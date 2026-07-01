import SwiftUI
import AtlasCore

/// Phase-0 placeholder ONLY. Proves the iOS target links `AtlasCore` and can sign
/// in against the same Supabase backend as the Mac app. Deliberately unstyled —
/// the real Capture/Schedule/Tasks UI is Phase 1.
struct ContentView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var status = "Not signed in"
    @State private var busy = false

    private let auth = SupabaseAuth()

    var body: some View {
        VStack(spacing: 16) {
            Text("Atlas").font(.largeTitle.bold())
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            SecureField("Password", text: $password)
            Button(busy ? "Signing in…" : "Sign in") { signIn() }
                .disabled(busy || email.isEmpty || password.isEmpty)
            Text(status)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .textFieldStyle(.roundedBorder)
        .padding()
    }

    private func signIn() {
        busy = true
        Task { @MainActor in
            do {
                _ = try await auth.signIn(email: email, password: password)
                status = "Signed in ✓"
            } catch {
                status = "Error: \(error.localizedDescription)"
            }
            busy = false
        }
    }
}
