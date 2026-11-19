import XCTest
@testable import RulesCore

final class RuleMergerTests: XCTestCase {
    func testMergesListsDropsCommentsHeadersAndDuplicates() {
        let first = "[Adblock Plus 2.0]\n! Title: X\n||a.com^\n\n##.ad\n[$path=/x]example.org##.promo\n"
        let second = "||a.com^\r\n  ||b.com^  \r\n"
        let merged = RuleMerger.merge(listTexts: [first, second],
                                      whitelistRules: ["@@||ok.pl^$document"])
        XCTAssertEqual(merged, [
            "||a.com^",
            "##.ad",
            "[$path=/x]example.org##.promo",
            "||b.com^",
            "@@||ok.pl^$document",
        ])
    }

    func testWhitelistRulesGoLast() {
        let merged = RuleMerger.merge(listTexts: ["||x.com^"], whitelistRules: ["@@||y.pl^$document"])
        XCTAssertEqual(merged.last, "@@||y.pl^$document")
    }
}
