import SwiftUI
import AtlasCore

/// Editorial sign-in: a big title on the bg, thin-rule fields, and an outlined
/// button (never accent-filled). Shown while `store.session == nil`.
struct SignInView: View {
    @EnvironmentObject private var store: MobileStore

    @State private var email = ""
    @State private var password = ""
    @State private var mode: Mode = .signIn
    @State private var busy = false
    @State private var error: String?
    @State private var resetNote: String?

    /// Stateless GoTrue client for the fire-and-forget password-reset request.
    private let auth = SupabaseAuth()

    private enum Mode { case signIn, signUp }

    private var canSubmit: Bool {
        !busy && !email.isEmpty && !password.isEmpty
    }

    private var submitLabel: String {
        switch (mode, busy) {
        case (.signIn, false): return "Sign in"
        case (.signIn, true):  return "Signing in"
        case (.signUp, false): return "Create account"
        case (.signUp, true):  return "Creating account"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            if let notice = store.authNotice {
                Text(notice)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Atlas").edScreenTitle()
                Text("Sign in to continue").edCapsLabel()
            }

            VStack(spacing: 0) {
                field("Email", text: $email, secure: false)
                field("Password", text: $password, secure: true)
            }

            VStack(alignment: .leading, spacing: 16) {
                Button(action: submit) {
                    Text(submitLabel)
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                        .frame(maxWidth: .infinity)
                        .edOutlineControl()
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.4)

                // Text-button mode switcher — no segmented-control chrome, matches
                // the "Forgot password?" caps-label treatment already on this screen.
                Button(action: toggleMode) {
                    Text(mode == .signIn ? "New to Atlas? Create account" : "Already have an account? Sign in")
                        .edCapsLabel()
                }
                .buttonStyle(.plain)
                .disabled(busy)

                // Custom-styled per the outlined-control design language (a stock
                // black SignInWithAppleButton would break the "never a fill" rule).
                Button(action: signInWithApple) {
                    HStack(spacing: 8) {
                        Image(systemName: "applelogo")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Sign in with Apple")
                            .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(MobileTheme.ink)
                    .frame(maxWidth: .infinity)
                    .edOutlineControl()
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .opacity(busy ? 0.4 : 1)

                Button(action: resetPassword) {
                    Text("Forgot password?").edCapsLabel()
                }
                .buttonStyle(.plain)
                .disabled(busy || email.isEmpty)
                .opacity(email.isEmpty ? 0.4 : 1)
            }

            if let resetNote {
                Text(resetNote)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
            }

            if let error {
                Text(error)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
            }

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 84)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MobileTheme.bg.ignoresSafeArea())
    }

    @ViewBuilder
    private func field(_ label: String, text: Binding<String>, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).edCapsLabel()
            Group {
                if secure {
                    SecureField("", text: text)
                        .textContentType(.password)
                } else {
                    TextField("", text: text)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .font(.system(size: 17, weight: .regular, design: .rounded))
            .foregroundStyle(MobileTheme.ink)
            .tint(MobileTheme.accent)   // caret = brand accent, not a fill
        }
        .padding(.vertical, 14)
        .edHairlineBelow()
    }

    private func submit() {
        busy = true
        error = nil
        Task {
            do {
                switch mode {
                case .signIn:
                    try await store.signIn(email: email, password: password)
                case .signUp:
                    try await store.signUp(email: email, password: password)
                }
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription
                    ?? (mode == .signIn
                        ? "Couldn't sign in. Check your email and password."
                        : "Couldn't create your account.")
            }
            busy = false
        }
    }

    /// Flips sign-in ↔ create-account and clears any stale error/notice left
    /// over from the other mode (mirrors the Mac's mode-switch behavior).
    private func toggleMode() {
        mode = mode == .signIn ? .signUp : .signIn
        error = nil
        store.authNotice = nil
    }

    private func signInWithApple() {
        busy = true
        error = nil
        Task {
            do {
                try await store.signInWithApple()
            } catch is CancellationError {
                // User dismissed the Apple sheet — not an error.
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription
                    ?? "Couldn't sign in with Apple."
            }
            busy = false
        }
    }

    /// Fire-and-forget: ask GoTrue to email a reset link to the typed address.
    private func resetPassword() {
        resetNote = nil
        Task {
            do {
                try await auth.resetPassword(email: email)
                resetNote = "Check your email for a reset link."
            } catch {
                resetNote = "Couldn't send the reset email."
            }
        }
    }
}
