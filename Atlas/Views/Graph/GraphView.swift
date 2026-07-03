import SwiftUI
import AtlasCore

// MARK: - Graph model

/// A single node in the relationship graph. Wraps an existing Atlas entity —
/// the graph derives entirely from data already in `AppState`, no new persistence.
struct GraphNode: Identifiable {
    enum Kind: String {
        case space, project, task, note, event, goal

        /// Drawn radius (graph-space units). Bigger = more central in the hierarchy.
        var radius: CGFloat {
            switch self {
            case .space:   return 24
            case .project: return 16
            case .goal:    return 12
            case .note:    return 9
            case .event:   return 9
            case .task:    return 8
            }
        }
        /// Whether this kind always shows a label (else only when selected/zoomed).
        var alwaysLabeled: Bool { self == .space || self == .project }
    }

    let id: UUID
    var kind: Kind
    var label: String
    var color: Color
}

/// An undirected edge between two nodes, with a desired rest length / pull weight.
struct GraphEdge: Identifiable {
    let id = UUID()
    let from: UUID
    let to: UUID
    var weight: Double = 1.0
}

/// Pure derivation of nodes + edges from the app's existing relationships.
/// Deterministic and side-effect free so it can be unit-tested without a view.
enum GraphSnapshot {
    /// Upper bound so a pathologically large account can't stall the layout.
    static let nodeCap = 400

    static func build(spaces: [Space],
                      tasks: [TaskItem],
                      notes: [Note],
                      events: [CalendarEvent],
                      goals: [Goal]) -> (nodes: [GraphNode], edges: [GraphEdge]) {
        var nodes: [GraphNode] = []
        var edges: [GraphEdge] = []
        var seen = Set<UUID>()
        // Title index (lowercased) → node id, for [[mention]] + NoteRef matching.
        var byTitle: [String: UUID] = [:]

        func add(_ node: GraphNode) {
            guard !seen.contains(node.id), nodes.count < nodeCap else { return }
            seen.insert(node.id)
            nodes.append(node)
            let key = node.label.lowercased()
            if byTitle[key] == nil { byTitle[key] = node.id }
        }
        func link(_ a: UUID, _ b: UUID, weight: Double = 1.0) {
            guard a != b, seen.contains(a), seen.contains(b) else { return }
            edges.append(GraphEdge(from: a, to: b, weight: weight))
        }

        // Spaces → Projects → Assignments (project-scoped tasks).
        for space in spaces {
            add(GraphNode(id: space.id, kind: .space, label: space.name, color: space.color))
            for project in space.projects {
                add(GraphNode(id: project.id, kind: .project, label: project.name, color: project.spaceColor))
                link(space.id, project.id, weight: 2.2)
                for assignment in project.assignments {
                    add(GraphNode(id: assignment.id, kind: .task, label: assignment.title, color: project.spaceColor))
                    link(project.id, assignment.id)
                }
                // Project note references → match to a real Note node by title.
                for ref in project.notes {
                    if let noteID = byTitle[ref.title.lowercased()] {
                        link(project.id, noteID, weight: 1.4)
                    }
                }
            }
        }

        // Flat (dashboard) tasks → link to their space by name.
        let spaceByName = Dictionary(spaces.map { ($0.name, $0.id) }, uniquingKeysWith: { a, _ in a })
        for task in tasks {
            add(GraphNode(id: task.id, kind: .task, label: task.title, color: task.spaceColor))
            if let sid = spaceByName[task.spaceName] { link(sid, task.id) }
        }

        // Notes → link to space by name (when set).
        for note in notes {
            add(GraphNode(id: note.id, kind: .note, label: note.title,
                          color: AtlasTheme.Colors.textSecondary))
            if let name = note.spaceName, let sid = spaceByName[name] { link(sid, note.id, weight: 1.2) }
        }

        // Events → link to a project (via projectID) or fall back to space by name.
        for event in events {
            add(GraphNode(id: event.id, kind: .event, label: event.title, color: event.color))
            if let pid = event.projectID, seen.contains(pid) {
                link(pid, event.id)
            } else if let sid = spaceByName[event.spaceName] {
                link(sid, event.id)
            }
        }

        // Goals — standalone for now (no persisted links yet).
        for goal in goals {
            add(GraphNode(id: goal.id, kind: .goal, label: goal.title, color: AtlasTheme.Colors.accent))
        }

        // [[mentions]] inside note bodies → edge to any node sharing that title.
        for note in notes where seen.contains(note.id) {
            for mention in GraphSnapshot.mentions(in: note.body) {
                if let target = byTitle[mention.lowercased()], target != note.id {
                    link(note.id, target, weight: 1.0)
                }
            }
        }

        return (nodes, edges)
    }

    /// Extract `[[target]]` mention strings from free text.
    static func mentions(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
}

// MARK: - Force-directed layout engine

/// Lightweight spring/repulsion simulation. Positions live in graph space and
/// settle near the view centre. Not `@Published` per-frame — `TimelineView`
/// drives redraws; only `settled` is observed so the timeline can pause once calm.
@MainActor
final class GraphEngine: ObservableObject {
    @Published private(set) var settled = false

    private(set) var nodes: [GraphNode] = []
    private var edges: [(Int, Int, Double)] = []     // index pairs + weight
    private var index: [UUID: Int] = [:]
    private(set) var pos: [CGPoint] = []
    private var vel: [CGPoint] = []
    private var laidOut = false
    private var size: CGSize = .zero
    private var calmFrames = 0

    // Tunables.
    private let repulsion: Double = 5200
    private let springK: Double = 0.012
    private let centerK: Double = 0.006
    private let damping: Double = 0.86
    private let restLength: Double = 78
    private let maxSpeed: Double = 28

    func load(nodes: [GraphNode], edges: [GraphEdge]) {
        // Only rebuild if the node set actually changed (cheap id signature).
        let signature = nodes.map(\.id)
        if signature == self.nodes.map(\.id) { return }
        self.nodes = nodes
        index = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })
        self.edges = edges.compactMap { e in
            guard let a = index[e.from], let b = index[e.to] else { return nil }
            return (a, b, e.weight)
        }
        pos = Array(repeating: .zero, count: nodes.count)
        vel = Array(repeating: .zero, count: nodes.count)
        laidOut = false
        settled = false
        calmFrames = 0
    }

    /// Seed positions on a phyllotaxis-like spiral so nothing starts coincident.
    private func seedLayout(in size: CGSize) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let golden = Double.pi * (3 - 5.squareRoot())
        for i in nodes.indices {
            let r = 26.0 * Double(i).squareRoot()
            let a = Double(i) * golden
            pos[i] = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
        }
        laidOut = true
    }

    func ensureLaidOut(in size: CGSize) {
        self.size = size
        if !laidOut && !nodes.isEmpty { seedLayout(in: size) }
    }

    /// Wake the simulation (after a drag/zoom or a data change).
    func reheat() { if settled { settled = false }; calmFrames = 0 }

    func nodeIndex(of id: UUID) -> Int? { index[id] }

    func setPosition(_ p: CGPoint, at i: Int) {
        guard pos.indices.contains(i) else { return }
        pos[i] = p; vel[i] = .zero
    }

    func position(at i: Int) -> CGPoint { pos.indices.contains(i) ? pos[i] : .zero }

    /// Live edge endpoints (graph space) for rendering.
    func edgeEndpoints() -> [(CGPoint, CGPoint)] {
        edges.compactMap { (a, b, _) in
            guard pos.indices.contains(a), pos.indices.contains(b) else { return nil }
            return (pos[a], pos[b])
        }
    }

    /// One integration step. No-ops once settled or before layout.
    func step() {
        guard laidOut, !settled, nodes.count > 1 else { return }
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        var force = Array(repeating: CGPoint.zero, count: nodes.count)

        // Pairwise repulsion (O(n²); n is capped).
        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                var dx = Double(pos[i].x - pos[j].x)
                var dy = Double(pos[i].y - pos[j].y)
                var d2 = dx * dx + dy * dy
                if d2 < 0.01 { dx = Double(i - j) + 0.1; dy = 0.1; d2 = dx * dx + dy * dy }
                let inv = repulsion / d2
                let dist = d2.squareRoot()
                let fx = dx / dist * inv, fy = dy / dist * inv
                force[i].x += fx; force[i].y += fy
                force[j].x -= fx; force[j].y -= fy
            }
        }

        // Spring attraction along edges.
        for (a, b, w) in edges {
            let dx = Double(pos[b].x - pos[a].x)
            let dy = Double(pos[b].y - pos[a].y)
            let dist = max(0.01, (dx * dx + dy * dy).squareRoot())
            let f = springK * w * (dist - restLength)
            let fx = dx / dist * f, fy = dy / dist * f
            force[a].x += fx; force[a].y += fy
            force[b].x -= fx; force[b].y -= fy
        }

        // Gentle centring + integrate.
        var kinetic = 0.0
        for i in nodes.indices {
            force[i].x += Double(c.x - pos[i].x) * centerK
            force[i].y += Double(c.y - pos[i].y) * centerK
            var vx = (Double(vel[i].x) + force[i].x) * damping
            var vy = (Double(vel[i].y) + force[i].y) * damping
            let speed = (vx * vx + vy * vy).squareRoot()
            if speed > maxSpeed { vx = vx / speed * maxSpeed; vy = vy / speed * maxSpeed }
            vel[i] = CGPoint(x: vx, y: vy)
            pos[i].x += vx; pos[i].y += vy
            kinetic += vx * vx + vy * vy
        }

        // Settle once kinetic energy stays low for a few frames.
        if kinetic / Double(nodes.count) < 0.4 {
            calmFrames += 1
            if calmFrames > 24 { settled = true }
        } else {
            calmFrames = 0
        }
    }
}

// MARK: - Graph view

/// Obsidian-style relationship map of spaces, projects, tasks, notes, events and
/// goals. Presented as a sheet from the Metrics popup's logo button.
struct GraphView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var engine = GraphEngine()

    @State private var selected: UUID?
    @State private var scale: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var grabbed: Int?          // node index being dragged
    @State private var gestureStartPan: CGSize = .zero

    var body: some View {
        ZStack(alignment: .top) {
            AtlasTheme.Colors.bgBase.ignoresSafeArea()
            canvas
            header
            legend
        }
        .frame(minWidth: 720, minHeight: 540)
        .onAppear(perform: rebuild)
    }

    private func rebuild() {
        let (nodes, edges) = GraphSnapshot.build(
            spaces: state.spaces, tasks: state.tasks,
            notes: state.notes, events: state.events, goals: state.goals)
        engine.load(nodes: nodes, edges: edges)
    }

    // Screen ⇄ graph-space transform: screen = pos*scale + pan.
    private func toGraph(_ screen: CGPoint) -> CGPoint {
        CGPoint(x: (screen.x - pan.width) / scale, y: (screen.y - pan.height) / scale)
    }

    private var canvas: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: engine.settled)) { _ in
                Canvas { ctx, size in
                    engine.ensureLaidOut(in: size)
                    engine.step()
                    draw(into: ctx)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(in: geo.size))
            .gesture(MagnificationGesture()
                .onChanged { scale = max(0.4, min(2.4, $0)) }
                .onEnded { _ in engine.reheat() })
            .onAppear { engine.ensureLaidOut(in: geo.size) }
        }
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if grabbed == nil {
                    // Decide on first move: did we grab a node or the canvas?
                    let g = toGraph(value.startLocation)
                    grabbed = hitTest(g)
                    gestureStartPan = pan
                }
                if let i = grabbed {
                    engine.setPosition(toGraph(value.location), at: i)
                    engine.reheat()
                } else {
                    pan = CGSize(width: gestureStartPan.width + value.translation.width,
                                 height: gestureStartPan.height + value.translation.height)
                }
            }
            .onEnded { value in
                if grabbed == nil {
                    // A tap (no real drag) selects the node under the finger.
                    if abs(value.translation.width) < 3 && abs(value.translation.height) < 3 {
                        let g = toGraph(value.startLocation)
                        selected = hitTest(g).map { engine.nodes[$0].id }
                    }
                }
                grabbed = nil
            }
    }

    /// Nearest node whose radius contains the graph-space point.
    private func hitTest(_ g: CGPoint) -> Int? {
        var best: Int?; var bestD = Double.greatestFiniteMagnitude
        for i in engine.nodes.indices {
            let p = engine.position(at: i)
            let d = Double((p.x - g.x) * (p.x - g.x) + (p.y - g.y) * (p.y - g.y))
            let r = Double(engine.nodes[i].kind.radius + 6)
            if d < r * r && d < bestD { best = i; bestD = d }
        }
        return best
    }

    private func draw(into base: GraphicsContext) {
        var ctx = base
        ctx.translateBy(x: pan.width, y: pan.height)
        ctx.scaleBy(x: scale, y: scale)

        // Edges first (under nodes).
        for edge in engineEdges() {
            var path = Path()
            path.move(to: edge.0); path.addLine(to: edge.1)
            ctx.stroke(path, with: .color(AtlasTheme.Colors.border),
                       lineWidth: 0.8 / scale)
        }

        // Nodes.
        for i in engine.nodes.indices {
            let node = engine.nodes[i]
            let p = engine.position(at: i)
            let r = node.kind.radius
            let isSel = node.id == selected
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            if isSel {
                ctx.fill(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)),
                         with: .color(AtlasTheme.Colors.accent.opacity(0.28)))
            }
            ctx.fill(Path(ellipseIn: rect), with: .color(node.color))
            ctx.stroke(Path(ellipseIn: rect),
                       with: .color(AtlasTheme.Colors.bgBase), lineWidth: 1.5 / scale)

            if node.kind.alwaysLabeled || isSel || scale > 1.5 {
                let text = Text(node.label)
                    .font(.system(size: node.kind == .space ? 11 : 9,
                                  weight: node.kind == .space ? .semibold : .regular,
                                  design: .rounded))
                    .foregroundColor(isSel ? AtlasTheme.Colors.textPrimary
                                           : AtlasTheme.Colors.textSecondary)
                ctx.draw(text, at: CGPoint(x: p.x, y: p.y + r + 8), anchor: .top)
            }
        }
    }

    /// Edge endpoints in graph space (resolved each frame from live positions).
    private func engineEdges() -> [(CGPoint, CGPoint)] {
        // Rebuild light edge list from node adjacency captured at load time.
        // (GraphEngine keeps edges internally; expose endpoints via positions.)
        engine.edgeEndpoints()
    }

    // MARK: chrome

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                BrandLogo(size: 20)
                Text("Graph")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Text("\(engine.nodes.count) nodes")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            Spacer()
            Button { engine.reheat() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .frame(width: 24, height: 24)
                    .background(AtlasTheme.Colors.bgBase, in: Circle())
                    .overlay(Circle().strokeBorder(AtlasTheme.Colors.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Re-run layout")
            Button { state.presentGraph = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .frame(width: 24, height: 24)
                    .background(AtlasTheme.Colors.bgBase, in: Circle())
                    .overlay(Circle().strokeBorder(AtlasTheme.Colors.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    private var legend: some View {
        let items: [(String, Color)] = [
            ("Space", AtlasTheme.Colors.accent),
            ("Project", AtlasTheme.Colors.school),
            ("Task", AtlasTheme.Colors.side),
            ("Note", AtlasTheme.Colors.textSecondary),
            ("Event", AtlasTheme.Colors.personal),
        ]
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.0) { item in
                HStack(spacing: 7) {
                    Circle().fill(item.1).frame(width: 8, height: 8)
                    Text(item.0).font(.system(size: 10, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
            }
        }
        .padding(10)
        .background(AtlasTheme.Colors.bgBase.opacity(0.92),
                    in: RoundedRectangle(cornerRadius: AtlasTheme.Radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AtlasTheme.Radius.sm, style: .continuous)
            .strokeBorder(AtlasTheme.Colors.border, lineWidth: 1))
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}
