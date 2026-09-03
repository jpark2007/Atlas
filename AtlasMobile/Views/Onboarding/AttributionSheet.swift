import SwiftUI
import AtlasCore

/// New-account first-run decision + local seen-flag for the attribution step.
/// Mirrors the Mac's `AttributionOnboarding`: new account = session user created
/// within 7 days AND the step never shown on this device. Skipping writes
/// `referral_source = "skipped"`, so it never asks again on any device.
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
/// school. Both optional; Skip is always available.
struct AttributionSheet: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    @State private var source: ReferralSource? = nil
    @State private var otherText = ""
    @State private var schoolQuery = ""
    @State private var pickedSchool: String? = nil

    /// Type-ahead hits, hidden once a school is picked or the field is short.
    private var schoolHits: [School] {
        guard pickedSchool == nil, schoolQuery.count >= 2 else { return [] }
        return USSchools.search(schoolQuery, limit: 6)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("How did you hear about Atlas?").edScreenTitle()
                        Text("Optional").edCapsLabel()
                    }
                    Spacer()
                    Button { skip() } label: { Text("Skip").edCapsLabel() }
                        .buttonStyle(.plain)
                }

                chips

                if source == .other {
                    TextField("Where did you find us?", text: $otherText)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                        .tint(MobileTheme.accentText)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusControl, style: .continuous)
                            .strokeBorder(MobileTheme.hairline, lineWidth: 1))
                }

                schoolField

                Button(action: save) {
                    Text("Done")
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                        .frame(maxWidth: .infinity)
                        .edOutlineControl()
                }
                .buttonStyle(.plain)
                .disabled(source == nil && trimmedSchool == nil)
                .opacity(source == nil && trimmedSchool == nil ? 0.45 : 1)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(MobileTheme.bg.ignoresSafeArea())
        .interactiveDismissDisabled()
    }

    // MARK: Pieces

    private var chips: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                  alignment: .leading, spacing: 8) {
            ForEach(ReferralSource.choices, id: \.self) { s in
                let on = (s == source)
                Button {
                    MobileTheme.Haptic.selection()
                    source = (source == s) ? nil : s
                } label: {
                    Text(s.label)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(on ? MobileTheme.accentText : MobileTheme.muted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(on ? MobileTheme.accent.opacity(0.13) : .clear,
                                    in: RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusChip, style: .continuous)
                            .strokeBorder(on ? MobileTheme.accent : MobileTheme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var schoolField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What school are you at?").edCapsLabel()

            TextField("Start typing…", text: $schoolQuery)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
                .tint(MobileTheme.accentText)
                .autocorrectionDisabled()
                .onChange(of: schoolQuery) { _, _ in pickedSchool = nil }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusControl, style: .continuous)
                    .strokeBorder(MobileTheme.hairline, lineWidth: 1))

            if !schoolHits.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(schoolHits) { hit in
                        row(hit.name) { pick(hit.name) }
                    }
                    // The bundled list is US universities only — anything else
                    // goes in verbatim through this row.
                    row("Use “\(schoolQuery)”") { pick(schoolQuery) }
                }
                .overlay(RoundedRectangle(cornerRadius: MobileTheme.radiusControl, style: .continuous)
                    .strokeBorder(MobileTheme.hairline, lineWidth: 1))
            }
        }
    }

    private func row(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 10)
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
        store.saveSignupAttribution(
            source: source ?? .skipped,
            detail: (source == .other && !detail.isEmpty) ? detail : nil,
            school: trimmedSchool)
        finish()
    }

    /// Skip still writes, so the question never comes back on another device.
    private func skip() {
        store.saveSignupAttribution(source: .skipped, detail: nil, school: nil)
        finish()
    }

    private func finish() {
        AttributionOnboarding.markSeen()
        dismiss()
    }
}
