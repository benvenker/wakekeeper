import XCTest
@testable import WakeKeeperCore

final class PMSetParserTests: XCTestCase {
    func testParsesDisablesleepForBothPowerSources() {
        let output = """
        Battery Power:
         Sleep On Power Button 1
         disablesleep        1
         sleep                1
        AC Power:
         disablesleep        0
         sleep                1
        """

        let state = PMSetParser.parseCustomDisablesleep(output)

        XCTAssertEqual(state, DisablesleepState(battery: 1, ac: 0))
    }

    func testReturnsEmptyStateWhenDisablesleepIsAbsent() {
        let output = """
        Battery Power:
         sleep                1
        AC Power:
         sleep                1
        """

        let state = PMSetParser.parseCustomDisablesleep(output)

        XCTAssertEqual(state, DisablesleepState())
    }
}
