import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import AtlasCore

/// Scan a syllabus: choose pages → read them → review what was found → commit.
///
/// The review step is the point. Phase 1 allows exactly one review screen in Atlas and
/// this is it: nothing the model produced touches a class, a task list or the calendar
/// until the button at the bottom is pressed.
struct SyllabusScanSheet: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    /// The class the scan was launched from — every detected group starts pointed here.
    let project: Project

    private enum Phase { case pick, scanning, review }

    @State private var phase: Phase = .pick
    @State private var pages: [ScannedPage] = []
    /// The files the user actually picked, kept verbatim. The pages above are rasterized
    /// for the model; THIS is what gets stored so the syllabus can be read again later.
    @State private var sources: [SyllabusPages.Source] = []
    @State private var groups: [SyllabusDraftGroup] = []
    @State private var truncated = false
    /// The one inline message line — never a dialog on top of this dialog.
    @State private var message: String?

    /// One page queued for the scan: the encoded image plus what to call it in the list.
    private struct ScannedPage: Identifiable {
        let id = UUID()
        let label: String
        let image: SyllabusScanImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AtlasTheme.Colors.hairline)
            Group {
                switch phase {
                case .pick:     pickStep
                case .scanning: scanningStep
                case .review:   reviewStep
                }
            }
        }
        .frame(width: 560, height: 560, alignment: .topLeading)
        .background(AtlasTheme.Colors.bgBase)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(phase == .review ? "Here's what the syllabus says" : "Scan a syllabus")
                    .atlasFont(size: 18, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Text(phase == .review
                     ? "Nothing is added until you say so. Uncheck anything you don't want."
                     : "A PDF or a screenshot. Atlas reads the meeting times, the work, and the policies.")
                    .atlasFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(phase == .review ? "Discard" : "Cancel") { dismiss() }
                .buttonStyle(.plain)
                .atlasFont(size: 14, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 18)
    }

    // MARK: - Step 1 · pages

    private var pickStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Button(action: choosePages) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.badge.plus").atlasFont(size: 12, weight: .semibold)
                            Text(pages.isEmpty ? "Choose a PDF or images…" : "Add more pages…")
                                .atlasFont(size: 13, weight: .semibold, design: .rounded)
                        }
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .overlay(RoundedRectangle(cornerRadius: AtlasTheme.Radius.control, style: .continuous)
                            .strokeBorder(AtlasTheme.Colors.border,
                                          style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    .buttonStyle(.plain)

                    if !pages.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(pages.count) \(pages.count == 1 ? "PAGE" : "PAGES")").atlasCapsLabel()
                            ForEach(pages) { page in
                                HStack(spacing: 8) {
                                    Image(systemName: "doc").atlasFont(size: 11)
                                    Text(page.label)
                                        .atlasFont(size: 13, weight: .medium, design: .rounded)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(sizeLabel(page.image.byteCount))
                                        .atlasMono(size: 11)
                                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                                    Button { pages.removeAll { $0.id == page.id }; message = nil } label: {
                                        Image(systemName: "minus.circle")
                                            .atlasFont(size: 12)
                                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                            }
                        }
                    }

                    Text("Up to \(SyllabusScan.maxImages) pages. A long syllabus scans best as the first few pages — the schedule and the grading table.")
                        .atlasFont(size: 11, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    messageLine
                }
                .padding(24)
            }
            Spacer(minLength: 0)
            footer {
                Button { runScan() } label: {
                    Text("Read it")
                        .atlasFont(size: 14, weight: .semibold, design: .rounded)
                        .foregroundStyle(pages.isEmpty ? AtlasTheme.Colors.textMuted
                                                       : AtlasTheme.Colors.accentText)
                }
                .buttonStyle(.plain)
                .disabled(pages.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private var scanningStep: some View {
        VStack(spacing: 12) {
            Spacer()
            AtlasLoader(size: 26)
            Text("Reading \(pages.count) \(pages.count == 1 ? "page" : "pages")…")
                .atlasFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Step 2 · review

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if truncated {
                        Text("Some pages were cut off — scan the rest separately if something's missing.")
                            .atlasFont(size: 11, weight: .medium, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.late)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if groups.isEmpty {
                        Text("Nothing readable came back. A sharper screenshot of the schedule page usually does it.")
                            .atlasFont(size: 13, weight: .medium, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach($groups) { $group in
                        groupSection($group)
                    }
                    messageLine
                }
                .padding(24)
            }
            footer {
                Button { commit() } label: {
                    Text(commitLabel)
                        .atlasFont(size: 14, weight: .semibold, design: .rounded)
                        .foregroundStyle(canCommit ? AtlasTheme.Colors.accentText
                                                   : AtlasTheme.Colors.textMuted)
                }
                .buttonStyle(.plain)
                .disabled(!canCommit)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private func groupSection(_ group: Binding<SyllabusDraftGroup>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            groupHeader(group)

            if !group.wrappedValue.meetingPattern.isEmpty {
                acceptRow(title: "Meeting times", on: group.includeMeetingPattern) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(group.wrappedValue.meetingPattern.enumerated()), id: \.offset) { _, block in
                            Text(MeetingPatternFormat.describe(block)
                                 + (block.location.map { $0.isEmpty ? "" : " · \($0)" } ?? ""))
                                .atlasFont(size: 12, weight: .medium, design: .rounded)
                                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                        }
                    }
                }
            }

            if let info = group.wrappedValue.classInfo {
                acceptRow(title: "Class info", on: group.includeClassInfo) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(infoLines(info), id: \.self) { line in
                            Text(line)
                                .atlasFont(size: 12, design: .rounded)
                                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if !group.wrappedValue.items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("WORK").atlasCapsLabel()
                    ForEach(group.items) { $item in
                        itemRow($item)
                    }
                }
            }
        }
        .padding(.bottom, 4)
        .atlasHairlineBelow()
    }

    private func groupHeader(_ group: Binding<SyllabusDraftGroup>) -> some View {
        HStack(spacing: 8) {
            Text(group.wrappedValue.detectedLabel.isEmpty ? "Unnamed class"
                                                          : group.wrappedValue.detectedLabel)
                .atlasFont(size: 14, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Spacer()
            Menu {
                ForEach(targetChoices, id: \.id) { klass in
                    Button(klass.name) { group.wrappedValue.targetClassID = klass.id }
                }
            } label: {
                Text("→ " + (targetName(group.wrappedValue.targetClassID) ?? "Pick a class"))
                    .atlasFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.accentText)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    /// A toggleable block of already-shaped content (meeting times, the info card).
    private func acceptRow<Content: View>(title: String,
                                          on: Binding<Bool>,
                                          @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 8) {
            checkbox(on)
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased()).atlasCapsLabel()
                content()
            }
            Spacer(minLength: 0)
        }
        .opacity(on.wrappedValue ? 1 : 0.45)
    }

    private func itemRow(_ item: Binding<SyllabusDraftItem>) -> some View {
        HStack(spacing: 8) {
            checkbox(item.include)
            Button {
                item.wrappedValue.kind = item.wrappedValue.kind == .task ? .event : .task
            } label: {
                Text(item.wrappedValue.kind.label)
                    .atlasMono(size: 10, weight: .semibold)
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    .frame(width: 44, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(AtlasTheme.Colors.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Switch between a deadline you owe and something that happens at a time")

            TextField("Title", text: item.title)
                .textFieldStyle(.plain)
                .atlasFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)

            if item.wrappedValue.date == nil {
                Button { item.wrappedValue.date = defaultItemDate() } label: {
                    Text("No date")
                        .atlasFont(size: 12, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.late)
                }
                .buttonStyle(.plain)
                .help("The syllabus didn't say — click to set one")
            } else {
                DatePicker("", selection: Binding(get: { item.wrappedValue.date ?? Date() },
                                                  set: { item.wrappedValue.date = $0 }),
                           displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .atlasFont(size: 12, design: .rounded)
                    .fixedSize()
            }
        }
        .opacity(item.wrappedValue.include ? 1 : 0.45)
    }

    private func checkbox(_ on: Binding<Bool>) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            Image(systemName: on.wrappedValue ? "checkmark.square.fill" : "square")
                .atlasFont(size: 13)
                .foregroundStyle(on.wrappedValue ? AtlasTheme.Colors.textPrimary
                                                 : AtlasTheme.Colors.textMuted)
        }
        .buttonStyle(.plain)
    }

    private func footer<Content: View>(@ViewBuilder trailing: () -> Content) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(AtlasTheme.Colors.hairline)
            HStack {
                Spacer()
                trailing()
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
    }

    private var messageLine: some View {
        Group {
            if let message {
                Text(message)
                    .atlasFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.late)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Choices

    /// The classes a group can be filed under: the class's own term when it has one,
    /// else every live class (a class awaiting the term prompt still needs a target).
    private var targetChoices: [Project] {
        let term = project.termID.flatMap { id in state.terms.first { $0.id == id } } ?? state.activeTerm
        if let term {
            let inTerm = state.classes(in: term)
            if !inTerm.isEmpty { return inTerm }
        }
        return state.allProjects.filter { $0.isClass && $0.archivedAt == nil }
    }

    private func targetName(_ id: UUID?) -> String? {
        id.flatMap { state.project($0)?.name }
    }

    private var canCommit: Bool {
        groups.contains { $0.targetClassID != nil && $0.writesAnything }
    }

    private var commitLabel: String {
        let count = groups.filter { $0.targetClassID != nil }.reduce(0) { $0 + $1.includedItems.count }
        return count == 0 ? "Add to my classes" : "Add \(count) \(count == 1 ? "item" : "items")"
    }

    private func infoLines(_ info: ClassInfoCard) -> [String] {
        info.gradeWeights + info.policies + (info.officeHours.map { [$0] } ?? [])
    }

    /// A blank date starts at the term's next sensible day — today, at 11:59 PM, the
    /// hour a syllabus usually means by "due".
    private func defaultItemDate() -> Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: Date()) ?? Date()
    }

    private func sizeLabel(_ bytes: Int) -> String {
        bytes < 1_000_000 ? "\(bytes / 1000) KB"
                          : String(format: "%.1f MB", Double(bytes) / 1_000_000)
    }

    // MARK: - Picking pages

    private func choosePages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .png, .jpeg, .heic, .webP]
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }

        message = nil
        for url in panel.urls {
            let room = SyllabusScan.maxImages - pages.count
            guard room > 0 else {
                message = "Atlas reads at most \(SyllabusScan.maxImages) pages at a time — the rest weren't added."
                break
            }
            do {
                pages.append(contentsOf: try SyllabusPages.read(url, limit: room)
                    .map { ScannedPage(label: $0.label, image: $0.image) })
                if let source = try? SyllabusPages.source(url) { sources.append(source) }
            } catch {
                message = "Couldn't read \(url.lastPathComponent)."
            }
        }
        // Surface the size cap here rather than after an upload that's going to 413.
        if let error = validationMessage() { message = error }
    }

    private func validationMessage() -> String? {
        do {
            try SyllabusScan.validate(pages.map(\.image))
            return nil
        } catch AtlasAIError.noImages {
            return nil   // the button is already disabled; no need to scold
        } catch {
            return "That's more than Atlas can read at once — remove a page or two."
        }
    }

    // MARK: - Scanning

    private func runScan() {
        if let error = validationMessage() { message = error; return }
        guard auth.session != nil else {
            message = "Sign in to Atlas to scan a syllabus."
            return
        }
        message = nil
        phase = .scanning
        let images = pages.map(\.image)
        let term = state.activeTerm

        Task { @MainActor in
            do {
                let response = try await SyllabusScan(session: { auth.session })
                    .scan(images: images, termStart: term?.startsOn, termEnd: term?.endsOn)
                groups = SyllabusDraft.groups(from: response, defaultTarget: project.id)
                truncated = response.truncated
                phase = .review
            } catch let error as AtlasAIError {
                message = plainLanguage(error)
                phase = .pick
            } catch {
                message = "Atlas couldn't reach the scanner. Check your connection and try again."
                phase = .pick
            }
        }
    }

    /// Server failures in words a student can act on — no status codes, no dialogs.
    private func plainLanguage(_ error: AtlasAIError) -> String {
        switch error {
        case .rateLimited:
            return "Too many scans just now — give it a minute and try again."
        case .tooLong, .imagesTooLarge:
            return "Those pages are too big to read at once — try fewer, or a smaller PDF."
        case .noImages:
            return "Add at least one page to scan."
        case .notAuthenticated:
            return "Sign in to Atlas to scan a syllabus."
        case .serverUnavailable, .parseFailed, .httpError:
            return "The scanner had trouble with that one. Try again in a moment."
        }
    }

    // MARK: - Commit (the ONLY place anything is written)

    private func commit() {
        for group in groups {
            guard let targetID = group.targetClassID, let klass = state.project(targetID) else { continue }

            if group.includeMeetingPattern && !group.meetingPattern.isEmpty {
                state.setMeetingPattern(projectID: targetID,
                                        blocks: group.meetingPattern,
                                        meetingInfo: klass.meetingInfo)
            }
            if group.includeClassInfo, let info = group.classInfo {
                state.setClassInfo(projectID: targetID, info: info)
            }
            for item in group.includedItems {
                // An event needs an instant to sit on. Without one it commits as an
                // undated task instead of being silently dropped.
                if item.kind == .event, let start = item.date {
                    state.addEvent(CalendarEvent(title: item.title,
                                                 subtitle: klass.code ?? klass.name,
                                                 start: start,
                                                 end: SyllabusDraft.eventEnd(for: start),
                                                 color: classColor(klass),
                                                 spaceName: klass.spaceName,
                                                 notes: item.notes,
                                                 projectID: klass.id,
                                                 spaceID: klass.spaceID))
                } else {
                    let task = state.addTask(title: item.title,
                                             dueDate: item.date,
                                             spaceName: klass.spaceName,
                                             projectName: klass.name)
                    if let notes = item.notes, !notes.isEmpty {
                        state.updateTaskNotes(taskId: task.id, notes: notes)
                    }
                }
            }
        }
        keepTheSyllabus()
        dismiss()
    }

    /// Store the document this scan was read from, so the class page can show it later.
    /// Best-effort and fire-and-forget: the scan's real product is already committed, and
    /// a storage hiccup must never cost the user their review. The pointer is written only
    /// after the upload succeeds.
    private func keepTheSyllabus() {
        let targets = groups.compactMap(\.targetClassID)
        // The syllabus belongs to the class you were standing on, unless the scan was
        // filed somewhere else entirely.
        guard let owner = targets.contains(project.id) ? project.id : targets.first,
              let file = SyllabusPages.package(sources),
              let session = auth.session else { return }

        Task { @MainActor in
            do {
                let path = try await SyllabusStorage.upload(file.data,
                                                            contentType: file.contentType,
                                                            fileExtension: file.fileExtension,
                                                            projectID: owner,
                                                            session: session)
                state.setSyllabusPath(projectID: owner, path: path)
            } catch {
                AtlasLog.append("syllabus upload failed: \(error)")
            }
        }
    }

    private func classColor(_ klass: Project) -> Color {
        klass.colorToken.map { ColorToken.color(for: $0) } ?? klass.spaceColor
    }
}

/// Turning what the user picked into pages the scan endpoint accepts. The endpoint is
/// images only, so a PDF is rasterized here — page by page, capped, because a 60-page
/// course packet is not a scan.
enum SyllabusPages {
    struct Page {
        let label: String
        let image: SyllabusScanImage
    }

    /// The long edge a rasterized PDF page is rendered at: enough for syllabus body text
    /// to read cleanly, small enough that ten pages fit under the size cap.
    static let renderLongEdge: CGFloat = 1600

    static func read(_ url: URL, limit: Int) throws -> [Page] {
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
            return try rasterize(url, limit: limit)
        }
        let data = try Data(contentsOf: url)
        let type = UTType(filenameExtension: url.pathExtension)
        let media = type.flatMap { $0.preferredMIMEType } ?? "image/png"
        return [Page(label: url.lastPathComponent,
                     image: SyllabusScanImage(bytes: data, mediaType: media))]
    }

    private static func rasterize(_ url: URL, limit: Int) throws -> [Page] {
        guard let doc = PDFDocument(url: url) else { throw CocoaError(.fileReadCorruptFile) }
        let count = min(doc.pageCount, limit)
        return (0..<count).compactMap { index in
            guard let page = doc.page(at: index) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let scale = renderLongEdge / max(bounds.width, bounds.height, 1)
            let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
            guard let png = pngData(page.thumbnail(of: size, for: .mediaBox)) else { return nil }
            return Page(label: "\(url.lastPathComponent) · page \(index + 1)",
                        image: SyllabusScanImage(bytes: png, mediaType: "image/png"))
        }
    }

    private static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Keeping the original

    /// One file exactly as the user picked it — never the rasterized pages. This is what
    /// gets stored, so a policy can be re-read in the professor's own document.
    struct Source {
        let name: String
        let data: Data
        let isPDF: Bool
        var fileExtension: String { (name as NSString).pathExtension.lowercased() }
    }

    static func source(_ url: URL) throws -> Source {
        let isPDF = UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true
        return Source(name: url.lastPathComponent, data: try Data(contentsOf: url), isPDF: isPDF)
    }

    /// The single object to store for a scan. One picked file is kept byte-for-byte; a
    /// handful of pages become one PDF, because a class has one syllabus, not five.
    static func package(_ sources: [Source]) -> (data: Data, contentType: String, fileExtension: String)? {
        guard !sources.isEmpty else { return nil }
        if sources.count == 1 {
            let only = sources[0]
            let ext = only.fileExtension.isEmpty ? (only.isPDF ? "pdf" : "png") : only.fileExtension
            let mime = UTType(filenameExtension: ext)?.preferredMIMEType
                ?? (only.isPDF ? "application/pdf" : "image/png")
            return (only.data, mime, ext)
        }
        guard let merged = mergedPDF(sources) else { return nil }
        return (merged, "application/pdf", "pdf")
    }

    private static func mergedPDF(_ sources: [Source]) -> Data? {
        let out = PDFDocument()
        for source in sources {
            if source.isPDF, let doc = PDFDocument(data: source.data) {
                for index in 0..<doc.pageCount {
                    guard let page = doc.page(at: index) else { continue }
                    out.insert(page, at: out.pageCount)
                }
            } else if let image = NSImage(data: source.data), let page = PDFPage(image: image) {
                out.insert(page, at: out.pageCount)
            }
        }
        return out.pageCount > 0 ? out.dataRepresentation() : nil
    }
}
