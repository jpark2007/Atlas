import SwiftUI
import AtlasCore

struct SignInView: View {
    @EnvironmentObject private var auth: AuthService

    @State private var email = ""
    @State private var password = ""
    @State private var mode: Mode = .signIn

    enum Mode { case signIn, signUp }

    var body: some View {
        ZStack {
            AtlasTheme.Colors.bgBase.ignoresSafeArea()

            VStack(spacing: 22) {
                logo

                VStack(spacing: 12) {
                    field(icon: "envelope", placeholder: "you@school.edu", text: $email, secure: false)
                    field(icon: "lock", placeholder: "Password", text: $password, secure: true)

                    if let error = auth.errorMessage {
                        message(error, color: AtlasTheme.Colors.danger)
                    }
                    if let info = auth.infoMessage {
                        message(info, color: AtlasTheme.Colors.accentText)
                    }

                    primaryButton

                    HStack(spacing: 4) {
                        Text(mode == .signIn ? "New to Atlas?" : "Already have an account?")
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                        Button(mode == .signIn ? "Create account" : "Sign in") {
                            withAnimation { mode = mode == .signIn ? .signUp : .signIn }
                            auth.errorMessage = nil; auth.infoMessage = nil
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AtlasTheme.Colors.accentText)
                    }
                    .atlasFont(size: 13, design: .rounded)
                    .padding(.top, 2)
                }

                dividerOr

                VStack(spacing: 10) {
                    appleButton
                }

                Button("Continue without an account") { auth.continueOffline() }
                    .buttonStyle(.plain)
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .padding(.top, 4)
            }
            .frame(width: 360)
            .padding(36)
            .overlay(alignment: .top) { if auth.isWorking { ProgressView().controlSize(.small).padding(10) } }
        }
        .frame(minWidth: 720, minHeight: 560)
    }

    // MARK: - Pieces

    private var logo: some View {
        VStack(spacing: 10) {
            BrandLogo(size: 76)
            Text("Atlas")
                .atlasFont(size: 33, weight: .heavy, design: .rounded)
                .tracking(-0.9)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Text(mode == .signIn ? "Your whole life, one place." : "Create your account.")
                .atlasFont(size: 14, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
        }
    }

    /// Editorial field: no fill, no box — an icon + input over a hairline rule.
    private func field(icon: String, placeholder: String, text: Binding<String>, secure: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).atlasFont(size: 14, weight: .medium)
                .foregroundStyle(AtlasTheme.Colors.textMuted).frame(width: 18)
            Group {
                if secure { SecureField(placeholder, text: text) }
                else { TextField(placeholder, text: text) }
            }
            .textFieldStyle(.plain)
            .atlasFont(size: 17, design: .rounded)
            .foregroundStyle(AtlasTheme.Colors.textPrimary)
            .tint(AtlasTheme.Colors.accent)   // caret = brand accent, not a fill
        }
        .padding(.vertical, 12)
        .atlasHairlineBelow()
    }

    private var primaryButton: some View {
        Button {
            Task {
                if mode == .signIn { await auth.signIn(email: email, password: password) }
                else { await auth.signUp(email: email, password: password) }
            }
        } label: {
            Text(mode == .signIn ? "Sign in" : "Create account")
                .atlasFont(size: 17, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .atlasOutlineControl()
                .contentShape(Rectangle())   // whole area clickable, not just the text
        }
        .buttonStyle(.plain)
        .disabled(auth.isWorking)
        .opacity(auth.isWorking ? 0.5 : 1)
    }

    /// Native SIWA when the running binary carries the entitlement (Debug/dev);
    /// otherwise the web-based Apple OAuth flow (Developer ID direct-download builds
    /// can't ship the entitlement). Same button, same resulting session either way.
    private var appleButton: some View {
        providerButton(title: "Sign in with Apple", system: "apple.logo") {
            Task {
                if AuthService.appleSignInAvailable { await auth.signInWithApple() }
                else { await auth.signInWithAppleWeb() }
            }
        }
    }

    /// Outlined ink control — the editorial system never fills a button.
    private func providerButton(title: String, system: String,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: system).atlasFont(size: 17)
                Text(title).atlasFont(size: 14, weight: .medium, design: .rounded)
            }
            .foregroundStyle(AtlasTheme.Colors.textPrimary)
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .overlay(RoundedRectangle(cornerRadius: AtlasTheme.Radius.control, style: .continuous)
                .strokeBorder(AtlasTheme.Colors.textPrimary, lineWidth: AtlasTheme.rule))
            .contentShape(Rectangle())   // whole area clickable, not just the text
        }
        .buttonStyle(.plain)
        .disabled(auth.isWorking)
    }

    private var dividerOr: some View {
        HStack(spacing: 12) {
            Rectangle().fill(AtlasTheme.Colors.hairline).frame(height: 1)
            Text("or").atlasFont(size: 12, weight: .medium, design: .rounded).foregroundStyle(AtlasTheme.Colors.textMuted)
            Rectangle().fill(AtlasTheme.Colors.hairline).frame(height: 1)
        }
    }

    private func message(_ text: String, color: Color) -> some View {
        Text(text).atlasFont(size: 12, design: .rounded).foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
