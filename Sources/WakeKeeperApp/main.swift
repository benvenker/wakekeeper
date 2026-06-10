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
        if controller.isAwakeModeEnabled {
            try? controller.disableAwakeMode()
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

        statusMenuItem.title = isEnabled ? "WakeKeeper: keeping agents awake" : "WakeKeeper: normal sleep"
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

final class PowerController {
    private let snapshotKey = "WakeKeeper.savedPowerSettingsSnapshot"
    private var caffeinateProcess: Process?

    var isAwakeModeEnabled: Bool {
        caffeinateProcess?.isRunning == true
    }

    var hasSavedSnapshot: Bool {
        loadSnapshot() != nil
    }

    func enableAwakeMode() throws {
        if !hasSavedSnapshot {
            let currentState = try readCurrentDisablesleepState()
            saveSnapshot(PowerSettingsSnapshot(disablesleep: currentState))
        }

        try runPrivileged([PowerCommandFactory.setDisablesleep(true)])
        try startCaffeinateIfNeeded()
    }

    func disableAwakeMode() throws {
        stopCaffeinate()
        try restoreNormalSleep()
    }

    func restoreNormalSleep() throws {
        let snapshot = loadSnapshot()
        let commands = PowerCommandFactory.restoreDisablesleepCommands(
            from: snapshot?.disablesleep ?? DisablesleepState()
        )

        try runPrivileged(commands)
        clearSnapshot()
    }

    private func startCaffeinateIfNeeded() throws {
        guard caffeinateProcess?.isRunning != true else {
            return
        }

        let command = PowerCommandFactory.caffeinateCommand
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        caffeinateProcess = process
    }

    private func stopCaffeinate() {
        guard let process = caffeinateProcess else {
            return
        }

        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }

        caffeinateProcess = nil
    }

    private func readCurrentDisablesleepState() throws -> DisablesleepState {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "custom"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return PMSetParser.parseCustomDisablesleep(text)
    }

    private func runPrivileged(_ commands: [ShellCommand]) throws {
        guard !commands.isEmpty else {
            return
        }

        for command in commands {
            let sudoCommand = PowerCommandFactory.nonInteractiveSudoCommand(for: command)
            let process = Process()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: sudoCommand.executable)
            process.arguments = sudoCommand.arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let data = stderr.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw PowerControllerError.passwordlessSudoUnavailable(message)
            }
        }
    }

    private func saveSnapshot(_ snapshot: PowerSettingsSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        UserDefaults.standard.set(data, forKey: snapshotKey)
    }

    private func loadSnapshot() -> PowerSettingsSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey) else {
            return nil
        }

        return try? JSONDecoder().decode(PowerSettingsSnapshot.self, from: data)
    }

    private func clearSnapshot() {
        UserDefaults.standard.removeObject(forKey: snapshotKey)
    }
}

enum PowerControllerError: LocalizedError {
    case passwordlessSudoUnavailable(String?)

    var errorDescription: String? {
        switch self {
        case .passwordlessSudoUnavailable(let message):
            let detail = message.map { "\n\nsudo said: \($0)" } ?? ""
            return """
            Passwordless WakeKeeper setup is not installed yet.

            Run:
            /Users/ben/code/wakekeeper/scripts/install-sudoers.sh

            That asks for your administrator password once, then WakeKeeper can toggle sleep without prompting.\(detail)
            """
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
