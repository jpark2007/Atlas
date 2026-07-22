import SwiftUI
import WidgetKit

/// Dismissible "Get started" card on the Schedule home. Four core items auto-check
/// from the same actions the tips donate; a soft widget bonus never blocks 4/4.
struct GetStartedCard: View {
    @AppStorage("checklist.connected") private var connected = false
    @AppStorage("checklist.captured")  private var captured = false
    @AppStorage("checklist.scheduled") private var scheduled = false
    @AppStorage("checklist.month")     private var month = false
    @AppStorage("checklist.dismissed") private var dismissed = false

    @State private var widgetAdded = false

    private var doneCount: Int { [connected, captured, scheduled, month].filter { $0 }.count }
    private var complete: Bool { doneCount == 4 }

    var body: some View {
        if dismissed || complete {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Get started")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                    Spacer()
                    Text("\(doneCount) of 4")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(MobileTheme.muted)
                    Button { dismissed = true } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                            .foregroundStyle(MobileTheme.faint)
                    }.buttonStyle(.plain)
                }
                row(connected, "Connect Google or Canvas")
                row(captured, "Capture your first task")
                row(scheduled, "Put something on the calendar")
                row(month, "Peek at month view")
                row(widgetAdded, "Add the Atlas widget", soft: true)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MobileTheme.bg))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(MobileTheme.hairline, lineWidth: 1))
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .task { await checkWidget() }
        }
    }

    private func row(_ done: Bool, _ title: String, soft: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? MobileTheme.ink : MobileTheme.faint)
            Text(title + (soft ? "  ·  optional" : ""))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(done ? MobileTheme.muted : MobileTheme.ink)
                .strikethrough(done, color: MobileTheme.muted)
            Spacer()
        }
    }

    /// Soft auto-check: WidgetCenter reports installed widget kinds. No signal if
    /// none added — stays a plain instruction row (never blocks completion).
    private func checkWidget() async {
        let atlasKinds: Set<String> = ["AtlasToday", "AtlasLockRect", "AtlasLockCircular"]
        // iOS 17 has only the completion-handler form; wrap it in a continuation.
        let infos: [WidgetInfo] = await withCheckedContinuation { cont in
            WidgetCenter.shared.getCurrentConfigurations { result in
                cont.resume(returning: (try? result.get()) ?? [])
            }
        }
        widgetAdded = infos.contains { atlasKinds.contains($0.kind) }
    }
}
