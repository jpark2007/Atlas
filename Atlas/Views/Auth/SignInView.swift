import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var auth: AuthService

    @State private var email = ""
    @State private var password = ""
    @State private var mode: Mode = .signIn

    enum Mode { case signIn, signUp }

    var body: some View {
        ZStack {
            AtlasTheme.Colors.bgBase.ignoresSafeArea()
            backdrop

            VStack(spacing: 22) {
                logo

                VStack(spacing: 12) {
                    field(icon: "envelope", placeholder: "you@school.edu", text: $email, secure: false)
                    field(icon: "lock", placeholder: "Password", text: $password, secure: true)

                    if let error = auth.errorMessage {
                        message(error, color: .red)
                    }
                    if let info = auth.infoMessage {
                        message(info, color: AtlasTheme.Colors.accent)
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
                        .foregroundStyle(AtlasTheme.Colors.accent)
                    }
                    .font(.system(size: 12))
                    .padding(.top, 2)
                }

                dividerOr

                VStack(spacing: 10) {
                    appleButton
                    googleButton
                }

                Button("Continue without an account") { auth.continueOffline() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .padding(.top, 4)
            }
            .frame(width: 360)
            .padding(36)
            .background(glassCard)
            .overlay(alignment: .top) { if auth.isWorking { ProgressView().controlSize(.small).padding(10) } }
        }
        .frame(minWidth: 720, minHeight: 560)
        .preferredColorScheme(.dark)
    }

    // MARK: - Pieces

    private var logo: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [AtlasTheme.Colors.accent, AtlasTheme.Colors.accentDeep],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 52, height: 52)
                .overlay(Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 24, weight: .bold)).foregroundStyle(.white))
            Text("Atlas").font(.system(size: 24, weight: .bold))
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Text(mode == .signIn ? "Your whole life, one place." : "Create your account.")
                .font(.system(size: 13)).foregroundStyle(AtlasTheme.Colors.textSecondary)
        }
    }

    private func field(icon: String, placeholder: String, text: Binding<String>, secure: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13))
                .foregroundStyle(AtlasTheme.Colors.textMuted).frame(width: 18)
            Group {
                if secure { SecureField(placeholder, text: text) }
                else { TextField(placeholder, text: text) }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(AtlasTheme.Colors.textPrimary)
            .tint(AtlasTheme.Colors.accent)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(AtlasTheme.Colors.bgElevated.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(AtlasTheme.Colors.border, lineWidth: 1))
    }

    private var primaryButton: some View {
        Button {
            Task {
                if mode == .signIn { await auth.signIn(email: email, password: password) }
                else { await auth.signUp(email: email, password: password) }
            }
        } label: {
            Text(mode == .signIn ? "Sign in" : "Create account")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(LinearGradient(colors: [AtlasTheme.Colors.accent, AtlasTheme.Colors.accentDeep],
                                           startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(auth.isWorking)
    }

    private var appleButton: some View {
        providerButton(title: "Sign in with Apple", system: "apple.logo", fg: .white,
                       bg: Color.black) { Task { await auth.signInWithApple() } }
    }

    private var googleButton: some View {
        providerButton(title: "Continue with Google", system: "g.circle.fill",
                       fg: AtlasTheme.Colors.textPrimary,
                       bg: AtlasTheme.Colors.bgElevated) { Task { await auth.signInWithGoogle() } }
    }

    private func providerButton(title: String, system: String, fg: Color, bg: Color,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: system).font(.system(size: 15))
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AtlasTheme.Colors.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(auth.isWorking)
    }

    private var dividerOr: some View {
        HStack(spacing: 12) {
            Rectangle().fill(AtlasTheme.Colors.border).frame(height: 1)
            Text("or").font(.system(size: 11)).foregroundStyle(AtlasTheme.Colors.textMuted)
            Rectangle().fill(AtlasTheme.Colors.border).frame(height: 1)
        }
    }

    private func message(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var glassCard: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AtlasTheme.Colors.bgCard.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AtlasTheme.Colors.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
    }

    private var backdrop: some View {
        RadialGradient(colors: [AtlasTheme.Colors.accent.opacity(0.10), .clear],
                       center: .top, startRadius: 0, endRadius: 480)
            .ignoresSafeArea()
    }
}
