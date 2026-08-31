import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers
import AtlasCore

/// Scan a syllabus from the phone: pick pages → read them → review what was found → commit.
///
/// This is the door the spec calls out as *more* natural on a phone — the syllabus is
/// usually already a screenshot in the camera roll. Two pickers land in the same place:
/// Photos (`PhotosPicker`) and Files (`fileImporter`, which is where a PDF lives).
///
/// The review step is the point. Phase 1 allows exactly one review screen in Atlas and
/// this is it: nothing the model produced touches a class, a task list or the calendar
/// until the button at the bottom is pressed.
struct SyllabusScanSheet: View {
    @EnvironmentObject private var store: MobileStore
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
    /// The one inline message line — never a dialog on top of this sheet.
    @State private var message: String?

    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showPhotosPicker = false
    @State private var showFileImporter = false

    /// One page queued for the scan: the encoded image plus what to call it in the list.
    private struct ScannedPage: Identifiable {
        let id = UUID()
        let label: String
        let image: SyllabusScanImage
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                switch phase {
                case .pick:     pickStep
                case .scanning: scanningStep
                case .review:   reviewStep
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
        }
        .background(MobileTheme.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .photosPicker(isPresented: $showPhotosPicker,
                      selection: $photoSelection,
                      maxSelectionCount: SyllabusScan.maxImages,
                      matching: .images)
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            Task { await addPhotos(items) }
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.pdf, .png, .jpeg, .heic, .webP],
                      allowsMultipleSelection: true) { result in
            addFiles(result)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(phase == .review ? "Here's what the syllabus says" : "Scan a syllabus")
                    .edScreenTitle()
                Text(phase == .review
                     ? "Nothing is added until you say so. Uncheck anything you don't want."
                     : "A photo or a PDF. Atlas reads the meeting times, the work, and the policies.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button { dismiss() } label: {
                Text(phase == .review ? "Discard" : "Cancel").edCapsLabel()
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 24)
    }

    // MARK: - Step 1 · pages

    @ViewBuilder
    private var pickStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            pickButton("Choose from Photos", symbol: "photo.on.rectangle") { showPhotosPicker = true }
            pickButton("Choose a file or PDF", symbol: "doc.badge.plus") { showFileImporter = true }
        }

        if !pages.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(pages.count) \(pages.count == 1 ? "page" : "pages")")
                    .edCapsLabel()
                    .padding(.bottom, 8)
                ForEach(pages) { page in
                    HStack(spacing: 10) {
                        Image(systemName: "doc").font(.system(size: 13, weight: .medium))
                        Text(page.label)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(sizeLabel(page.image.byteCount))
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(MobileTheme.faint)
                        Button { pages.removeAll { $0.id == page.id }; message = nil } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(MobileTheme.faint)
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(MobileTheme.muted)
                    .padding(.vertical, 10)
                    .edHairlineBelow()
                }
            }
            .padding(.top, 24)
        }

        Text("Up to \(SyllabusScan.maxImages) pages. A long syllabus scans best as the first few pages — the schedule and the grading table.")
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(MobileTheme.faint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 20)

        messageLine

        primaryButton("Read it", enabled: !pages.isEmpty) { runScan() }
    }

    private func pickButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                Text(title).font(.system(size: 15.5, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(MobileTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusControl, style: .continuous)
                .strokeBorder(MobileTheme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var scanningStep: some View {
        VStack(spacing: 12) {
            AtlasLoader(size: 26)
            Text("Reading \(pages.count) \(pages.count == 1 ? "page" : "pages")…")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Step 2 · review

    @ViewBuilder
    private var reviewStep: some View {
        if truncated {
            Text("Some pages were cut off — scan the rest separately if something's missing.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.warning)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)
        }
        if groups.isEmpty {
            Text("Nothing readable came back. A sharper photo of the schedule page usually does it.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach($groups) { $group in
            groupSection($group)
        }
        messageLine
        primaryButton(commitLabel, enabled: canCommit) { commit() }
    }

    private func groupSection(_ group: Binding<SyllabusDraftGroup>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            groupHeader(group)

            if !group.wrappedValue.meetingPattern.isEmpty {
                acceptRow(title: "Meeting times", on: group.includeMeetingPattern) {
                    ForEach(Array(group.wrappedValue.meetingPattern.enumerated()), id: \.offset) { _, block in
                        Text(MeetingPatternFormat.describe(block)
                             + (block.location.map { $0.isEmpty ? "" : " · \($0)" } ?? ""))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(MobileTheme.muted)
                    }
                }
            }

            if let info = group.wrappedValue.classInfo {
                acceptRow(title: "Class info", on: group.includeClassInfo) {
                    ForEach(infoLines(info), id: \.self) { line in
                        Text(line)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(MobileTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !group.wrappedValue.items.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Work").edCapsLabel()
                    ForEach(group.items) { $item in
                        itemRow($item)
                    }
                }
            }
        }
        .padding(.bottom, 18)
        .edHairlineBelow()
        .padding(.bottom, 22)
    }

    private func groupHeader(_ group: Binding<SyllabusDraftGroup>) -> some View {
        HStack(spacing: 10) {
            Text(group.wrappedValue.detectedLabel.isEmpty ? "Unnamed class"
                                                          : group.wrappedValue.detectedLabel)
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
            Spacer(minLength: 8)
            Menu {
                ForEach(targetChoices) { klass in
                    Button(klass.name) { group.wrappedValue.targetClassID = klass.id }
                }
            } label: {
                Text("→ " + (targetName(group.wrappedValue.targetClassID) ?? "Pick a class"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.accentText)
                    .lineLimit(1)
            }
        }
    }

    /// A toggleable block of already-shaped content (meeting times, the info card).
    private func acceptRow<Content: View>(title: String,
                                          on: Binding<Bool>,
                                          @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            checkbox(on)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).edCapsLabel()
                content()
            }
            Spacer(minLength: 0)
        }
        .opacity(on.wrappedValue ? 1 : 0.45)
    }

    private func itemRow(_ item: Binding<SyllabusDraftItem>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                checkbox(item.include)
                // Thumb-sized Task/Event chip — the phone's version of the Mac's toggle.
                Button {
                    MobileTheme.Haptic.selection()
                    item.wrappedValue.kind = item.wrappedValue.kind == .task ? .event : .task
                } label: {
                    Text(item.wrappedValue.kind.label)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(MobileTheme.muted)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
                            .strokeBorder(MobileTheme.hairline, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                TextField("Title", text: item.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                    .tint(MobileTheme.accent)
            }
            if item.wrappedValue.date == nil {
                Button { item.wrappedValue.date = defaultItemDate() } label: {
                    Text("No date — tap to set one")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(MobileTheme.warning)
                }
                .buttonStyle(.plain)
                .padding(.leading, 34)
            } else {
                DatePicker("", selection: Binding(get: { item.wrappedValue.date ?? Date() },
                                                  set: { item.wrappedValue.date = $0 }),
                           displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .padding(.leading, 34)
            }
        }
        .opacity(item.wrappedValue.include ? 1 : 0.45)
    }

    private func checkbox(_ on: Binding<Bool>) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            Image(systemName: on.wrappedValue ? "checkmark.square.fill" : "square")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(on.wrappedValue ? MobileTheme.ink : MobileTheme.faint)
        }
        .buttonStyle(.plain)
    }

    private func primaryButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .foregroundStyle(enabled ? MobileTheme.ink : MobileTheme.faint)
                .frame(maxWidth: .infinity)
                .edOutlineControl()
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .padding(.top, 28)
        .padding(.bottom, 40)
    }

    @ViewBuilder
    private var messageLine: some View {
        if let message {
            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.warning)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
    }

    // MARK: - Choices

    /// The classes a group can be filed under: the class's own term when it has one,
    /// else every live class (a class awaiting the term prompt still needs a target).
    private var targetChoices: [Project] {
        let term = project.termID.flatMap { id in store.terms.first { $0.id == id } } ?? store.activeTerm
        if let term {
            let inTerm = store.classes(in: term)
            if !inTerm.isEmpty { return inTerm }
        }
        return store.snapshot.projects.filter { $0.isClass && $0.archivedAt == nil }
    }

    private func targetName(_ id: UUID?) -> String? {
        id.flatMap { pid in store.snapshot.projects.first { $0.id == pid }?.name }
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

    /// A blank date starts at today, 11:59 PM — the hour a syllabus usually means by "due".
    private func defaultItemDate() -> Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: Date()) ?? Date()
    }

    private func sizeLabel(_ bytes: Int) -> String {
        bytes < 1_000_000 ? "\(bytes / 1000) KB"
                          : String(format: "%.1f MB", Double(bytes) / 1_000_000)
    }

    // MARK: - Picking pages

    /// Camera-roll pages. `PhotosPickerItem` hands back raw bytes; the UTType it reports
    /// is the media type the endpoint needs, defaulting to PNG when it says nothing.
    private func addPhotos(_ items: [PhotosPickerItem]) async {
        message = nil
        var index = 1
        for item in items {
            guard pages.count < SyllabusScan.maxImages else {
                message = "Atlas reads at most \(SyllabusScan.maxImages) pages at a time — the rest weren't added."
                break
            }
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                message = "Couldn't read one of those photos."
                continue
            }
            let type = item.supportedContentTypes.first
            let media = type?.preferredMIMEType ?? "image/png"
            pages.append(ScannedPage(label: "Photo \(index)",
                                     image: SyllabusScanImage(bytes: data, mediaType: media)))
            sources.append(SyllabusPages.Source(name: "Photo \(index).\(type?.preferredFilenameExtension ?? "png")",
                                                data: data,
                                                isPDF: false))
            index += 1
        }
        photoSelection = []
        if let error = validationMessage() { message = error }
    }

    /// Files-app pages. A PDF is rasterized here — the endpoint is images only.
    private func addFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else {
            message = "Couldn't open that file."
            return
        }
        message = nil
        for url in urls {
            let room = SyllabusScan.maxImages - pages.count
            guard room > 0 else {
                message = "Atlas reads at most \(SyllabusScan.maxImages) pages at a time — the rest weren't added."
                break
            }
            // Files handed over by the importer live outside the sandbox until asked for.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                pages.append(contentsOf: try SyllabusPages.read(url, limit: room)
                    .map { ScannedPage(label: $0.label, image: $0.image) })
                if let source = try? SyllabusPages.source(url) { sources.append(source) }
            } catch {
                message = "Couldn't read \(url.lastPathComponent)."
            }
        }
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
        guard store.session != nil else {
            message = "Sign in to Atlas to scan a syllabus."
            return
        }
        message = nil
        phase = .scanning
        let images = pages.map(\.image)
        let term = store.activeTerm

        Task { @MainActor in
            do {
                let response = try await SyllabusScan(session: { store.session })
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
            guard let targetID = group.targetClassID,
                  let klass = store.snapshot.projects.first(where: { $0.id == targetID }) else { continue }

            if group.includeMeetingPattern && !group.meetingPattern.isEmpty {
                store.setMeetingPattern(projectID: targetID,
                                        blocks: group.meetingPattern,
                                        meetingInfo: klass.meetingInfo)
            }
            if group.includeClassInfo, let info = group.classInfo {
                store.setClassInfo(projectID: targetID, info: info)
            }
            for item in group.includedItems {
                // An event needs an instant to sit on. Without one it commits as an
                // undated task instead of being silently dropped.
                if item.kind == .event, let start = item.date {
                    let event = CalendarEvent(title: item.title,
                                              subtitle: klass.code ?? klass.name,
                                              start: start,
                                              end: SyllabusDraft.eventEnd(for: start),
                                              color: classColor(klass),
                                              spaceName: klass.spaceName,
                                              notes: item.notes,
                                              projectID: klass.id,
                                              spaceID: klass.spaceID)
                    Task { await store.addEvent(event) }
                } else {
                    var task = TaskItem(title: item.title,
                                        dueLabel: TaskItem.dueLabel(for: item.date),
                                        dueDate: item.date)
                    task.spaceName   = klass.spaceName
                    task.spaceColor  = classColor(klass)
                    task.spaceID     = klass.spaceID
                    task.projectID   = klass.id
                    task.projectName = klass.name
                    task.notes       = item.notes ?? ""
                    Task { await store.addTask(task) }
                }
            }
        }
        keepTheSyllabus()
        MobileTheme.Haptic.success()
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
              let session = store.session else { return }

        Task { @MainActor in
            do {
                let path = try await SyllabusStorage.upload(file.data,
                                                            contentType: file.contentType,
                                                            fileExtension: file.fileExtension,
                                                            projectID: owner,
                                                            session: session)
                store.setSyllabusPath(projectID: owner, path: path)
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
/// course packet is not a scan. UIKit twin of the Mac's `SyllabusPages`.
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
        let media = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
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
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            guard let png = page.thumbnail(of: size, for: .mediaBox).pngData() else { return nil }
            return Page(label: "\(url.lastPathComponent) · page \(index + 1)",
                        image: SyllabusScanImage(bytes: png, mediaType: "image/png"))
        }
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
    /// handful of photos become one PDF, because a class has one syllabus, not five.
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
            } else if let image = UIImage(data: source.data), let page = PDFPage(image: image) {
                out.insert(page, at: out.pageCount)
            }
        }
        return out.pageCount > 0 ? out.dataRepresentation() : nil
    }
}
