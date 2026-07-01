import SwiftUI

/// Editorial sign-in: a big title on the bg, thin-rule fields, and an outlined
/// button (never accent-filled). Shown while `store.session == nil`.
struct SignInView: View {
    @EnvironmentObject private var store: MobileStore

    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    private var canSubmit: Bool {
        !busy && !email.isEmpty && !password.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Atlas").edScreenTitle()
                Text("Sign in to continue").edCapsLabel()
            }

            VStack(spacing: 0) {
                field("Email", text: $email, secure: false)
                field("Password", text: $password, secure: true)
            }

            Button(action: signIn) {
                Text(busy ? "Signing in" : "Sign in")
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                    .frame(maxWidth: .infinity)
                    .edOutlineControl()
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.4)

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

    private func signIn() {
        busy = true
        error = nil
        Task {
            do {
                try await store.signIn(email: email, password: password)
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription
                    ?? "Couldn't sign in. Check your email and password."
            }
            busy = false
        }
    }
}
