import SwiftUI

/// The Atlas brand mark — an abstract bloom (8 rounded petals in the orange
/// accent with a deeper center) on a soft warm rounded-square, mirroring the
/// macOS AppIcon (`tools/gen_app_icon.swift`). Reusable in-app wherever the
/// brand mark is shown (e.g. the sidebar header).
struct BrandLogo: View {
    var size: CGFloat = 26

    // Palette mirrors the icon generator / AtlasTheme.
    private let bgTop      = Color(hex: "fff1e2")
    private let bgBottom   = Color(hex: "ffdbbb")
    private let petalStart = AtlasTheme.Colors.accent
    private let petalEnd   = AtlasTheme.Colors.accentDeep
    private let centerCol  = Color(hex: "ffb15a")

    var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let center = CGPoint(x: s / 2, y: s / 2)

            // Soft rounded-square background.
            let bg = Path(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                          cornerRadius: s * 0.2237)
            context.fill(bg, with: .linearGradient(
                Gradient(colors: [bgTop, bgBottom]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: s)))

            // 8 petals radiating from the center.
            let petalW = s * 0.165
            let petalH = s * 0.300
            let orbit  = s * 0.085
            for i in 0 ..< 8 {
                let angle = Double(i) / 8.0 * 2 * .pi
                var layer = context
                layer.translateBy(x: center.x, y: center.y)
                layer.rotate(by: .radians(angle))
                let petal = Path(ellipseIn: CGRect(x: -petalW / 2, y: orbit,
                                                   width: petalW, height: petalH))
                layer.fill(petal, with: .linearGradient(
                    Gradient(colors: [petalStart, petalEnd]),
                    startPoint: CGPoint(x: 0, y: orbit),
                    endPoint: CGPoint(x: 0, y: orbit + petalH)))
            }

            // Deeper center disc.
            let cr = s * 0.130
            let disc = Path(ellipseIn: CGRect(x: center.x - cr, y: center.y - cr,
                                              width: cr * 2, height: cr * 2))
            context.fill(disc, with: .color(centerCol))
        }
        .frame(width: size, height: size)
    }
}
