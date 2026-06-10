import XCTest
@testable import WakeKeeperCore

final class PowerCommandFactoryTests: XCTestCase {
    func testCaffeinateCommandPreventsIdleDisplayDiskAndSystemSleep() {
        XCTAssertEqual(
            PowerCommandFactory.caffeinateCommand,
            ShellCommand("/usr/bin/caffeinate", ["-dimsu"])
        )
    }

    func testEnableDisablesleepCommandUsesAllPowerSources() {
        XCTAssertEqual(
            PowerCommandFactory.setDisablesleep(true),
            ShellCommand("/usr/bin/pmset", ["-a", "disablesleep", "1"])
        )
    }

    func testNonInteractiveSudoWrapsCommandWithoutPrompting() {
        XCTAssertEqual(
            PowerCommandFactory.nonInteractiveSudoCommand(
                for: ShellCommand("/usr/bin/pmset", ["-a", "disablesleep", "1"])
            ),
            ShellCommand("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", "1"])
        )
    }

    func testRestoreFallsBackToEnablingNormalSleepWhenNoSnapshotValueExists() {
        XCTAssertEqual(
            PowerCommandFactory.restoreDisablesleepCommands(from: DisablesleepState()),
            [ShellCommand("/usr/bin/pmset", ["-a", "disablesleep", "0"])]
        )
    }

    func testRestorePreservesPerPowerSourceSnapshotValues() {
        XCTAssertEqual(
            PowerCommandFactory.restoreDisablesleepCommands(
                from: DisablesleepState(battery: 1, ac: 0)
            ),
            [
                ShellCommand("/usr/bin/pmset", ["-b", "disablesleep", "1"]),
                ShellCommand("/usr/bin/pmset", ["-c", "disablesleep", "0"])
            ]
        )
    }

    func testShellEscapesArgumentsForPrivilegedScript() {
        let command = ShellCommand("/bin/echo", ["plain", "has spaces", "it's ok"])

        XCTAssertEqual(command.shellScript, "/bin/echo plain 'has spaces' 'it'\\''s ok'")
    }
}
