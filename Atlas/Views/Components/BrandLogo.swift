import SwiftUI

/// The Atlas brand mark — the titan shouldering the celestial sphere (the app's
/// logo, vector-traced into `Assets.xcassets/AtlasMark`, which mirrors the macOS
/// AppIcon). Reusable in-app wherever the brand mark is shown (sidebar header,
/// sign-in). The artwork is taller than it is wide, so it fits within a square
/// box of `size` and centers horizontally.
struct BrandLogo: View {
    var size: CGFloat = 26

    var body: some View {
        Image("AtlasMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("Atlas")
    }
}
