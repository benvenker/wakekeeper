import Foundation

public struct CommandResult: Equatable, Sendable {
    public var terminationStatus: Int32
    public var standardOutput: String
    public var standardError: String

    public init(terminationStatus: Int32, standardOutput: String = "", standardError: String = "") {
        self.terminationStatus = terminationStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public protocol RunningPowerProcess: AnyObject {
    var isRunning: Bool { get }
    func terminateAndWait()
}

public protocol PowerProcessRunning {
    func run(_ command: ShellCommand) throws -> CommandResult
    func start(_ command: ShellCommand) throws -> RunningPowerProcess
}

public protocol PowerSnapshotStoring {
    func loadSnapshot() -> PowerSettingsSnapshot?
    func saveSnapshot(_ snapshot: PowerSettingsSnapshot) throws
    func clearSnapshot()
}

public final class PowerController {
    private let runner: PowerProcessRunning
    private let store: PowerSnapshotStoring
    private var caffeinateProcess: RunningPowerProcess?

    public init(
        runner: PowerProcessRunning = FoundationPowerProcessRunner(),
        store: PowerSnapshotStoring = UserDefaultsPowerSnapshotStore()
    ) {
        self.runner = runner
        self.store = store
    }

    public var isAwakeModeEnabled: Bool {
        caffeinateProcess?.isRunning == true
    }

    public var hasSavedSnapshot: Bool {
        store.loadSnapshot() != nil
    }

    public var needsRestoration: Bool {
        isAwakeModeEnabled || hasSavedSnapshot
    }

    public func enableAwakeMode() throws {
        let createdSnapshot = try captureSnapshotIfNeeded()

        do {
            try runPrivileged([PowerCommandFactory.setDisablesleep(true)])
        } catch {
            if createdSnapshot {
                store.clearSnapshot()
            }
            throw error
        }

        try startCaffeinateIfNeeded()
    }

    public func disableAwakeMode() throws {
        try restoreNormalSleep()
        stopCaffeinate()
    }

    public func restoreNormalSleep() throws {
        let snapshot = store.loadSnapshot()
        let commands = PowerCommandFactory.restoreDisablesleepCommands(
            from: snapshot?.disablesleep ?? DisablesleepState()
        )

        try runPrivileged(commands)
        store.clearSnapshot()
    }

    private func captureSnapshotIfNeeded() throws -> Bool {
        guard !hasSavedSnapshot else {
            return false
        }

        let currentState = try readCurrentDisablesleepState()
        try store.saveSnapshot(PowerSettingsSnapshot(disablesleep: currentState))
        return true
    }

    private func startCaffeinateIfNeeded() throws {
        guard caffeinateProcess?.isRunning != true else {
            return
        }

        caffeinateProcess = try runner.start(PowerCommandFactory.caffeinateCommand)
    }

    private func stopCaffeinate() {
        guard let process = caffeinateProcess else {
            return
        }

        if process.isRunning {
            process.terminateAndWait()
        }

        caffeinateProcess = nil
    }

    private func readCurrentDisablesleepState() throws -> DisablesleepState {
        let result = try runner.run(ShellCommand("/usr/bin/pmset", ["-g", "custom"]))

        guard result.terminationStatus == 0 else {
            throw PowerControllerError.pmsetReadFailed(clean(result.standardError))
        }

        return PMSetParser.parseCustomDisablesleep(result.standardOutput)
    }

    private func runPrivileged(_ commands: [ShellCommand]) throws {
        for command in commands {
            let sudoCommand = PowerCommandFactory.nonInteractiveSudoCommand(for: command)
            let result = try runner.run(sudoCommand)

            guard result.terminationStatus == 0 else {
                throw PowerControllerError.passwordlessSudoUnavailable(clean(result.standardError))
            }
        }
    }

    private func clean(_ message: String) -> String? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum PowerControllerError: LocalizedError, Equatable {
    case passwordlessSudoUnavailable(String?)
    case pmsetReadFailed(String?)

    public var errorDescription: String? {
        switch self {
        case .passwordlessSudoUnavailable(let message):
            let detail = message.map { "\n\nsudo said: \($0)" } ?? ""
            return """
            Passwordless WakeKeeper setup is not installed yet.

            Run ./scripts/install-sudoers.sh from the WakeKeeper checkout, or see README.md for setup instructions.

            That asks for your administrator password once, then WakeKeeper can toggle sleep without prompting.\(detail)
            """

        case .pmsetReadFailed(let message):
            let detail = message.map { "\n\npmset said: \($0)" } ?? ""
            return "WakeKeeper could not read the current macOS sleep settings.\(detail)"
        }
    }
}

public final class UserDefaultsPowerSnapshotStore: PowerSnapshotStoring {
    private let key: String
    private let userDefaults: UserDefaults

    public init(
        key: String = "WakeKeeper.savedPowerSettingsSnapshot",
        userDefaults: UserDefaults = .standard
    ) {
        self.key = key
        self.userDefaults = userDefaults
    }

    public func loadSnapshot() -> PowerSettingsSnapshot? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(PowerSettingsSnapshot.self, from: data)
    }

    public func saveSnapshot(_ snapshot: PowerSettingsSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        userDefaults.set(data, forKey: key)
    }

    public func clearSnapshot() {
        userDefaults.removeObject(forKey: key)
    }
}

public final class FoundationPowerProcessRunner: PowerProcessRunning {
    public init() {}

    public func run(_ command: ShellCommand) throws -> CommandResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        return CommandResult(
            terminationStatus: process.terminationStatus,
            standardOutput: Self.read(stdout),
            standardError: Self.read(stderr)
        )
    }

    public func start(_ command: ShellCommand) throws -> RunningPowerProcess {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return FoundationRunningPowerProcess(process)
    }

    private static func read(_ pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private final class FoundationRunningPowerProcess: RunningPowerProcess {
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    var isRunning: Bool {
        process.isRunning
    }

    func terminateAndWait() {
        process.terminate()
        process.waitUntilExit()
    }
}
