import WidgetKit
import SwiftUI

@main
struct AtlasWidgetsBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        TodayWidget()
        LockRectangularWidget()
        LockCircularWidget()
        controls
    }

    @WidgetBundleBuilder
    var controls: some Widget {
        if #available(iOS 18.0, *) {
            CaptureControl()
        }
    }
}
