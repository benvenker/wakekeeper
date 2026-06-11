import AppKit
import Foundation
import WakeKeeperCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = PowerController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem()
    private let toggleMenuItem = NSMenuItem()
    private let restoreMenuItem = NSMenuItem()
    private let quitMenuItem = NSMenuItem()
    private var isBusy = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenu()
        refreshMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if controller.needsRestoration {
            try? controller.disableAwakeMode()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard controller.needsRestoration else {
            return .terminateNow
        }

        do {
            try controller.disableAwakeMode()
            refreshMenu()
            return .terminateNow
        } catch {
            refreshMenu()
            showError(error)
            return .terminateCancel
        }
    }

    private func configureMenu() {
        statusMenuItem.isEnabled = false

        toggleMenuItem.target = self
        toggleMenuItem.action = #selector(toggleAwakeMode)

        restoreMenuItem.title = "Restore Normal Sleep"
        restoreMenuItem.target = self
        restoreMenuItem.action = #selector(restoreNormalSleep)

        quitMenuItem.title = "Quit WakeKeeper"
        quitMenuItem.target = self
        quitMenuItem.action = #selector(quit)

        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(toggleMenuItem)
        menu.addItem(restoreMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitMenuItem)

        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "WakeKeeper"
    }

    private func refreshMenu() {
        let isEnabled = controller.isAwakeModeEnabled
        let hasSnapshot = controller.hasSavedSnapshot

        if isEnabled {
            statusMenuItem.title = "WakeKeeper: keeping agents awake"
        } else if hasSnapshot {
            statusMenuItem.title = "WakeKeeper: restore needed"
        } else {
            statusMenuItem.title = "WakeKeeper: normal sleep"
        }

        toggleMenuItem.title = isEnabled ? "Turn Off" : "Turn On"
        toggleMenuItem.state = isEnabled ? .on : .off
        toggleMenuItem.isEnabled = !isBusy
        restoreMenuItem.isHidden = isEnabled || !hasSnapshot
        restoreMenuItem.isEnabled = !isBusy
        quitMenuItem.isEnabled = !isBusy

        let symbolName = isEnabled ? "bolt.circle.fill" : "bolt.circle"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "WakeKeeper") {
            image.isTemplate = true
            statusItem.button?.image = image
            statusItem.button?.title = ""
        } else {
            statusItem.button?.image = nil
            statusItem.button?.title = isEnabled ? "WK+" : "WK"
        }
    }

    @objc private func toggleAwakeMode() {
        if controller.isAwakeModeEnabled {
            performPowerChange { try self.controller.disableAwakeMode() }
        } else {
            performPowerChange { try self.controller.enableAwakeMode() }
        }
    }

    @objc private func restoreNormalSleep() {
        performPowerChange { try self.controller.restoreNormalSleep() }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func performPowerChange(_ operation: () throws -> Void) {
        isBusy = true
        refreshMenu()

        let result = Result { try operation() }
        isBusy = false
        refreshMenu()

        if case .failure(let error) = result {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "WakeKeeper could not change sleep settings"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
