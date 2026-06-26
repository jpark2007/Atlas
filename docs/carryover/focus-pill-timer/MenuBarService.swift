// CARRYOVER — from old Atlas prototype. macOS-only (NSStatusBar menu bar). Restyle/adapt before use.
// Shows a live focus timer in the macOS menu bar + quick actions.
import AppKit
import SwiftUI
import SwiftData

@MainActor
final class MenuBarService {
    private var statusItem: NSStatusItem?
    private var tickTimer: Timer?
    private weak var focusVM: FocusViewModel?
    private var panelController: CapturePanelController?
    private var container: ModelContainer?
    private var lastKnownRunning: Bool = false
    private var lastKnownOnBreak: Bool = false

    private var elapsedItem: NSMenuItem?
    private var breakElapsedItem: NSMenuItem?
    private var breakToggleItem: NSMenuItem?

    deinit { tickTimer?.invalidate() }

    func setup(
        focusVM: FocusViewModel,
        panelController: CapturePanelController,
        container: ModelContainer
    ) {
        self.focusVM = focusVM
        self.panelController = panelController
        self.container = container

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "Atlas")
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        }

        rebuildMenu()

        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(tickTimer!, forMode: .common)
    }

    private func refresh() {
        guard let button = statusItem?.button else { return }
        let isRunning = focusVM?.isRunning ?? false
        let isOnBreak = focusVM?.isOnBreak ?? false

        if let vm = focusVM, isRunning {
            button.title = "  Atlas · \(vm.elapsedFormatted)"
        } else {
            button.title = ""
        }

        if isRunning != lastKnownRunning || isOnBreak != lastKnownOnBreak {
            lastKnownRunning = isRunning
            lastKnownOnBreak = isOnBreak
            rebuildMenu()
        } else if isRunning, let vm = focusVM {
            if let font = NSFont(name: "Menlo", size: 12) {
                elapsedItem?.attributedTitle = NSAttributedString(
                    string: "\(vm.elapsedFormatted) elapsed",
                    attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
                )
            } else {
                elapsedItem?.title = "\(vm.elapsedFormatted) elapsed"
            }
            if isOnBreak {
                if let font = NSFont(name: "Menlo", size: 12) {
                    breakElapsedItem?.attributedTitle = NSAttributedString(
                        string: "Break · \(vm.breakElapsedFormatted)",
                        attributes: [.font: font, .foregroundColor: NSColor.systemOrange]
                    )
                } else {
                    breakElapsedItem?.title = "Break · \(vm.breakElapsedFormatted)"
                }
            }
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        elapsedItem = nil
        breakElapsedItem = nil
        breakToggleItem = nil

        if let vm = focusVM, vm.isRunning {
            let projectName = vm.selectedProject?.name ?? "Focus"
            let header = NSMenuItem(title: "Focused on \(projectName)", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            let elapsed = NSMenuItem(title: "\(vm.elapsedFormatted) elapsed", action: nil, keyEquivalent: "")
            elapsed.isEnabled = false
            if let font = NSFont(name: "Menlo", size: 12) {
                elapsed.attributedTitle = NSAttributedString(
                    string: "\(vm.elapsedFormatted) elapsed",
                    attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
                )
            }
            menu.addItem(elapsed)
            elapsedItem = elapsed

            if vm.isOnBreak {
                let brk = NSMenuItem(title: "Break · \(vm.breakElapsedFormatted)", action: nil, keyEquivalent: "")
                brk.isEnabled = false
                if let font = NSFont(name: "Menlo", size: 12) {
                    brk.attributedTitle = NSAttributedString(
                        string: "Break · \(vm.breakElapsedFormatted)",
                        attributes: [.font: font, .foregroundColor: NSColor.systemOrange]
                    )
                }
                menu.addItem(brk)
                breakElapsedItem = brk
            }

            menu.addItem(.separator())

            let breakLabel = vm.isOnBreak ? "Resume Focus" : "Take a Break"
            let breakItem = NSMenuItem(title: breakLabel, action: #selector(toggleBreak), keyEquivalent: "")
            breakItem.target = self
            menu.addItem(breakItem)
            breakToggleItem = breakItem

            let end = NSMenuItem(title: "End Session", action: #selector(endSession), keyEquivalent: "")
            end.target = self
            menu.addItem(end)
        } else {
            let capture = NSMenuItem(title: "New Capture", action: #selector(triggerCapture), keyEquivalent: " ")
            capture.keyEquivalentModifierMask = [.command, .shift]
            capture.target = self
            menu.addItem(capture)
        }

        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open Atlas", action: #selector(openAtlas), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let quit = NSMenuItem(title: "Quit Atlas", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem?.menu = menu
    }

    @objc private func triggerCapture() { panelController?.show() }

    @objc private func toggleBreak() {
        guard let vm = focusVM else { return }
        if vm.isOnBreak { vm.endBreak() } else { vm.startBreak() }
        lastKnownOnBreak = vm.isOnBreak
        rebuildMenu()
    }

    @objc private func endSession() {
        guard let vm = focusVM, let container else { return }
        vm.requestEndSession()
        vm.commitSession(notes: nil, context: container.mainContext)
        openAtlas()
    }

    @objc private func openAtlas() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}
