import SwiftUI

/// Atlas's own loading mark — a clay stroke sweeping a thin ink ring.
///
/// The stock `ProgressView` spinner is a system gray pinwheel: it reads as OS chrome
/// dropped into the middle of an Atlas sheet. This is the one indicator Atlas-owned
/// sheets wait on instead, built from the same tokens as everything else on the page —
/// an ink-12% hairline ring with a clay (`Colors.accent`) arc riding it.
///
/// Reduce Motion drops the rotation for a gentle opacity pulse on the closed clay ring
/// rather than freezing the mark, so the wait still reads as "working".
public struct AtlasLoader: View {
    /// Diameter of the mark. 22 pt sits inline next to body copy; 28 suits a sheet that
    /// is doing nothing but waiting.
    private let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweeping = false
    @State private var dimmed = false

    public init(size: CGFloat = 22) { self.size = size }

    public var body: some View {
        ZStack {
            Circle()
                .strokeBorder(AtlasTheme.Colors.hairline, lineWidth: AtlasTheme.hairlineWidth)
            mark
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Loading")
    }

    @ViewBuilder
    private var mark: some View {
        if reduceMotion {
            Circle()
                .strokeBorder(AtlasTheme.Colors.accent, lineWidth: stroke)
                .opacity(dimmed ? 0.25 : 0.75)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: dimmed)
                .onAppear { dimmed = true }
        } else {
            Circle()
                .trim(from: 0, to: 0.22)
                .stroke(AtlasTheme.Colors.accent,
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                // `.stroke` centers on the path, so inset by half the width to keep the
                // clay arc concentric with the hairline ring instead of overhanging it.
                .padding(stroke / 2)
                .rotationEffect(.degrees(sweeping ? 360 : 0))
                .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: sweeping)
                .onAppear { sweeping = true }
        }
    }

    /// Heavier than the ring's hairline so the clay reads as a drawn stroke, not a tint.
    private var stroke: CGFloat { max(2, size * 0.09) }
}
