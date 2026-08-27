import SwiftUI

/// Collects named anchor frames (toggle, calendar glyph) from the header so the
/// spotlight can cut a hole over the right control.
struct SpotlightAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publish this view's frame in global space under `id`.
    func spotlightAnchor(_ id: String) -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: SpotlightAnchorKey.self, value: [id: geo.frame(in: .global)])
        })
    }
}

/// The dim + cutout overlay. `step` 0 highlights the toggle, 1 the calendar glyph.
/// `onSkip` finishes immediately. Anchors come from the ScheduleView header.
struct CalendarSpotlightOverlay: View {
    @Environment(\.horizontalSizeClass) private var hSize
    let step: Int
    let anchors: [String: CGRect]
    let onSkip: () -> Void

    /// At regular width this overlay lives inside `edContentColumn`, so it is narrower than
    /// the screen: the dim has to spill past both edges to cover the gutters, and the
    /// anchors (captured in global space) have to be pulled back into the column's space.
    /// Both are no-ops on the phone, where the column is the screen.
    private var spill: CGFloat { hSize == .regular ? 2000 : 0 }

    private var holeID: String { step == 0 ? "toggle" : "calendar" }
    private var caption: String {
        step == 0 ? "Switch between list and grid" : "Tap to jump to any day in month view"
    }

    var body: some View {
        GeometryReader { geo in
            // Guard: the preference may not have been delivered on the first frame.
            // Drawing a cutout at .zero would flash a hole at the origin — skip until real.
            if let raw = anchors[holeID], raw != .zero {
                let dx = hSize == .regular ? -geo.frame(in: .global).minX : 0
                let hole = raw.insetBy(dx: -8, dy: -8).offsetBy(dx: dx, dy: 0)
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Color.black.opacity(0.55))
                        .mask(
                            Rectangle()
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .frame(width: hole.width, height: hole.height)
                                    .position(x: hole.midX + spill, y: hole.midY)
                                    .blendMode(.destinationOut))
                                .compositingGroup()
                        )
                        // Negative padding widens the dim past the column into the gutters;
                        // `spill` above keeps the cutout aligned inside the wider rect.
                        .padding(.horizontal, -spill)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)   // taps pass through to the real control

                    // The bubble lives in a screen-wide band inset by `margin`, hugging the
                    // side its anchor is on — centring it on the anchor pushed the caption
                    // off-screen whenever the control sat near an edge.
                    let margin: CGFloat = 16
                    let band = max(0, geo.size.width - margin * 2)
                    let onTrailingHalf = hole.midX > geo.size.width / 2
                    Text(caption)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(onTrailingHalf ? .trailing : .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: max(0, band - 28))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.7)))
                        .frame(width: band, alignment: onTrailingHalf ? .trailing : .leading)
                        // `hole` is in global coords but the dim ignores the safe area, so
                        // convert the caption's y into this GeometryReader's inset-local space.
                        .position(x: geo.size.width / 2, y: hole.maxY + 28 - geo.safeAreaInsets.top)

                    Button("Skip", action: onSkip)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.2)))
                        .position(x: geo.size.width / 2, y: geo.size.height - 80)
                }
            }
        }
    }
}
