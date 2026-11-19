import XCTest
@testable import RulesCore

final class WhitelistTests: XCTestCase {
    func testNormalizesUserFriendlyEntries() throws {
        let text = """
        # Moja biała lista

        Example.com
        https://www.Onet.pl/news?x=1
        wp.pl:443   # z portem
        sub.domain.co.uk.
        example.com
        """
        XCTAssertEqual(try Whitelist.parseDomains(text),
                       ["example.com", "onet.pl", "wp.pl", "sub.domain.co.uk"])
    }

    func testHandlesWindowsLineEndingsAndReportsCorrectLine() {
        XCTAssertThrowsError(try Whitelist.parseDomains("a.pl\r\nzła wartość!\r\n")) {
            XCTAssertEqual($0 as? Whitelist.ParseError, .invalidDomain(line: 2, value: "zła wartość!"))
        }
    }

    func testRejectsSingleLabelHost() {
        XCTAssertThrowsError(try Whitelist.parseDomains("localhost")) {
            XCTAssertEqual($0 as? Whitelist.ParseError, .invalidDomain(line: 1, value: "localhost"))
        }
    }

    func testEmptyFileGivesNoDomains() throws {
        XCTAssertEqual(try Whitelist.parseDomains("# tylko komentarz\n\n"), [])
    }

    func testBuildsDocumentExceptionRules() {
        XCTAssertEqual(Whitelist.rules(forDomains: ["example.com", "wp.pl"]),
                       ["@@||example.com^$document", "@@||wp.pl^$document"])
    }
}
