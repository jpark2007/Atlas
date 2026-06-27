import SwiftUI

/// Account + integrations sheet. Reached from the sidebar profile row.
struct SettingsView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var canvas: CanvasService
    @Environment(\.dismiss) private var dismiss

    @State private var canvasToken = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Settings").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(AtlasTheme.Colors.textMuted)
            }

            account
            Divider().overlay(AtlasTheme.Colors.border)
            canvasSection
            Divider().overlay(AtlasTheme.Colors.border)
            integrations

            Spacer()
        }
        .padding(28)
        .frame(width: 460, height: 560)
        .background(AtlasTheme.Colors.bgBase)
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("ACCOUNT")
            HStack(spacing: 12) {
                Circle().fill(AtlasTheme.Colors.accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: "person.fill").foregroundStyle(AtlasTheme.Colors.accent))
                VStack(alignment: .leading, spacing: 2) {
                    Text(identityTitle).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text(identitySubtitle).font(.system(size: 12))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer()
                if case .offline = auth.state {
                    Button("Sign in") { auth.signOut() } // returns to gate
                        .buttonStyle(.plain).foregroundStyle(AtlasTheme.Colors.accent)
                } else {
                    Button("Sign out") { auth.signOut(); dismiss() }
                        .buttonStyle(.plain).foregroundStyle(.red)
                }
            }
        }
    }

    private var canvasSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("CANVAS")
            switch canvas.status {
            case .connected(let name):
                row(icon: "checkmark.seal.fill", tint: AtlasTheme.Colors.green,
                    title: "Connected as \(name)", subtitle: canvas.host)
                Button("Disconnect") { canvas.disconnect() }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.red)
            default:
                input("school.instructure.com", text: Binding(get: { canvas.host }, set: { canvas.host = $0 }))
                input("Canvas access token", text: $canvasToken, secure: true)
                if case .failed(let msg) = canvas.status {
                    Text(msg).font(.system(size: 11)).foregroundStyle(.red)
                }
                Button {
                    Task { await canvas.connect(host: canvas.host, token: canvasToken) }
                } label: {
                    Text(canvas.status == .connecting ? "Connecting…" : "Connect Canvas")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(AtlasTheme.Colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                Text("Account → Settings → Approved Integrations → New Access Token")
                    .font(.system(size: 10)).foregroundStyle(AtlasTheme.Colors.textMuted)
            }
        }
    }

    private var integrations: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("INTEGRATIONS")
            row(icon: "calendar", tint: AtlasTheme.Colors.school, title: "Google Calendar / Drive / Gmail",
                subtitle: "Sign in with Google to enable")
            row(icon: "applelogo", tint: AtlasTheme.Colors.textSecondary, title: "Sign in with Apple",
                subtitle: "Enable signing in Xcode to use on device")
        }
    }

    // MARK: helpers

    private var identityTitle: String {
        switch auth.state {
        case .signedIn(let u): return u.displayName
        case .offline: return "Offline mode"
        default: return "Not signed in"
        }
    }
    private var identitySubtitle: String {
        switch auth.state {
        case .signedIn(let u): return u.email ?? "Signed in"
        case .offline: return "Using local mock data"
        default: return ""
        }
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .semibold)).tracking(1.2)
            .foregroundStyle(AtlasTheme.Colors.textMuted)
    }

    private func row(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13)).foregroundStyle(AtlasTheme.Colors.textPrimary)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            Spacer()
        }
    }

    private func input(_ placeholder: String, text: Binding<String>, secure: Bool = false) -> some View {
        Group {
            if secure { SecureField(placeholder, text: text) }
            else { TextField(placeholder, text: text) }
        }
        .textFieldStyle(.plain).font(.system(size: 13))
        .foregroundStyle(AtlasTheme.Colors.textPrimary).tint(AtlasTheme.Colors.accent)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(AtlasTheme.Colors.bgElevated.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(AtlasTheme.Colors.border, lineWidth: 1))
    }
}
