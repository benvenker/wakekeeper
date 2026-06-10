import Foundation

public enum PMSetParser {
    public static func parseCustomDisablesleep(_ output: String) -> DisablesleepState {
        var currentSource: PowerSource?
        var state = DisablesleepState()

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            switch line {
            case "Battery Power:":
                currentSource = .battery
                continue
            case "AC Power:":
                currentSource = .ac
                continue
            default:
                break
            }

            guard line.hasPrefix("disablesleep") else {
                continue
            }

            let pieces = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard pieces.count >= 2, let value = Int(pieces[1]) else {
                continue
            }

            switch currentSource {
            case .battery:
                state.battery = value
            case .ac:
                state.ac = value
            case .none:
                break
            }
        }

        return state
    }
}
