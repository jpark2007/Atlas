import Foundation

/// Supabase project connection. The **anon key is safe to ship** — Row Level
/// Security on the server is what protects data, so this lives in source (not a
/// secret). Server-side secrets (OpenRouter, Google client secret, Canvas
/// tokens) NEVER go here — they live as Supabase Edge Function secrets.
enum SupabaseConfig {
    static let url = URL(string: "https://jxrmozhgsebwtbdleyxp.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp4cm1vemhnc2Vid3RiZGxleXhwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI1MTAxOTIsImV4cCI6MjA5ODA4NjE5Mn0.xV-CS3P0V8o2MqQwcJsQYhHYpA4-G_ocvKveGMgu9mw"

    /// Custom URL scheme used for OAuth redirects (Google). Must be registered
    /// in Supabase Auth → URL Configuration → Redirect URLs as `atlas://auth-callback`.
    static let redirectScheme = "atlas"
    static let redirectURL = "atlas://auth-callback"

    static var authBase: URL { url.appendingPathComponent("auth/v1") }
}
