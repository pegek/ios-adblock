import XCTest
@testable import RulesCore

final class FilterSourcesTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testParsesAllThreeBlockers() throws {
        let sources = try FilterSources.parse(data("""
        {"ads":["https://a.example/1.txt","https://a.example/2.txt"],
         "trackers":["https://t.example/list.txt"],
         "cookies":["https://c.example/list.txt"]}
        """))
        XCTAssertEqual(FilterSources.blockerKeys, ["ads", "trackers", "cookies"])
        XCTAssertEqual(sources.urlsByBlocker["ads"]?.map(\.absoluteString),
                       ["https://a.example/1.txt", "https://a.example/2.txt"])
        XCTAssertEqual(sources.urlsByBlocker["cookies"]?.count, 1)
    }

    func testMissingBlockerFails() {
        XCTAssertThrowsError(try FilterSources.parse(data("""
        {"ads":["https://a.example/1.txt"],"trackers":["https://t.example/1.txt"]}
        """))) { XCTAssertEqual($0 as? FilterSources.LoadError, .missingBlocker("cookies")) }
    }

    func testUnknownBlockerFails() {
        XCTAssertThrowsError(try FilterSources.parse(data("""
        {"ads":["https://a.example/1.txt"],"trackers":["https://t.example/1.txt"],
         "cookies":["https://c.example/1.txt"],"video":["https://v.example/1.txt"]}
        """))) { XCTAssertEqual($0 as? FilterSources.LoadError, .unknownBlocker("video")) }
    }

    func testEmptyBlockerFails() {
        XCTAssertThrowsError(try FilterSources.parse(data("""
        {"ads":[],"trackers":["https://t.example/1.txt"],"cookies":["https://c.example/1.txt"]}
        """))) { XCTAssertEqual($0 as? FilterSources.LoadError, .emptyBlocker("ads")) }
    }

    func testNonHttpsURLFails() {
        XCTAssertThrowsError(try FilterSources.parse(data("""
        {"ads":["http://a.example/1.txt"],"trackers":["https://t.example/1.txt"],"cookies":["https://c.example/1.txt"]}
        """))) { XCTAssertEqual($0 as? FilterSources.LoadError, .invalidURL("http://a.example/1.txt")) }
    }

    func testInvalidJSONFails() {
        XCTAssertThrowsError(try FilterSources.parse(data("to nie json"))) {
            XCTAssertEqual($0 as? FilterSources.LoadError, .invalidJSON)
        }
    }
}
