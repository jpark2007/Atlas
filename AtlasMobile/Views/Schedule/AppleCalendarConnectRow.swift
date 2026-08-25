import SwiftUI
import EventKit
import UIKit
import AtlasCore

/// Connect Apple Calendar from the phone (Phase 3). Read-only: Atlas shows your Apple
/// events alongside your schedule and never writes to them from iOS.
///
/// Deliberately a **standalone row** so it can live wherever the calendar connections
/// list ends up — drop `AppleCalendarConnectRow()` into the Settings calendars section
/// and it works unchanged. It's mounted on the Schedule list until then.
struct AppleCalendarConnectRow: View {
    @EnvironmentObject private var store: MobileStore
    /// The shown day, so a fresh connect immediately fills the visible window.
    var day: Date = Date()

    @State private var connected = false
    @State private var denied = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(MobileTheme.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Calendar")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                Text(subtitle)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.faint)
            }
            Spacer()
            action
        }
        .contentShape(Rectangle())
        .onAppear(perform: syncState)
    }

    private var subtitle: String {
        if denied { return "Allow calendar access in iOS Settings" }
        return connected ? "Read-only on this phone" : "Show your Apple events here"
    }

    @ViewBuilder
    private var action: some View {
        if denied {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(MobileTheme.accentText)
            .buttonStyle(.plain)
        } else if connected {
            Button("Disconnect") {
                store.appleCalendarEnabled = false
                syncState()
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(MobileTheme.muted)
            .buttonStyle(.plain)
        } else {
            Button("Connect") {
                Task {
                    await store.connectAppleCalendar(around: day)
                    syncState()
                }
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(MobileTheme.ink)
            .buttonStyle(.plain)
        }
    }

    /// EventKit permission can change outside the app (iOS Settings), so the row's state
    /// is derived from the live authorization status, never cached.
    private func syncState() {
        let status = store.eventKit.authorizationStatus
        denied = status == .denied || status == .restricted
        connected = store.appleCalendarEnabled && status == .fullAccess
    }
}
