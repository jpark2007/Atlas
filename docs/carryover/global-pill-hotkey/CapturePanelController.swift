// CARRYOVER — from old Atlas prototype. macOS-only (NSPanel). Restyle/adapt before use.
// Hosts the floating "pill" command panel summoned by the global hotkey.
import AppKit
import SwiftUI
import SwiftData

@MainActor
final class CapturePanelController {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var globalClickMonitor: Any?
    private var localEventMonitor: Any?
    private let container: ModelContainer
    private let captureVM: CaptureViewModel

    init(container: ModelContainer, captureVM: CaptureViewModel) {
        self.container = container
        self.captureVM = captureVM
    }

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        captureVM.setContext(container.mainContext)
        captureVM.startCapture()

        repositionPanel(panel)
        panel.orderFrontRegardless()
        installEventMonitors(panel: panel)
    }

    func hide() {
        panel?.orderOut(nil)
        removeEventMonitors()
        captureVM.dismiss()
    }

    private func makePanel() -> NSPanel {
        let initialSize = NSSize(width: 520, height: 160)
        let rect = NSRect(origin: .zero, size: initialSize)
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false

        let root = CapturePanelView(vm: captureVM, onDismiss: { [weak self] in
            self?.hide()
        })
        .modelContainer(container)

        let hosting = NSHostingController(rootView: AnyView(root))
        hosting.sizingOptions = [.intrinsicContentSize]
        self.hostingController = hosting
        panel.contentViewController = hosting

        return panel
    }

    private func repositionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        let y = visible.minY + 24
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func installEventMonitors(panel: NSPanel) {
        removeEventMonitors()
        // Clicks in other apps — dismiss
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        // Clicks inside Atlas but outside the panel — dismiss. Also ESC.
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self, weak panel] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { // ESC
                    Task { @MainActor in self.hide() }
                    return nil
                }
                return event
            }
            if event.window !== panel {
                Task { @MainActor in self.hide() }
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }
}
