import XCTest
@testable import WakeKeeperCore

final class PowerControllerTests: XCTestCase {
    func testEnableFailureClearsNewSnapshotAndDoesNotStartCaffeinate() {
        let runner = FakePowerProcessRunner(results: [
            CommandResult(terminationStatus: 0, standardOutput: pmsetOutput),
            CommandResult(terminationStatus: 1, standardError: "sudo: a password is required")
        ])
        let store = FakePowerSnapshotStore()
        let controller = PowerController(runner: runner, store: store)

        XCTAssertThrowsError(try controller.enableAwakeMode()) { error in
            XCTAssertEqual(
                error as? PowerControllerError,
                .passwordlessSudoUnavailable("sudo: a password is required")
            )
        }

        XCTAssertNil(store.snapshot)
        XCTAssertTrue(runner.startedProcesses.isEmpty)
        XCTAssertEqual(runner.events, [
            "run /usr/bin/pmset -g custom",
            "run /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 1"
        ])
    }

    func testPmsetReadFailureStopsBeforeMutatingPowerSettings() {
        let runner = FakePowerProcessRunner(results: [
            CommandResult(terminationStatus: 1, standardError: "pmset failed")
        ])
        let store = FakePowerSnapshotStore()
        let controller = PowerController(runner: runner, store: store)

        XCTAssertThrowsError(try controller.enableAwakeMode()) { error in
            XCTAssertEqual(error as? PowerControllerError, .pmsetReadFailed("pmset failed"))
        }

        XCTAssertNil(store.snapshot)
        XCTAssertTrue(runner.startedProcesses.isEmpty)
        XCTAssertEqual(runner.events, ["run /usr/bin/pmset -g custom"])
    }

    func testDisableRestoresDisablesleepBeforeStoppingCaffeinate() throws {
        let runner = FakePowerProcessRunner(results: [
            CommandResult(terminationStatus: 0),
            CommandResult(terminationStatus: 0),
            CommandResult(terminationStatus: 0)
        ])
        let store = FakePowerSnapshotStore(snapshot: snapshot(battery: 1, ac: 0))
        let controller = PowerController(runner: runner, store: store)

        try controller.enableAwakeMode()
        try controller.disableAwakeMode()

        XCTAssertEqual(runner.events, [
            "run /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 1",
            "start /usr/bin/caffeinate -dimsu",
            "run /usr/bin/sudo -n /usr/bin/pmset -b disablesleep 1",
            "run /usr/bin/sudo -n /usr/bin/pmset -c disablesleep 0",
            "terminate"
        ])
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(controller.isAwakeModeEnabled)
    }

    func testDisableKeepsAwakeModeAndSnapshotWhenRestoreFails() throws {
        let runner = FakePowerProcessRunner(results: [
            CommandResult(terminationStatus: 0),
            CommandResult(terminationStatus: 1, standardError: "not allowed")
        ])
        let store = FakePowerSnapshotStore(snapshot: snapshot(battery: 1, ac: 0))
        let controller = PowerController(runner: runner, store: store)

        try controller.enableAwakeMode()

        XCTAssertThrowsError(try controller.disableAwakeMode()) { error in
            XCTAssertEqual(error as? PowerControllerError, .passwordlessSudoUnavailable("not allowed"))
        }

        XCTAssertTrue(controller.isAwakeModeEnabled)
        XCTAssertTrue(controller.needsRestoration)
        XCTAssertNotNil(store.snapshot)
        XCTAssertEqual(runner.events, [
            "run /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 1",
            "start /usr/bin/caffeinate -dimsu",
            "run /usr/bin/sudo -n /usr/bin/pmset -b disablesleep 1"
        ])
    }

    func testSavedSnapshotMeansRestorationIsPendingAfterRelaunch() {
        let runner = FakePowerProcessRunner()
        let store = FakePowerSnapshotStore(snapshot: snapshot(battery: 1, ac: 0))
        let controller = PowerController(runner: runner, store: store)

        XCTAssertFalse(controller.isAwakeModeEnabled)
        XCTAssertTrue(controller.hasSavedSnapshot)
        XCTAssertTrue(controller.needsRestoration)
    }

    private var pmsetOutput: String {
        """
        Battery Power:
         disablesleep        1
        AC Power:
         disablesleep        0
        """
    }

    private func snapshot(battery: Int, ac: Int) -> PowerSettingsSnapshot {
        PowerSettingsSnapshot(
            capturedAt: Date(timeIntervalSince1970: 0),
            disablesleep: DisablesleepState(battery: battery, ac: ac)
        )
    }
}

private final class FakePowerProcessRunner: PowerProcessRunning {
    var results: [CommandResult]
    var events: [String] = []
    var startedProcesses: [FakeRunningPowerProcess] = []

    init(results: [CommandResult] = []) {
        self.results = results
    }

    func run(_ command: ShellCommand) throws -> CommandResult {
        events.append("run \(description(of: command))")

        guard !results.isEmpty else {
            throw TestFailure.missingCommandResult
        }

        return results.removeFirst()
    }

    func start(_ command: ShellCommand) throws -> RunningPowerProcess {
        events.append("start \(description(of: command))")
        let process = FakeRunningPowerProcess { [weak self] in
            self?.events.append("terminate")
        }
        startedProcesses.append(process)
        return process
    }

    private func description(of command: ShellCommand) -> String {
        ([command.executable] + command.arguments).joined(separator: " ")
    }
}

private final class FakeRunningPowerProcess: RunningPowerProcess {
    private let onTerminate: () -> Void
    private(set) var isRunning = true

    init(onTerminate: @escaping () -> Void) {
        self.onTerminate = onTerminate
    }

    func terminateAndWait() {
        onTerminate()
        isRunning = false
    }
}

private final class FakePowerSnapshotStore: PowerSnapshotStoring {
    var snapshot: PowerSettingsSnapshot?

    init(snapshot: PowerSettingsSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func loadSnapshot() -> PowerSettingsSnapshot? {
        snapshot
    }

    func saveSnapshot(_ snapshot: PowerSettingsSnapshot) throws {
        self.snapshot = snapshot
    }

    func clearSnapshot() {
        snapshot = nil
    }
}

private enum TestFailure: Error {
    case missingCommandResult
}
