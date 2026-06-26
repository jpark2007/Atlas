// CARRYOVER — from old Atlas prototype. Depends on old `DS` design system + `CaptureViewModel`.
// The SwiftUI pill UI (idle / recording / processing / results / error / typing states).
import SwiftUI
import SwiftData

struct CapturePanelView: View {
    @Bindable var vm: CaptureViewModel
    var onDismiss: () -> Void
    @Environment(\.modelContext) private var context
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            body(for: state)
        }
        .padding(20)
        .frame(width: 520)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous)
                .fill(DS.Colors.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous)
                        .stroke(DS.Colors.borderSubtle, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 32, y: 12)
        )
        .onAppear {
            vm.setContext(context)
            pulse = true
        }
        .onExitCommand { onDismiss() }
    }

    // MARK: - States

    private enum PanelState {
        case idle, recording, processing, results, error, typing
    }

    private var state: PanelState {
        if vm.error != nil { return .error }
        if !vm.parsedTasks.isEmpty { return .results }
        if vm.isProcessing { return .processing }
        if vm.speechService.isRecording { return .recording }
        if !vm.textInput.isEmpty { return .typing }
        return .idle
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Text("Capture thought")
                .font(DS.Typography.panelTitle)
                .foregroundColor(DS.Colors.textPrimary)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.Colors.textMuted)
                    .padding(6)
                    .background(DS.Colors.bgElevated)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Body per state

    @ViewBuilder
    private func body(for state: PanelState) -> some View {
        switch state {
        case .idle:       idleBody
        case .recording:  recordingBody
        case .processing: processingBody
        case .results:    resultsBody
        case .error:      errorBody
        case .typing:     typingBody
        }
    }

    private var idleBody: some View {
        HStack(spacing: 14) {
            Button {
                vm.startVoiceCapture()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Colors.bgPrimary)
                    .frame(width: 36, height: 36)
                    .background(DS.Colors.accentAction)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text("Press record or type below")
                    .font(DS.Typography.body)
                    .foregroundColor(DS.Colors.textSecondary)
                Text("Click stop when you're done")
                    .font(DS.Typography.tiny)
                    .foregroundColor(DS.Colors.textGhost)
            }
            Spacer()
        }
    }

    private var recordingBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(DS.Colors.recording)
                    .frame(width: 9, height: 9)
                    .opacity(pulse ? 1 : 0.35)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                Text("Listening…")
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.textSecondary)
                Spacer()
                Button("Stop") { vm.stopVoiceCapture() }
                    .buttonStyle(.plain)
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.textSecondary)
            }

            Text(vm.speechService.transcript.isEmpty ? "Start speaking…" : vm.speechService.transcript)
                .font(DS.Typography.body)
                .foregroundColor(vm.speechService.transcript.isEmpty ? DS.Colors.textGhost : DS.Colors.textPrimary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Text("Click stop when you're done")
                .font(DS.Typography.tiny)
                .foregroundColor(DS.Colors.textGhost)
        }
    }

    private var processingBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(currentTranscript)
                .font(DS.Typography.body)
                .foregroundColor(DS.Colors.textPrimary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Text("Routing tasks…")
                    .font(DS.Typography.caption)
                    .foregroundColor(DS.Colors.warmAccent)
            }
        }
    }

    private var resultsBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(vm.parsedTasks.prefix(4).enumerated()), id: \.offset) { _, task in
                HStack(spacing: 10) {
                    Circle()
                        .fill(DS.Colors.warmAccent)
                        .frame(width: 6, height: 6)
                    Text(task.title)
                        .font(DS.Typography.body)
                        .foregroundColor(DS.Colors.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text("→ inbox")
                        .font(DS.Typography.tiny)
                        .foregroundColor(DS.Colors.textMuted)
                }
            }
            if vm.parsedTasks.count > 4 {
                Text("+\(vm.parsedTasks.count - 4) more")
                    .font(DS.Typography.tiny)
                    .foregroundColor(DS.Colors.textMuted)
            }
        }
        .onAppear {
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                onDismiss()
            }
        }
    }

    private var errorBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(vm.error ?? "Something went wrong")
                .font(DS.Typography.caption)
                .foregroundColor(DS.Colors.warmAccent)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Retry") {
                    vm.error = nil
                    vm.startVoiceCapture()
                }
                .buttonStyle(.plain)
                .font(DS.Typography.caption)
                .fontWeight(.semibold)
                .foregroundColor(DS.Colors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(DS.Colors.bgElevated)
                .clipShape(Capsule())
                Spacer()
            }
        }
    }

    private var typingBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $vm.textInput)
                .font(DS.Typography.body)
                .foregroundColor(DS.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60, maxHeight: 140)
                .padding(8)
                .background(DS.Colors.bgPrimary)
                .cornerRadius(DS.Radius.md)
            HStack {
                Spacer()
                Button {
                    Task { await vm.processDump(context: context) }
                } label: {
                    Text("Process")
                        .font(DS.Typography.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(DS.Colors.bgPrimary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(DS.Colors.accentAction)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var currentTranscript: String {
        vm.textInput.isEmpty ? vm.speechService.transcript : vm.textInput
    }
}
