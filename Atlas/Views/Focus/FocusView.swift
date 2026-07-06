import SwiftUI
import AtlasCore

/// Focus mode — a Pomodoro timer styled in the Atlas dark + orange design language.
///
/// Ported and restyled from the old prototype's pill-timer (`docs/carryover/focus-pill-timer`).
/// Stage 1 ships the in-app timer only. The menu-bar service (`MenuBarService` /
/// `NSStatusItem`) and the `FocusReflectionSheet` from the carryover are intentionally
/// NOT ported here (see report). The view drives a dedicated `FocusViewModel` and does
/// not touch `AppState`.
struct FocusView: View {
    @StateObject private var vm = FocusViewModel()

    var body: some View {
        ZStack {
            AtlasTheme.Colors.bgBase.ignoresSafeArea()

            VStack(spacing: 36) {
                Spacer(minLength: 0)

                phaseLabel
                timerDisplay
                controls
                cycleMeta

                Spacer(minLength: 0)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.25), value: vm.phaseLabel)
            .animation(.easeInOut(duration: 0.2), value: vm.isRunning)
        }
    }

    // MARK: - Phase label

    private var phaseLabel: some View {
        // Caps treatment inlined: atlasCapsLabel() bakes its own foreground nearest the
        // Text, which would kill the break-phase accent (same trap as WeekColumnHeader).
        Text("— \(vm.phaseLabel.uppercased()) —")
            .atlasMono(size: 11, weight: .bold)
            .tracking(2)
            .textCase(.uppercase)
            .foregroundStyle(isBreak ? AtlasTheme.Colors.accentText : AtlasTheme.Colors.textMuted)
    }

    // MARK: - Big time display

    private var timerDisplay: some View {
        ZStack {
            // Subtle progress ring behind the digits.
            Circle()
                .stroke(AtlasTheme.Colors.border, lineWidth: 4)
            Circle()
                .trim(from: 0, to: vm.progress)
                .stroke(
                    AngularGradient(
                        colors: [AtlasTheme.Colors.accentDeep, AtlasTheme.Colors.accent],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: vm.progress)

            Text(vm.timeFormatted)
                .atlasMono(size: 96, weight: .ultraLight)
                .monospacedDigit()
                .foregroundStyle(vm.isRunning
                    ? AtlasTheme.Colors.textPrimary
                    : AtlasTheme.Colors.textSecondary)
                .contentTransition(.numericText())
        }
        .frame(width: 320, height: 320)
    }

    // MARK: - Controls (pill start/pause + reset)

    private var controls: some View {
        HStack(spacing: 16) {
            // PILL — primary start/pause: transparent with a 1.5 pt ink outline.
            Button(action: vm.toggle) {
                HStack(spacing: 8) {
                    Image(systemName: vm.primaryButtonIcon)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(vm.primaryButtonTitle)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .overlay(Capsule().strokeBorder(AtlasTheme.Colors.textPrimary, lineWidth: AtlasTheme.rule))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(vm.isRunning ? "Pause the timer" : "Start the timer")

            // Reset — secondary, outlined circular control.
            Button(action: vm.reset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    .frame(width: 44, height: 44)
                    .overlay(Circle().strokeBorder(AtlasTheme.Colors.borderStrong, lineWidth: AtlasTheme.rule))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Reset the cycle")

            // Skip — advance to the next phase.
            Button(action: vm.skipPhase) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    .frame(width: 44, height: 44)
                    .overlay(Circle().strokeBorder(AtlasTheme.Colors.borderStrong, lineWidth: AtlasTheme.rule))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(isBreak ? "Skip to focus" : "Skip to break")
        }
    }

    // MARK: - Cycle meta

    private var cycleMeta: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            Text(intervalsText)
                .atlasMono(size: 11)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .overlay(Capsule().strokeBorder(AtlasTheme.Colors.border, lineWidth: 1))
        .contentShape(Capsule())
    }

    private var intervalsText: String {
        let n = vm.completedWorkIntervals
        return n == 1 ? "1 focus interval done" : "\(n) focus intervals done"
    }

    private var isBreak: Bool { vm.phase == .shortBreak }
}

#if DEBUG
#Preview {
    FocusView()
        .frame(width: 720, height: 600)
}
#endif
