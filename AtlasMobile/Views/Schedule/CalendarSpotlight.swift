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
    let step: Int
    let anchors: [String: CGRect]
    let onSkip: () -> Void

    private var holeID: String { step == 0 ? "toggle" : "calendar" }
    private var caption: String {
        step == 0 ? "Switch between list and grid" : "Tap to jump to any day in month view"
    }

    var body: some View {
        GeometryReader { geo in
            // Guard: the preference may not have been delivered on the first frame.
            // Drawing a cutout at .zero would flash a hole at the origin — skip until real.
            if let raw = anchors[holeID], raw != .zero {
                let hole = raw.insetBy(dx: -8, dy: -8)
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Color.black.opacity(0.55))
                        .mask(
                            Rectangle()
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .frame(width: hole.width, height: hole.height)
                                    .position(x: hole.midX, y: hole.midY)
                                    .blendMode(.destinationOut))
                                .compositingGroup()
                        )
                        .ignoresSafeArea()
                        .allowsHitTesting(false)   // taps pass through to the real control

                    Text(caption)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.7)))
                        .position(x: hole.midX, y: hole.maxY + 28)

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
