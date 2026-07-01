import SwiftUI
import AtlasCore

/// The Schedule home (spec §4.1): a day header with nav + swipe, the shared space
/// filter, a "Needs a time" block pinned on top, and the day's timeline. Opens on
/// today; the calendar glyph pushes a month page for jumping days.
struct ScheduleView: View {
    @EnvironmentObject private var store: MobileStore

    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var showMonth = false
    @State private var timing: TaskItem?

    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            header
            list
        }
        .background(MobileTheme.bg.ignoresSafeArea())
        .sheet(isPresented: $showMonth) {
            MonthPageView(selected: selectedDay) { selectedDay = $0 }
        }
        .sheet(item: $timing) { task in
            SetTimeSheet(task: task, day: selectedDay) { updated in
                Task { await store.updateTask(updated) }
            }
        }
        .onAppear(perform: consumeFocusToday)
        .onChange(of: store.scheduleFocusToday) { _, _ in consumeFocusToday() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button { changeDay(-1) } label: { chevron("chevron.left") }
                Text(dayLabel)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .tracking(-0.5)
                    .foregroundStyle(MobileTheme.ink)
                    .layoutPriority(1)
                Button { changeDay(1) } label: { chevron("chevron.right") }
                Spacer()
            }

            HStack(spacing: 14) {
                Text("\(leftCount) left").edCapsLabel()
                Spacer()
                spaceFilterMenu
                Button { showMonth = true } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(MobileTheme.ink)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MobileTheme.ink).frame(height: MobileTheme.rule)   // strong header rule
        }
    }

    private func chevron(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(MobileTheme.ink)
            .frame(width: 30, height: 30)
    }

    private var spaceFilterMenu: some View {
        Menu {
            Button("All spaces") { store.spaceFilter = nil }
            ForEach(store.snapshot.spaces) { space in
                Button(space.name) { store.spaceFilter = space.id }
            }
        } label: {
            HStack(spacing: 6) {
                if let space = filterSpace {
                    Circle().fill(space.color).frame(width: 8, height: 8)
                }
                Text(filterSpace?.name ?? "All")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.88).textCase(.uppercase)
                    .foregroundStyle(MobileTheme.muted)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MobileTheme.faint)
            }
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            NeedsTimeSection(tasks: needsTime) { timing = $0 }
            DayTimelineView(
                day: selectedDay,
                now: Date(),
                events: filteredEvents,
                tasks: filteredTasks,
                onToggle: toggle,
                onDelete: delete
            )
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .simultaneousGesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.5,
                          abs(value.translation.width) > 50 else { return }
                    changeDay(value.translation.width < 0 ? 1 : -1)
                }
        )
    }

    // MARK: - Data (space-filtered)

    private var filterSpace: Space? {
        guard let id = store.spaceFilter else { return nil }
        return store.snapshot.spaces.first { $0.id == id }
    }

    private func inFilter(_ spaceName: String) -> Bool {
        guard let name = filterSpace?.name else { return true }
        return spaceName.caseInsensitiveCompare(name) == .orderedSame
    }

    private var filteredEvents: [CalendarEvent] { store.snapshot.events.filter { inFilter($0.spaceName) } }
    private var filteredTasks: [TaskItem] { store.snapshot.tasks.filter { inFilter($0.spaceName) } }

    /// Tasks due on the shown day with no time yet.
    private var needsTime: [TaskItem] {
        filteredTasks
            .filter { task in
                guard let due = task.dueDate, task.scheduledAt == nil, !task.done else { return false }
                return cal.isDate(due, inSameDayAs: selectedDay)
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// "N left" — incomplete tasks for the day (needs-a-time + timed, not done).
    private var leftCount: Int {
        let timed = filteredTasks.filter { task in
            guard let at = task.scheduledAt, !task.done else { return false }
            return cal.isDate(at, inSameDayAs: selectedDay)
        }
        return needsTime.count + timed.count
    }

    private var dayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: selectedDay)
    }

    // MARK: - Actions

    private func changeDay(_ delta: Int) {
        if let next = cal.date(byAdding: .day, value: delta, to: selectedDay) {
            withAnimation(.easeInOut(duration: 0.18)) { selectedDay = next }
        }
    }

    private func toggle(_ task: TaskItem) {
        var updated = task
        updated.done.toggle()
        Task { await store.updateTask(updated) }
    }

    private func delete(_ task: TaskItem) {
        Task { await store.deleteTask(id: task.id) }
    }

    private func consumeFocusToday() {
        guard store.scheduleFocusToday else { return }
        store.scheduleFocusToday = false
        selectedDay = cal.startOfDay(for: Date())
    }
}
