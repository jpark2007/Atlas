import SwiftUI
import AtlasCore

/// New-account first-run decision + local seen-flag for the attribution step.
/// Same rule as `NamePromptOnboarding`: new account = session user created within
/// 7 days AND the step never shown on this device. Skipping marks it seen and
/// writes `referral_source = "skipped"`, so it never asks again anywhere.
enum AttributionOnboarding {
    private static let seenKey = "onboarding.attributionSeen"

    static func shouldShow(session: SupabaseSession?) -> Bool {
        guard !UserDefaults.standard.bool(forKey: seenKey),
              let iso = session?.user.createdAt,
              let created = parseISO(iso) else { return false }
        return Date().timeIntervalSince(created) < 7 * 24 * 60 * 60
    }

    static func markSeen() { UserDefaults.standard.set(true, forKey: seenKey) }

    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

/// Asked once, right after sign-up: where the account came from, and which
/// school. Both optional. Matches `NamePromptPopup`'s look.
struct AttributionPopup: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var source: ReferralSource? = nil
    @State private var otherText = ""
    @State private var schoolQuery = ""
    @State private var pickedSchool: String? = nil
    @FocusState private var otherFocused: Bool

    /// Type-ahead hits, hidden once a school is picked or the field is empty.
    private var schoolHits: [School] {
        guard pickedSchool == nil, schoolQuery.count >= 2 else { return [] }
        return USSchools.search(schoolQuery, limit: 6)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(AtlasTheme.Colors.accent)
                Text("How did you hear about Atlas?")
                    .atlasFont(size: 20, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            }
            Text("Two quick questions — both optional. They only help us know where to show up.")
                .atlasFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            chips

            if source == .other {
                TextField("Where did you find us?", text: $otherText)
                    .textFieldStyle(.plain)
                    .atlasFont(size: 14, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .tint(AtlasTheme.Colors.accent)
                    .focused($otherFocused)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AtlasTheme.Colors.border, lineWidth: 1))
            }

            Divider().overlay(AtlasTheme.Colors.border)

            schoolField

            HStack {
                Button("Skip") { skip() }
                    .buttonStyle(.plain)
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                Spacer()
                Button("Done") { save() }
                    .buttonStyle(.plain)
                    .atlasFont(size: 13, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.accentText)
                    .disabled(source == nil && trimmedSchool == nil)
            }
        }
        .padding(28)
        .frame(width: 460)
        .background(AtlasTheme.Colors.bgBase)
    }

    // MARK: Pieces

    private var chips: some View {
        FlowChips(sources: ReferralSource.choices, selected: source) { choice in
            source = (source == choice) ? nil : choice
            otherFocused = (source == .other)
        }
    }

    @ViewBuilder
    private var schoolField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What school are you at?")
                .atlasFont(size: 13, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)

            TextField("Start typing…", text: $schoolQuery)
                .textFieldStyle(.plain)
                .atlasFont(size: 14, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .tint(AtlasTheme.Colors.accent)
                .onChange(of: schoolQuery) { _, _ in pickedSchool = nil }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AtlasTheme.Colors.border, lineWidth: 1))

            if !schoolHits.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(schoolHits) { hit in
                        row(hit.name) { pick(hit.name) }
                    }
                    // The list is US universities only — anything else goes in
                    // verbatim through this row.
                    row("Use “\(schoolQuery)”") { pick(schoolQuery) }
                }
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AtlasTheme.Colors.border, lineWidth: 1))
            }
        }
    }

    private func row(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .atlasFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private var trimmedSchool: String? {
        let s = (pickedSchool ?? schoolQuery).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private func pick(_ name: String) {
        pickedSchool = name
        schoolQuery = name
    }

    private func save() {
        let detail = otherText.trimmingCharacters(in: .whitespacesAndNewlines)
        state.saveSignupAttribution(
            source: source ?? .skipped,
            detail: (source == .other && !detail.isEmpty) ? detail : nil,
            school: trimmedSchool)
        finish()
    }

    /// Skip still writes, so the question never comes back on another device.
    private func skip() {
        state.saveSignupAttribution(source: .skipped, detail: nil, school: nil)
        finish()
    }

    private func finish() {
        AttributionOnboarding.markSeen()
        dismiss()
    }
}

/// The chip row — three to a line at the popup's fixed width.
private struct FlowChips: View {
    let sources: [ReferralSource]
    let selected: ReferralSource?
    let tap: (ReferralSource) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                  alignment: .leading, spacing: 8) {
            ForEach(sources, id: \.self) { s in
                let on = (s == selected)
                Button { tap(s) } label: {
                    Text(s.label)
                        .atlasFont(size: 12, weight: .semibold, design: .rounded)
                        .foregroundStyle(on ? AtlasTheme.Colors.accentText : AtlasTheme.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(on ? AtlasTheme.wash(AtlasTheme.Colors.accent) : Color.clear, in: Capsule())
                        .overlay(Capsule().strokeBorder(
                            on ? AtlasTheme.Colors.accent : AtlasTheme.Colors.border, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
