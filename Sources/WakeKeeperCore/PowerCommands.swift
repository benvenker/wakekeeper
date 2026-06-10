import Foundation

public enum PowerSource: String, Codable, Equatable, Sendable {
    case battery
    case ac
}

public struct DisablesleepState: Codable, Equatable, Sendable {
    public var battery: Int?
    public var ac: Int?

    public init(battery: Int? = nil, ac: Int? = nil) {
        self.battery = battery
        self.ac = ac
    }

    public var isEmpty: Bool {
        battery == nil && ac == nil
    }
}

public struct PowerSettingsSnapshot: Codable, Equatable, Sendable {
    public var capturedAt: Date
    public var disablesleep: DisablesleepState

    public init(capturedAt: Date = Date(), disablesleep: DisablesleepState) {
        self.capturedAt = capturedAt
        self.disablesleep = disablesleep
    }
}

public struct ShellCommand: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]

    public init(_ executable: String, _ arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    public var shellScript: String {
        ([executable] + arguments).map(Self.shellEscape).joined(separator: " ")
    }

    public static func shellEscape(_ value: String) -> String {
        if value.range(of: #"^[A-Za-z0-9_/\-.:=]+$"#, options: .regularExpression) != nil {
            return value
        }

        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public enum PowerCommandFactory {
    public static var caffeinateCommand: ShellCommand {
        ShellCommand("/usr/bin/caffeinate", ["-dimsu"])
    }

    public static func nonInteractiveSudoCommand(for command: ShellCommand) -> ShellCommand {
        ShellCommand("/usr/bin/sudo", ["-n", command.executable] + command.arguments)
    }

    public static func setDisablesleep(_ enabled: Bool) -> ShellCommand {
        ShellCommand("/usr/bin/pmset", ["-a", "disablesleep", enabled ? "1" : "0"])
    }

    public static func restoreDisablesleepCommands(from state: DisablesleepState) -> [ShellCommand] {
        if state.isEmpty {
            return [setDisablesleep(false)]
        }

        var commands: [ShellCommand] = []

        if let battery = state.battery {
            commands.append(ShellCommand("/usr/bin/pmset", ["-b", "disablesleep", String(battery)]))
        } else {
            commands.append(ShellCommand("/usr/bin/pmset", ["-b", "disablesleep", "0"]))
        }

        if let ac = state.ac {
            commands.append(ShellCommand("/usr/bin/pmset", ["-c", "disablesleep", String(ac)]))
        } else {
            commands.append(ShellCommand("/usr/bin/pmset", ["-c", "disablesleep", "0"]))
        }

        return commands
    }
}
