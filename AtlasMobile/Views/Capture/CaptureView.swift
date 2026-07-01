import SwiftUI
import AtlasCore

/// The Capture hero. A small state machine drives the screen; Task 2 builds the
/// `.empty` state (the dump box + manual-add path). Tasks 3/4 flesh out
/// `.thinking`/`.result` (AI) and `.listening` (voice).
struct CaptureView: View {
    @EnvironmentObject private var store: MobileStore

    enum Phase: Equatable { case empty, listening, thinking, result }

    @State private var phase: Phase = .empty
    @State private var text = ""
    @State private var showManualAdd = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        ZStack {
            MobileTheme.bg.ignoresSafeArea()
            switch phase {
            case .empty:                       emptyState
            case .listening, .thinking, .result:
                // Built in Tasks 3 & 4; unreachable until those wire transitions.
                emptyState
            }
        }
        .sheet(isPresented: $showManualAdd) {
            ManualAddSheet()
                .environmentObject(store)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Empty state (spec §4.2)

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Capture").edScreenTitle()

            dumpBox

            VStack(spacing: 22) {
                orDivider
                Button { showManualAdd = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("Add a task manually")
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.88)
                    .textCase(.uppercase)
                    .foregroundStyle(MobileTheme.ink)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editorFocused = false }
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
            }
        }
    }

    /// Big outlined dump box (radius 24) with a placeholder + a refined mic glyph.
    private var dumpBox: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .focused($editorFocused)
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
                .tint(MobileTheme.accent)          // caret = brand accent, not a fill
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            if text.isEmpty {
                Text("What’s on your mind?")
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundStyle(MobileTheme.faint)
                    .padding(.horizontal, 19)
                    .padding(.vertical, 20)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 200)
        .overlay(alignment: .bottomTrailing) { micGlyph.padding(14) }
        .overlay(
            RoundedRectangle(cornerRadius: MobileTheme.radiusCard, style: .continuous)
                .strokeBorder(MobileTheme.ink, lineWidth: MobileTheme.rule)
        )
        .contentShape(RoundedRectangle(cornerRadius: MobileTheme.radiusCard, style: .continuous))
    }

    /// Refined mic glyph — outlined, never a fill. Faint (disabled-looking) until
    /// Task 4 wires on-device speech.
    private var micGlyph: some View {
        Image(systemName: "mic")
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(MobileTheme.faint)
            .frame(width: 44, height: 44)
            .overlay(Circle().strokeBorder(MobileTheme.hairline, lineWidth: MobileTheme.rule))
    }

    private var orDivider: some View {
        HStack(spacing: 14) {
            Rectangle().fill(MobileTheme.hairline).frame(height: 1)
            Text("or").edCapsLabel().fixedSize()
            Rectangle().fill(MobileTheme.hairline).frame(height: 1)
        }
    }
}
