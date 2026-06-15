import XCTest
@testable import Dientempo

final class SpanishNumberFormatterTests: XCTestCase {
    func testSpanishNumberWordsAtKeyBoundaries() {
        XCTAssertEqual(SpanishNumberFormatter.words(for: 0), "cero")
        XCTAssertEqual(SpanishNumberFormatter.words(for: 16), "dieciséis")
        XCTAssertEqual(SpanishNumberFormatter.words(for: 21), "veintiuno")
        XCTAssertEqual(SpanishNumberFormatter.words(for: 26), "veintiséis")
        XCTAssertEqual(SpanishNumberFormatter.words(for: 31), "treinta y uno")
        XCTAssertEqual(SpanishNumberFormatter.words(for: 100), "cien")
        XCTAssertEqual(SpanishNumberFormatter.words(for: 101), "ciento uno")
        XCTAssertEqual(SpanishNumberFormatter.words(for: 199), "ciento noventa y nueve")
        XCTAssertEqual(SpanishNumberFormatter.words(for: 200), "doscientos")
    }
}
