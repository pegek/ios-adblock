# iOS Safari AdBlock v1 — plan implementacji

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Zbudować aplikację iOS z trzema Safari Content Blockerami (Reklamy, Trackery, Cookies/RODO). Reguły mają być generowane i budowane automatycznie w GitHub Actions jako niepodpisany `AdBlocker.ipa`, który użytkownik instaluje z Windowsa przez Sideloadly.

**Architecture:**
- Swift Package `tools/build-rules` pobiera listy filtrów, łączy je z białą listą i konwertuje przez AdGuard SafariConverterLib do `blockerList.json` dla każdego blokera oraz do `rules-manifest.json`.
- Projekt iOS jest opisany w `project.yml` (XcodeGen): aplikacja SwiftUI plus 3 rozszerzenia `com.apple.Safari.content-blocker`.
- Workflow GitHub Actions na `macos-15` testuje całość, buduje bez podpisu, weryfikuje `.ipa` i publikuje Release (tylko z `main`).

**Tech Stack:** Swift 5.9+, SwiftUI, SafariServices, XcodeGen, SafariConverterLib 4.3.0, GitHub Actions, bash, Sideloadly (po stronie użytkownika).

**Spec:** `docs/superpowers/specs/2026-10-15-ios-safari-adblock-design.md`

## Global Constraints

- Komputer deweloperski to Windows bez Swifta i Xcode. **Każda kompilacja i każdy test Swift działa wyłącznie w GitHub Actions.** Weryfikacja kroku = `git push` + `bash scripts/ci-wait.sh` (Task 1). Komendy uruchamiaj w Git Bash z katalogu repo.
- Praca na gałęzi `v1`. Workflow testuje każdą gałąź, a Release publikuje tylko z `main`.
- Bundle ID: aplikacja `pl.local.adblocker`, rozszerzenia `pl.local.adblocker.ads`, `pl.local.adblocker.trackers`, `pl.local.adblocker.cookies`.
- Nazwy targetów: `AdBlocker`, `AdsBlocker`, `TrackersBlocker`, `CookiesBlocker`, `AdBlockerTests`. Foldery: `Blockers/Ads`, `Blockers/Trackers`, `Blockers/Cookies`.
- Nazwy widoczne dla użytkownika: aplikacja „AdBlocker”, blokery „Reklamy”, „Trackery”, „Cookies/RODO”. Wszystkie teksty UI i komunikaty błędów po polsku.
- Klucze blokerów i ich kolejność: `ads`, `trackers`, `cookies`.
- Minimalne iOS: **16.4** (doprecyzowanie spec: reguły generujemy dla Safari 16.4, a starsze iOS odrzuciłyby cały bloker).
- SafariConverterLib przypięta `exact: "4.3.0"`. `SafariVersion.safari16_4`, `maxJsonSizeBytes = 10_000_000` (błąd iOS przy JSON > ~11 MB), limit 150 000 reguł na bloker.
- Pliki generowane nie trafiają do gita:
  - `Blockers/*/blockerList.json`
  - `App/Resources/rules-manifest.json`
  - `*.xcodeproj`
  - wygenerowane `Info.plist` (folder `Generated/`, poza folderami źródeł, żeby nie trafiły do zasobów)
  - `tools/build-rules/.build`

  To doprecyzowanie spec: zamiast placeholderów `[]` pliki powstają przed `xcodegen generate`.
- Runner `macos-15`, Xcode `latest-stable` (`maxim-lobanov/setup-xcode@v1`). Build `.ipa` z `CODE_SIGNING_ALLOWED=NO`.
- Format manifestu (wspólny kontrakt build-rules ↔ aplikacja), data w ISO 8601 UTC:
  `{"builtAt":"2026-10-15T12:00:00Z","blockers":[{"key":"ads","sourceRules":1,"safariRules":1,"discarded":0,"errors":0}]}`
- Działania na zewnątrz (utworzenie publicznego repo, merge do `main`) wymagają wyraźnej zgody użytkownika w czacie.

## Review Focus

1. **Biała lista edytowana na Windowsie.** Wpisy mogą zawierać CRLF, adresy URL z `https://`, `www.`, ścieżki, porty, wielkie litery lub komentarze. Każdy wpis ma się znormalizować do domeny. Błędna linia ma zatrzymać build z poprawnym numerem linii (testy w Task 1).
2. **Serwer listy zwraca 200 ze stroną HTML** (błąd, CAPTCHA, przekierowanie) albo ucięty plik. Build musi się zatrzymać, a poprzedni Release pozostaje (testy w Task 3).
3. **Skonwertowany JSON przekracza ~10 MB.** iOS po cichu odrzuciłby bloker, więc reguły muszą zostać przycięte, z liczbą odrzuconych reguł w ostrzeżeniu (test w Task 2).
4. **Sideloadly zmienia prefiks bundle ID.** Status blokerów w aplikacji ma nadal działać, bo identyfikatory są wyliczane z `Bundle.main.bundleIdentifier` (test w Task 4).
5. **Brakujący lub uszkodzony `rules-manifest.json`.** Aplikacja nie może się wysypać i ma pokazać „Brak danych…” (testy w Task 4).

---

## Mapa plików

| Plik | Odpowiedzialność |
|---|---|
| `.gitignore`, `.gitattributes` | Pliki generowane poza gitem; LF dla skryptów |
| `scripts/ci-wait.sh` | Czeka na run CI dla bieżącego commita i zwraca wynik |
| `tools/build-rules/Package.swift` | Pakiet: biblioteka `RulesCore`, CLI `build-rules`, testy |
| `tools/build-rules/Sources/RulesCore/FilterSources.swift` | Parsowanie i walidacja `filters/sources.json` |
| `tools/build-rules/Sources/RulesCore/Whitelist.swift` | Parsowanie `whitelist.txt` → domeny → reguły wyjątków |
| `tools/build-rules/Sources/RulesCore/RuleMerger.swift` | Łączenie list, usuwanie komentarzy i duplikatów |
| `tools/build-rules/Sources/RulesCore/BlockerConverter.swift` | Wrapper na SafariConverterLib |
| `tools/build-rules/Sources/RulesCore/BlockerJSONValidator.swift` | Walidacja wynikowego JSON |
| `tools/build-rules/Sources/RulesCore/DownloadValidator.swift` | Walidacja pobranej listy (status, HTML, liczba reguł) |
| `tools/build-rules/Sources/RulesCore/Manifest.swift` | Model i kodowanie `rules-manifest.json` |
| `tools/build-rules/Sources/BuildRules/main.swift` | CLI: pobierz → połącz → konwertuj → zapisz |
| `tools/build-rules/Tests/RulesCoreTests/*.swift` | Testy jednostkowe RulesCore |
| `filters/sources.json`, `filters/whitelist.txt` | Konfiguracja list i białej listy |
| `project.yml` | Definicja projektu XcodeGen |
| `App/*.swift` | Aplikacja SwiftUI (katalog blokerów, manifest, status, UI) |
| `AppTests/*.swift` | Testy logiki aplikacji (symulator) |
| `Blockers/Shared/ContentBlockerRequestHandler.swift` | Wspólny handler 3 rozszerzeń |
| `scripts/ci-test-app.sh` | Wybór symulatora i `xcodebuild test` |
| `scripts/package-ipa.sh`, `scripts/verify-ipa.sh`, `scripts/test-verify-ipa.sh` | Pakowanie i weryfikacja `.ipa` |
| `.github/workflows/build.yml` | Pipeline CI |
| `README.md` | Instalacja krok po kroku i checklista testów ręcznych |

---

### Task 1: Repozytorium, CI i parsowanie wejścia (FilterSources, Whitelist, RuleMerger)

**Files:**
- Create: `.gitignore`, `.gitattributes`, `scripts/ci-wait.sh`, `.github/workflows/build.yml`
- Create: `tools/build-rules/Package.swift`
- Create: `tools/build-rules/Sources/RulesCore/FilterSources.swift`, `Whitelist.swift`, `RuleMerger.swift`
- Create: `tools/build-rules/Sources/BuildRules/main.swift` (tymczasowy szkielet)
- Test: `tools/build-rules/Tests/RulesCoreTests/FilterSourcesTests.swift`, `WhitelistTests.swift`, `RuleMergerTests.swift`

**Interfaces:**
- Consumes: nic.
- Produces:
  - `FilterSources.blockerKeys: [String]` = `["ads","trackers","cookies"]`
  - `FilterSources.parse(_ data: Data) throws -> FilterSources`
  - `FilterSources.urlsByBlocker: [String: [URL]]`
  - `FilterSources.LoadError`
  - `Whitelist.parseDomains(_ text: String) throws -> [String]`
  - `Whitelist.rules(forDomains: [String]) -> [String]`
  - `Whitelist.ParseError.invalidDomain(line: Int, value: String)`
  - `RuleMerger.merge(listTexts: [String], whitelistRules: [String]) -> [String]`
  - `scripts/ci-wait.sh`

- [ ] **Step 1: Konfiguracja GitHub (z użytkownikiem)**

Zainstaluj GitHub CLI (pokaże okno zgody Windows):

```bash
winget install --id GitHub.cli -e
```

Poproś użytkownika, żeby sam wykonał w terminalu `gh auth login` (GitHub.com → HTTPS → logowanie przez przeglądarkę). Nie wpisuj za niego danych logowania. Sprawdź:

```bash
gh auth status
```

Expected: `Logged in to github.com account ...`

Zapytaj użytkownika w czacie: „Czy mogę utworzyć publiczne repo `ios-adblock` na Twoim koncie GitHub i wypchnąć do niego obecny kod?”. Dopiero po „tak”:

```bash
gh repo create ios-adblock --public --source . --remote origin --push
git checkout -b v1
```

- [ ] **Step 2: Pliki repozytorium**

`.gitignore`:

```gitignore
# Generowane w CI
Blockers/*/blockerList.json
App/Resources/rules-manifest.json
*.xcodeproj/
Generated/
build/
tools/build-rules/.build/
tools/build-rules/.swiftpm/
.DS_Store
```

`.gitattributes`:

```gitattributes
*.sh text eol=lf
*.yml text eol=lf
*.swift text eol=lf
```

`scripts/ci-wait.sh`:

```bash
#!/usr/bin/env bash
# Czeka na run GitHub Actions dla bieżącego commita i zwraca jego wynik.
# Przy błędzie wypisuje końcówkę logów nieudanych kroków.
set -euo pipefail
SHA="$(git rev-parse HEAD)"
ID=""
for _ in $(seq 1 30); do
  ID="$(gh run list --commit "$SHA" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)"
  [ -n "$ID" ] && break
  sleep 5
done
[ -n "$ID" ] || { echo "Brak runu CI dla $SHA"; exit 1; }
echo "Run CI: $ID"
if ! gh run watch "$ID" --exit-status --interval 20 > /dev/null; then
  gh run view "$ID" --log-failed | tail -120
  echo "CI: FAIL"
  exit 1
fi
echo "CI: PASS"
```

`.github/workflows/build.yml` (wersja z Task 1):

```yaml
name: build

on:
  push:
    branches: ["**"]
  workflow_dispatch:

jobs:
  build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable

      - uses: actions/cache@v4
        with:
          path: tools/build-rules/.build
          key: spm-${{ runner.os }}-${{ hashFiles('tools/build-rules/Package.swift') }}

      - name: Testy build-rules
        working-directory: tools/build-rules
        run: swift test
```

`tools/build-rules/Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BuildRules",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "build-rules", targets: ["BuildRules"]),
    ],
    dependencies: [
        .package(url: "https://github.com/AdguardTeam/SafariConverterLib.git", exact: "4.3.0"),
    ],
    targets: [
        .target(
            name: "RulesCore",
            dependencies: [
                .product(name: "ContentBlockerConverter", package: "SafariConverterLib"),
            ]
        ),
        .executableTarget(name: "BuildRules", dependencies: ["RulesCore"]),
        .testTarget(name: "RulesCoreTests", dependencies: ["RulesCore"]),
    ]
)
```

`tools/build-rules/Sources/BuildRules/main.swift` (szkielet, zastąpiony w Task 3):

```swift
print("build-rules: jeszcze nie zaimplementowane")
```

- [ ] **Step 3: Napisz testy, które nie przejdą**

`tools/build-rules/Tests/RulesCoreTests/FilterSourcesTests.swift`:

```swift
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
```

`tools/build-rules/Tests/RulesCoreTests/WhitelistTests.swift`:

```swift
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
```

`tools/build-rules/Tests/RulesCoreTests/RuleMergerTests.swift`:

```swift
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
```

- [ ] **Step 4: Uruchom testy i sprawdź, że NIE przechodzą**

```bash
git add -A && git commit -m "test: testy parsowania wejścia build-rules" && git push -u origin v1
bash scripts/ci-wait.sh
```

Expected: `CI: FAIL`, a w logu błędy kompilacji typu `cannot find 'FilterSources' in scope`.

- [ ] **Step 5: Implementacja**

`tools/build-rules/Sources/RulesCore/FilterSources.swift`:

```swift
import Foundation

/// Lista adresów list filtrów dla każdego blokera, wczytana z `filters/sources.json`.
public struct FilterSources: Equatable {
    public static let blockerKeys = ["ads", "trackers", "cookies"]

    public let urlsByBlocker: [String: [URL]]

    public init(urlsByBlocker: [String: [URL]]) {
        self.urlsByBlocker = urlsByBlocker
    }

    public enum LoadError: Error, Equatable, CustomStringConvertible {
        case invalidJSON
        case missingBlocker(String)
        case unknownBlocker(String)
        case emptyBlocker(String)
        case invalidURL(String)

        public var description: String {
            switch self {
            case .invalidJSON: return "sources.json: niepoprawny JSON (oczekiwano {\"ads\": [\"https://...\"], ...})"
            case .missingBlocker(let key): return "sources.json: brak blokera \"\(key)\""
            case .unknownBlocker(let key): return "sources.json: nieznany bloker \"\(key)\" (dozwolone: ads, trackers, cookies)"
            case .emptyBlocker(let key): return "sources.json: bloker \"\(key)\" nie ma żadnej listy"
            case .invalidURL(let value): return "sources.json: niepoprawny adres \"\(value)\" (wymagany https://)"
            }
        }
    }

    public static func parse(_ data: Data) throws -> FilterSources {
        guard let raw = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            throw LoadError.invalidJSON
        }
        for key in raw.keys.sorted() where !blockerKeys.contains(key) {
            throw LoadError.unknownBlocker(key)
        }
        var result: [String: [URL]] = [:]
        for key in blockerKeys {
            guard let strings = raw[key] else { throw LoadError.missingBlocker(key) }
            guard !strings.isEmpty else { throw LoadError.emptyBlocker(key) }
            result[key] = try strings.map { value in
                guard let url = URL(string: value), url.scheme == "https", url.host != nil else {
                    throw LoadError.invalidURL(value)
                }
                return url
            }
        }
        return FilterSources(urlsByBlocker: result)
    }
}
```

`tools/build-rules/Sources/RulesCore/Whitelist.swift`:

```swift
import Foundation

/// Biała lista domen z `filters/whitelist.txt` (jedna na linię, `#` zaczyna komentarz).
public enum Whitelist {
    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case invalidDomain(line: Int, value: String)

        public var description: String {
            switch self {
            case let .invalidDomain(line, value):
                return "whitelist.txt, linia \(line): \"\(value)\" nie jest poprawną domeną"
            }
        }
    }

    /// Zwraca znormalizowane domeny bez duplikatów, w kolejności z pliku.
    /// Akceptuje też wklejone adresy URL (schemat, www., ścieżka i port są usuwane).
    public static func parseDomains(_ text: String) throws -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        for (index, rawLine) in lines.enumerated() {
            let withoutComment = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map(String.init) ?? ""
            let trimmed = withoutComment.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let domain = normalize(trimmed)
            guard isValidDomain(domain) else {
                throw ParseError.invalidDomain(line: index + 1, value: trimmed)
            }
            if seen.insert(domain).inserted { result.append(domain) }
        }
        return result
    }

    /// Reguły wyjątków wyłączające wszystkie blokady na danej domenie i jej subdomenach.
    public static func rules(forDomains domains: [String]) -> [String] {
        domains.map { "@@||\($0)^$document" }
    }

    static func normalize(_ value: String) -> String {
        var domain = value.lowercased()
        for scheme in ["https://", "http://"] where domain.hasPrefix(scheme) {
            domain.removeFirst(scheme.count)
        }
        if let cut = domain.firstIndex(where: { "/?:".contains($0) }) {
            domain = String(domain[..<cut])
        }
        if domain.hasPrefix("www.") { domain.removeFirst(4) }
        while domain.hasSuffix(".") { domain.removeLast() }
        return domain
    }

    static func isValidDomain(_ domain: String) -> Bool {
        domain.range(of: #"^[a-z0-9-]+(\.[a-z0-9-]+)+$"#, options: .regularExpression) != nil
    }
}
```

`tools/build-rules/Sources/RulesCore/RuleMerger.swift`:

```swift
import Foundation

/// Łączy treść list filtrów w jedną tablicę reguł dla konwertera.
public enum RuleMerger {
    /// Pomija puste linie, komentarze (`!`) i nagłówki list (`[Adblock Plus 2.0]`),
    /// zachowując reguły z modyfikatorami AdGuard (`[$path=...]...`).
    /// Duplikaty są usuwane (wygrywa pierwsze wystąpienie), reguły białej listy trafiają na koniec.
    public static func merge(listTexts: [String], whitelistRules: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for text in listTexts {
            for rawLine in text.split(whereSeparator: \.isNewline) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("!") { continue }
                if line.hasPrefix("[") && !line.hasPrefix("[$") { continue }
                if seen.insert(line).inserted { result.append(line) }
            }
        }
        for rule in whitelistRules where seen.insert(rule).inserted {
            result.append(rule)
        }
        return result
    }
}
```

- [ ] **Step 6: Uruchom testy i sprawdź, że przechodzą**

```bash
git add -A && git commit -m "feat: parsowanie sources.json, białej listy i łączenie list" && git push
bash scripts/ci-wait.sh
```

Expected: `CI: PASS`. W logu kroku „Testy build-rules” widać `Executed 13 tests, with 0 failures`.

---

### Task 2: Konwersja do formatu Safari i walidacja JSON

**Files:**
- Create: `tools/build-rules/Sources/RulesCore/BlockerConverter.swift`, `BlockerJSONValidator.swift`
- Test: `tools/build-rules/Tests/RulesCoreTests/BlockerConverterTests.swift`, `BlockerJSONValidatorTests.swift`

**Interfaces:**
- Consumes: `RuleMerger.merge` i `Whitelist.rules(forDomains:)` (Task 1), tylko w testach.
- Produces:
  - `BlockerOutput` z polami `json: String`, `sourceRules: Int`, `safariRules: Int`, `discarded: Int`, `errors: Int`
  - `BlockerConverter.convert(rules: [String], maxJsonSizeBytes: Int = BlockerConverter.defaultMaxJsonSizeBytes) -> BlockerOutput`
  - `BlockerJSONValidator.validate(_ json: String, maxRules: Int = 150_000) throws -> Int` (zwraca liczbę reguł)
  - `BlockerJSONValidator.ValidationError`

- [ ] **Step 1: Napisz testy, które nie przejdą**

`tools/build-rules/Tests/RulesCoreTests/BlockerConverterTests.swift`:

```swift
import XCTest
@testable import RulesCore

final class BlockerConverterTests: XCTestCase {
    /// Typy akcji (`block`, `css-display-none`, `ignore-previous-rules`...) w wynikowym JSON.
    private func actionTypes(_ json: String) throws -> [String] {
        let array = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
        )
        return array.compactMap { ($0["action"] as? [String: Any])?["type"] as? String }
    }

    func testConvertsNetworkRuleToBlock() throws {
        let output = BlockerConverter.convert(rules: ["||ads.example.com^"])
        XCTAssertEqual(output.sourceRules, 1)
        XCTAssertEqual(output.safariRules, 1)
        XCTAssertEqual(try actionTypes(output.json), ["block"])
    }

    func testConvertsCosmeticRuleToCssHiding() throws {
        let output = BlockerConverter.convert(rules: ["example.com##.banner"])
        XCTAssertTrue(try actionTypes(output.json).contains("css-display-none"))
    }

    func testWhitelistRuleBecomesIgnorePreviousRules() throws {
        let rules = RuleMerger.merge(listTexts: ["||ads.example.com^"],
                                     whitelistRules: Whitelist.rules(forDomains: ["good.example"]))
        let types = try actionTypes(BlockerConverter.convert(rules: rules).json)
        XCTAssertTrue(types.contains("block"))
        XCTAssertEqual(types.last, "ignore-previous-rules")
    }

    func testOversizedOutputIsTrimmedToSizeLimit() throws {
        let rules = (0..<2000).map { "||adhost\($0).example^" }
        let output = BlockerConverter.convert(rules: rules, maxJsonSizeBytes: 5_000)
        XCTAssertLessThanOrEqual(output.json.utf8.count, 5_000)
        XCTAssertGreaterThan(output.discarded, 0)
        XCTAssertGreaterThan(try BlockerJSONValidator.validate(output.json), 0)
    }
}
```

`tools/build-rules/Tests/RulesCoreTests/BlockerJSONValidatorTests.swift`:

```swift
import XCTest
@testable import RulesCore

final class BlockerJSONValidatorTests: XCTestCase {
    private let rule = #"{"trigger":{"url-filter":"x"},"action":{"type":"block"}}"#

    func testCountsRules() throws {
        XCTAssertEqual(try BlockerJSONValidator.validate("[\(rule),\(rule)]"), 2)
    }

    func testRejectsEmptyArray() {
        XCTAssertThrowsError(try BlockerJSONValidator.validate("[]")) {
            XCTAssertEqual($0 as? BlockerJSONValidator.ValidationError, .empty)
        }
    }

    func testRejectsNonArray() {
        XCTAssertThrowsError(try BlockerJSONValidator.validate("{}")) {
            XCTAssertEqual($0 as? BlockerJSONValidator.ValidationError, .notJSONArray)
        }
        XCTAssertThrowsError(try BlockerJSONValidator.validate("nie json")) {
            XCTAssertEqual($0 as? BlockerJSONValidator.ValidationError, .notJSONArray)
        }
    }

    func testRejectsTooManyRules() {
        XCTAssertThrowsError(try BlockerJSONValidator.validate("[\(rule),\(rule),\(rule)]", maxRules: 2)) {
            XCTAssertEqual($0 as? BlockerJSONValidator.ValidationError, .tooManyRules(3))
        }
    }
}
```

- [ ] **Step 2: Uruchom testy i sprawdź, że NIE przechodzą**

```bash
git add -A && git commit -m "test: testy konwersji i walidacji JSON" && git push
bash scripts/ci-wait.sh
```

Expected: `CI: FAIL` z `cannot find 'BlockerConverter' in scope`.

- [ ] **Step 3: Implementacja**

`tools/build-rules/Sources/RulesCore/BlockerConverter.swift`:

```swift
import ContentBlockerConverter
import Foundation

/// Wynik konwersji jednego blokera.
public struct BlockerOutput: Equatable {
    public let json: String
    public let sourceRules: Int
    public let safariRules: Int
    public let discarded: Int
    public let errors: Int

    public init(json: String, sourceRules: Int, safariRules: Int, discarded: Int, errors: Int) {
        self.json = json
        self.sourceRules = sourceRules
        self.safariRules = safariRules
        self.discarded = discarded
        self.errors = errors
    }
}

/// Konwersja reguł AdBlock/AdGuard do JSON Safari Content Blockera (SafariConverterLib).
public enum BlockerConverter {
    /// Minimalne iOS aplikacji to 16.4, więc generujemy reguły dla Safari 16.4.
    public static let safariVersion = SafariVersion.safari16_4

    /// iOS odrzuca bloker, gdy JSON jest zbyt duży (SafariConverterLib issue #56, ~11 MB).
    public static let defaultMaxJsonSizeBytes = 10_000_000

    public static func convert(rules: [String], maxJsonSizeBytes: Int = defaultMaxJsonSizeBytes) -> BlockerOutput {
        let result = ContentBlockerConverter().convertArray(
            rules: rules,
            safariVersion: safariVersion,
            advancedBlocking: false,
            maxJsonSizeBytes: maxJsonSizeBytes
        )
        return BlockerOutput(
            json: result.safariRulesJSON,
            sourceRules: result.sourceRulesCount,
            safariRules: result.safariRulesCount,
            discarded: result.discardedSafariRules,
            errors: result.errorsCount
        )
    }
}
```

`tools/build-rules/Sources/RulesCore/BlockerJSONValidator.swift`:

```swift
import Foundation

/// Ostatnia linia obrony przed wysłaniem do Safari niepoprawnego pliku reguł.
public enum BlockerJSONValidator {
    public static let maxRules = 150_000

    public enum ValidationError: Error, Equatable, CustomStringConvertible {
        case notJSONArray
        case empty
        case tooManyRules(Int)

        public var description: String {
            switch self {
            case .notJSONArray: return "blockerList.json nie jest tablicą JSON"
            case .empty: return "blockerList.json jest pusty"
            case .tooManyRules(let count): return "blockerList.json ma \(count) reguł (limit \(BlockerJSONValidator.maxRules))"
            }
        }
    }

    /// Zwraca liczbę reguł w poprawnym pliku.
    @discardableResult
    public static func validate(_ json: String, maxRules: Int = maxRules) throws -> Int {
        guard let array = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [Any] else {
            throw ValidationError.notJSONArray
        }
        guard !array.isEmpty else { throw ValidationError.empty }
        guard array.count <= maxRules else { throw ValidationError.tooManyRules(array.count) }
        return array.count
    }
}
```

- [ ] **Step 4: Uruchom testy i sprawdź, że przechodzą**

```bash
git add -A && git commit -m "feat: konwersja reguł przez SafariConverterLib i walidacja JSON" && git push
bash scripts/ci-wait.sh
```

Expected: `CI: PASS`, `Executed 21 tests, with 0 failures`. Jeśli `testWhitelistRuleBecomesIgnorePreviousRules` zawiedzie, wypisz w teście `output.json` i dopasuj asercję do faktycznej struktury. Wymaganie jest jedno: w wyniku jest akcja `ignore-previous-rules` po regułach blokujących.

---

### Task 3: Pobieranie list, manifest i CLI `build-rules`

**Files:**
- Create: `tools/build-rules/Sources/RulesCore/DownloadValidator.swift`, `Manifest.swift`
- Modify: `tools/build-rules/Sources/BuildRules/main.swift` (pełna zamiana)
- Create: `filters/sources.json`, `filters/whitelist.txt`
- Modify: `.github/workflows/build.yml`
- Test: `tools/build-rules/Tests/RulesCoreTests/DownloadValidatorTests.swift`, `ManifestTests.swift`

**Interfaces:**
- Consumes: wszystko z Task 1 i 2.
- Produces:
  - `DownloadValidator.validate(url: URL, status: Int, body: Data, minimumRuleCount: Int = 100) throws -> String`
  - `Manifest(builtAt: Date, blockers: [Manifest.Entry])`
  - `Manifest.Entry(key:sourceRules:safariRules:discarded:errors:)`
  - `Manifest.encoded() throws -> Data`
  - `Manifest.decode(_ data: Data) throws -> Manifest`
  - CLI `swift run -c release build-rules <repo-root>` zapisuje `Blockers/{Ads,Trackers,Cookies}/blockerList.json` oraz `App/Resources/rules-manifest.json`.

- [ ] **Step 1: Napisz testy, które nie przejdą**

`tools/build-rules/Tests/RulesCoreTests/DownloadValidatorTests.swift`:

```swift
import XCTest
@testable import RulesCore

final class DownloadValidatorTests: XCTestCase {
    private let url = URL(string: "https://lists.example/list.txt")!

    private func list(rules count: Int) -> Data {
        let rules = (0..<count).map { "||ad\($0).example^" }.joined(separator: "\n")
        return Data("[Adblock Plus 2.0]\n! Title: Test\n\(rules)\n".utf8)
    }

    func testAcceptsValidList() throws {
        let text = try DownloadValidator.validate(url: url, status: 200, body: list(rules: 150))
        XCTAssertTrue(text.contains("||ad149.example^"))
    }

    func testRejectsHttpError() {
        XCTAssertThrowsError(try DownloadValidator.validate(url: url, status: 404, body: list(rules: 150))) {
            XCTAssertEqual($0 as? DownloadValidator.ValidationError,
                           .badStatus(url: url.absoluteString, status: 404))
        }
    }

    func testRejectsHtmlPageServedWith200() {
        let html = Data("\u{FEFF}  \n<!DOCTYPE html><html><body>Captcha</body></html>".utf8)
        XCTAssertThrowsError(try DownloadValidator.validate(url: url, status: 200, body: html)) {
            XCTAssertEqual($0 as? DownloadValidator.ValidationError, .looksLikeHTML(url: url.absoluteString))
        }
    }

    func testRejectsTruncatedList() {
        XCTAssertThrowsError(try DownloadValidator.validate(url: url, status: 200, body: list(rules: 5))) {
            XCTAssertEqual($0 as? DownloadValidator.ValidationError,
                           .tooFewRules(url: url.absoluteString, count: 5))
        }
    }

    func testRejectsNonUTF8() {
        XCTAssertThrowsError(try DownloadValidator.validate(url: url, status: 200, body: Data([0xFF, 0xFE, 0x00, 0xD8]))) {
            XCTAssertEqual($0 as? DownloadValidator.ValidationError, .notText(url: url.absoluteString))
        }
    }
}
```

`tools/build-rules/Tests/RulesCoreTests/ManifestTests.swift`:

```swift
import XCTest
@testable import RulesCore

final class ManifestTests: XCTestCase {
    private let manifest = Manifest(
        builtAt: Date(timeIntervalSince1970: 1_792_065_600), // 2026-10-15T12:00:00Z
        blockers: [Manifest.Entry(key: "ads", sourceRules: 90_000, safariRules: 61_000, discarded: 0, errors: 12)]
    )

    func testEncodesContractFieldsWithISODate() throws {
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: manifest.encoded()) as? [String: Any]
        )
        XCTAssertEqual(object["builtAt"] as? String, "2026-10-15T12:00:00Z")
        let first = try XCTUnwrap((object["blockers"] as? [[String: Any]])?.first)
        XCTAssertEqual(first["key"] as? String, "ads")
        XCTAssertEqual(first["sourceRules"] as? Int, 90_000)
        XCTAssertEqual(first["safariRules"] as? Int, 61_000)
        XCTAssertEqual(first["discarded"] as? Int, 0)
        XCTAssertEqual(first["errors"] as? Int, 12)
    }

    func testRoundTrip() throws {
        XCTAssertEqual(try Manifest.decode(manifest.encoded()), manifest)
    }
}
```

- [ ] **Step 2: Uruchom testy i sprawdź, że NIE przechodzą**

```bash
git add -A && git commit -m "test: testy walidacji pobrań i manifestu" && git push
bash scripts/ci-wait.sh
```

Expected: `CI: FAIL` z `cannot find 'DownloadValidator' in scope`.

- [ ] **Step 3: Implementacja RulesCore**

`tools/build-rules/Sources/RulesCore/DownloadValidator.swift`:

```swift
import Foundation

/// Sprawdza, czy pobrany plik jest prawdziwą listą filtrów, a nie stroną błędu lub uciętym plikiem.
public enum DownloadValidator {
    public static let minimumRuleCount = 100

    public enum ValidationError: Error, Equatable, CustomStringConvertible {
        case badStatus(url: String, status: Int)
        case notText(url: String)
        case looksLikeHTML(url: String)
        case tooFewRules(url: String, count: Int)

        public var description: String {
            switch self {
            case let .badStatus(url, status): return "\(url): serwer zwrócił HTTP \(status)"
            case let .notText(url): return "\(url): odpowiedź nie jest tekstem UTF-8"
            case let .looksLikeHTML(url): return "\(url): zamiast listy filtrów przyszła strona HTML"
            case let .tooFewRules(url, count): return "\(url): tylko \(count) reguł, lista wygląda na uciętą"
            }
        }
    }

    /// Zwraca treść listy, jeśli przeszła wszystkie kontrole.
    public static func validate(url: URL, status: Int, body: Data,
                                minimumRuleCount: Int = minimumRuleCount) throws -> String {
        let name = url.absoluteString
        guard status == 200 else { throw ValidationError.badStatus(url: name, status: status) }
        guard let text = String(data: body, encoding: .utf8) else { throw ValidationError.notText(url: name) }
        let start = text.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))
        )
        if start.hasPrefix("<") { throw ValidationError.looksLikeHTML(url: name) }
        let count = RuleMerger.merge(listTexts: [text], whitelistRules: []).count
        guard count >= minimumRuleCount else { throw ValidationError.tooFewRules(url: name, count: count) }
        return text
    }
}
```

`tools/build-rules/Sources/RulesCore/Manifest.swift`:

```swift
import Foundation

/// Informacje o buildzie list dołączane do aplikacji (`App/Resources/rules-manifest.json`).
public struct Manifest: Codable, Equatable {
    public struct Entry: Codable, Equatable {
        public let key: String
        public let sourceRules: Int
        public let safariRules: Int
        public let discarded: Int
        public let errors: Int

        public init(key: String, sourceRules: Int, safariRules: Int, discarded: Int, errors: Int) {
            self.key = key
            self.sourceRules = sourceRules
            self.safariRules = safariRules
            self.discarded = discarded
            self.errors = errors
        }
    }

    public let builtAt: Date
    public let blockers: [Entry]

    public init(builtAt: Date, blockers: [Entry]) {
        self.builtAt = builtAt
        self.blockers = blockers
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> Manifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Manifest.self, from: data)
    }
}
```

- [ ] **Step 4: Implementacja CLI**

`tools/build-rules/Sources/BuildRules/main.swift` (zastąp całą zawartość):

```swift
import Foundation
import RulesCore

/// Folder rozszerzenia w repo dla każdego klucza blokera.
let blockerFolders = ["ads": "Ads", "trackers": "Trackers", "cookies": "Cookies"]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("::error::\(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else { fail("Użycie: build-rules <ścieżka-do-repo>") }
let root = URL(fileURLWithPath: arguments[1], isDirectory: true)

do {
    let sources = try FilterSources.parse(Data(contentsOf: root.appendingPathComponent("filters/sources.json")))
    let whitelistURL = root.appendingPathComponent("filters/whitelist.txt")
    var whitelistText = ""
    if FileManager.default.fileExists(atPath: whitelistURL.path) {
        whitelistText = try String(contentsOf: whitelistURL, encoding: .utf8)
    }
    let whitelistRules = try Whitelist.rules(forDomains: Whitelist.parseDomains(whitelistText))
    print("Biała lista: \(whitelistRules.count) domen")

    var entries: [Manifest.Entry] = []
    for key in FilterSources.blockerKeys {
        var texts: [String] = []
        for url in sources.urlsByBlocker[key] ?? [] {
            print("[\(key)] pobieram \(url.absoluteString)")
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            texts.append(try DownloadValidator.validate(url: url, status: status, body: data))
        }
        let rules = RuleMerger.merge(listTexts: texts, whitelistRules: whitelistRules)
        let output = BlockerConverter.convert(rules: rules)
        let count = try BlockerJSONValidator.validate(output.json)

        guard let folderName = blockerFolders[key] else { fail("Brak folderu dla blokera \(key)") }
        let folder = root.appendingPathComponent("Blockers/\(folderName)")
        try Data(output.json.utf8).write(to: folder.appendingPathComponent("blockerList.json"))
        print("[\(key)] źródłowe: \(output.sourceRules), Safari: \(count), odrzucone: \(output.discarded), błędy konwersji: \(output.errors), JSON: \(output.json.utf8.count / 1024) KB")
        if output.discarded > 0 {
            print("::warning::[\(key)] odrzucono \(output.discarded) reguł z powodu limitów Safari/iOS")
        }
        entries.append(Manifest.Entry(key: key, sourceRules: output.sourceRules, safariRules: count,
                                      discarded: output.discarded, errors: output.errors))
    }

    let resources = root.appendingPathComponent("App/Resources")
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    try Manifest(builtAt: Date(), blockers: entries).encoded()
        .write(to: resources.appendingPathComponent("rules-manifest.json"))
    print("Gotowe: zapisano reguły 3 blokerów i rules-manifest.json")
} catch {
    fail("\(error)")
}
```

Katalogi `Blockers/Ads`, `Blockers/Trackers`, `Blockers/Cookies` muszą istnieć. Utwórz je z plikiem `.gitkeep`, który w Task 4 zostanie zastąpiony prawdziwymi plikami:

```bash
mkdir -p Blockers/Ads Blockers/Trackers Blockers/Cookies && touch Blockers/Ads/.gitkeep Blockers/Trackers/.gitkeep Blockers/Cookies/.gitkeep
```

- [ ] **Step 5: Konfiguracja list**

`filters/sources.json` (adresy sprawdzone 2026-10-15, wszystkie zwracały HTTP 200):

```json
{
  "ads": [
    "https://easylist.to/easylist/easylist.txt",
    "https://raw.githubusercontent.com/MajkiIT/polish-ads-filter/master/polish-adblock-filters/adblock.txt"
  ],
  "trackers": [
    "https://easylist.to/easylist/easyprivacy.txt"
  ],
  "cookies": [
    "https://secure.fanboy.co.nz/fanboy-cookiemonster.txt",
    "https://raw.githubusercontent.com/MajkiIT/polish-ads-filter/master/cookies_filters/adblock_cookies.txt"
  ]
}
```

`filters/whitelist.txt`:

```text
# Biała lista: strony, na których AdBlocker nic nie blokuje.
# Jedna domena na linię. Można wkleić cały adres (https://www.example.com/strona),
# zostanie zamieniony na domenę i obejmie też jej subdomeny.
# Po zmianie: zatwierdź plik w gicie i wypchnij — GitHub zbuduje nową wersję.
```

- [ ] **Step 6: Krok generowania reguł w CI**

`.github/workflows/build.yml` (pełna zawartość):

```yaml
name: build

on:
  push:
    branches: ["**"]
  workflow_dispatch:

jobs:
  build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable

      - uses: actions/cache@v4
        with:
          path: tools/build-rules/.build
          key: spm-${{ runner.os }}-${{ hashFiles('tools/build-rules/Package.swift') }}

      - name: Testy build-rules
        working-directory: tools/build-rules
        run: swift test

      - name: Generowanie reguł
        working-directory: tools/build-rules
        run: swift run -c release build-rules "$GITHUB_WORKSPACE"

      - name: Podgląd manifestu
        run: cat App/Resources/rules-manifest.json
```

- [ ] **Step 7: Uruchom i sprawdź**

```bash
git add -A && git commit -m "feat: CLI build-rules pobiera listy i zapisuje reguły oraz manifest" && git push
bash scripts/ci-wait.sh
gh run view "$(gh run list --branch v1 --limit 1 --json databaseId -q '.[0].databaseId')" --log | grep -E "\[(ads|trackers|cookies)\] źródłowe|safariRules|warning"
```

Expected:
- `CI: PASS` i `Executed 28 tests, with 0 failures`.
- 3 linie `[ads] źródłowe: …, Safari: N…`, każde N > 1000.
- Manifest z 3 wpisami.
- Ewentualne `::warning::` o odrzuconych regułach są dopuszczalne. Zapisz liczby, trafią do README.

---

### Task 4: Aplikacja iOS i 3 rozszerzenia Content Blocker

**Files:**
- Create: `project.yml`
- Create: `App/AdBlockerApp.swift`, `App/BlockerCatalog.swift`, `App/RulesManifest.swift`, `App/BlockerStatusModel.swift`, `App/ContentView.swift`
- Create: `Blockers/Shared/ContentBlockerRequestHandler.swift`
- Delete: `Blockers/*/.gitkeep`
- Create: `scripts/ci-test-app.sh`
- Modify: `.github/workflows/build.yml`
- Test: `AppTests/BlockerCatalogTests.swift`, `AppTests/RulesManifestTests.swift`

**Interfaces:**
- Consumes:
  - pliki z Task 3: `Blockers/{Ads,Trackers,Cookies}/blockerList.json`, `App/Resources/rules-manifest.json`;
  - kontrakt manifestu z Global Constraints.
- Produces:
  - targety Xcode `AdBlocker` (app), `AdsBlocker`, `TrackersBlocker`, `CookiesBlocker` (app-extension), `AdBlockerTests`;
  - schemat `AdBlocker`;
  - `BlockerCatalog.all: [BlockerInfo]`, `BlockerCatalog.identifier(appBundleID:key:) -> String`;
  - `RulesManifest.load(from: Data?) -> RulesManifest?`, `RulesManifest.ruleCountText(for:) -> String`, `RulesManifest.builtAtText(locale:timeZone:) -> String`.

- [ ] **Step 1: Projekt XcodeGen**

`project.yml`:

```yaml
name: AdBlocker
options:
  bundleIdPrefix: pl.local
  deploymentTarget:
    iOS: "16.4"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "5.0"
    MARKETING_VERSION: "1.0"
    CURRENT_PROJECT_VERSION: "1"
    TARGETED_DEVICE_FAMILY: "1"
targets:
  AdBlocker:
    type: application
    platform: iOS
    sources:
      - App
    info:
      path: Generated/AdBlocker-Info.plist
      properties:
        CFBundleDisplayName: AdBlocker
        UILaunchScreen: {}
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: pl.local.adblocker
    dependencies:
      - target: AdsBlocker
      - target: TrackersBlocker
      - target: CookiesBlocker
    scheme:
      testTargets:
        - AdBlockerTests
  AdsBlocker:
    type: app-extension
    platform: iOS
    sources:
      - Blockers/Ads
      - Blockers/Shared
    info:
      path: Generated/AdsBlocker-Info.plist
      properties:
        CFBundleDisplayName: Reklamy
        NSExtension:
          NSExtensionPointIdentifier: com.apple.Safari.content-blocker
          NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).ContentBlockerRequestHandler
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: pl.local.adblocker.ads
  TrackersBlocker:
    type: app-extension
    platform: iOS
    sources:
      - Blockers/Trackers
      - Blockers/Shared
    info:
      path: Generated/TrackersBlocker-Info.plist
      properties:
        CFBundleDisplayName: Trackery
        NSExtension:
          NSExtensionPointIdentifier: com.apple.Safari.content-blocker
          NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).ContentBlockerRequestHandler
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: pl.local.adblocker.trackers
  CookiesBlocker:
    type: app-extension
    platform: iOS
    sources:
      - Blockers/Cookies
      - Blockers/Shared
    info:
      path: Generated/CookiesBlocker-Info.plist
      properties:
        CFBundleDisplayName: Cookies/RODO
        NSExtension:
          NSExtensionPointIdentifier: com.apple.Safari.content-blocker
          NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).ContentBlockerRequestHandler
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: pl.local.adblocker.cookies
  AdBlockerTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - AppTests
    dependencies:
      - target: AdBlocker
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
```

`scripts/ci-test-app.sh`:

```bash
#!/usr/bin/env bash
# Uruchamia testy aplikacji na pierwszym dostępnym symulatorze iPhone'a.
set -euo pipefail
SIM_ID="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime, items in sorted(devices.items(), reverse=True):
    if "iOS" in runtime:
        for d in items:
            if d["name"].startswith("iPhone"):
                print(d["udid"]); sys.exit(0)
sys.exit("Brak symulatora iPhone")
')"
echo "Symulator: $SIM_ID"
xcodebuild test \
  -project AdBlocker.xcodeproj \
  -scheme AdBlocker \
  -destination "id=$SIM_ID" \
  CODE_SIGNING_ALLOWED=NO
```

Dopisz w `.github/workflows/build.yml` po kroku „Podgląd manifestu” (pełny plik):

```yaml
name: build

on:
  push:
    branches: ["**"]
  workflow_dispatch:

jobs:
  build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable

      - uses: actions/cache@v4
        with:
          path: tools/build-rules/.build
          key: spm-${{ runner.os }}-${{ hashFiles('tools/build-rules/Package.swift') }}

      - name: Testy build-rules
        working-directory: tools/build-rules
        run: swift test

      - name: Generowanie reguł
        working-directory: tools/build-rules
        run: swift run -c release build-rules "$GITHUB_WORKSPACE"

      - name: Podgląd manifestu
        run: cat App/Resources/rules-manifest.json

      - name: Generowanie projektu Xcode
        run: |
          brew install xcodegen
          xcodegen generate

      - name: Testy aplikacji (symulator)
        run: bash scripts/ci-test-app.sh
```

- [ ] **Step 2: Napisz testy, które nie przejdą**

`AppTests/BlockerCatalogTests.swift`:

```swift
import XCTest
@testable import AdBlocker

final class BlockerCatalogTests: XCTestCase {
    func testCatalogListsThreeBlockersInOrder() {
        XCTAssertEqual(BlockerCatalog.all.map(\.key), ["ads", "trackers", "cookies"])
        XCTAssertEqual(BlockerCatalog.all.map(\.title), ["Reklamy", "Trackery", "Cookies/RODO"])
    }

    func testIdentifierFollowsActualAppBundleID() {
        XCTAssertEqual(BlockerCatalog.identifier(appBundleID: "pl.local.adblocker", key: "ads"),
                       "pl.local.adblocker.ads")
        // Sideloadly może zmienić prefiks: identyfikator rozszerzenia musi podążać za aplikacją.
        XCTAssertEqual(BlockerCatalog.identifier(appBundleID: "com.ABCDE12345.pl.local.adblocker", key: "cookies"),
                       "com.ABCDE12345.pl.local.adblocker.cookies")
    }
}
```

`AppTests/RulesManifestTests.swift`:

```swift
import XCTest
@testable import AdBlocker

final class RulesManifestTests: XCTestCase {
    private let sample = Data("""
    {"builtAt":"2026-10-15T12:00:00Z","blockers":[
      {"key":"ads","sourceRules":90000,"safariRules":61000,"discarded":0,"errors":12},
      {"key":"cookies","sourceRules":30000,"safariRules":150000,"discarded":2500,"errors":0}
    ]}
    """.utf8)

    func testLoadsValidManifest() throws {
        let manifest = try XCTUnwrap(RulesManifest.load(from: sample))
        XCTAssertEqual(manifest.blockers.map(\.key), ["ads", "cookies"])
        XCTAssertEqual(manifest.builtAt, Date(timeIntervalSince1970: 1_792_065_600))
    }

    func testMissingManifestGivesNil() {
        XCTAssertNil(RulesManifest.load(from: nil))
    }

    func testCorruptManifestGivesNil() {
        XCTAssertNil(RulesManifest.load(from: Data("nie json".utf8)))
    }

    func testRuleCountTexts() throws {
        let manifest = try XCTUnwrap(RulesManifest.load(from: sample))
        XCTAssertEqual(manifest.ruleCountText(for: "ads"), "61000 reguł")
        XCTAssertEqual(manifest.ruleCountText(for: "cookies"), "150000 reguł (odrzucono 2500)")
        XCTAssertEqual(manifest.ruleCountText(for: "trackers"), "Brak danych o regułach")
    }

    func testBuiltAtText() throws {
        let manifest = try XCTUnwrap(RulesManifest.load(from: sample))
        let text = manifest.builtAtText(locale: Locale(identifier: "pl_PL"),
                                        timeZone: TimeZone(identifier: "Europe/Warsaw")!)
        XCTAssertTrue(text.hasPrefix("Listy zbudowane: "), text)
        XCTAssertTrue(text.contains("2026"), text)
        XCTAssertTrue(text.contains("14:00"), text)
    }
}
```

Dodaj minimalne pliki aplikacji, żeby projekt się wygenerował. Bez nich testy nie skompilują się z powodu braku typów, a to właśnie jest oczekiwany RED:

`App/AdBlockerApp.swift`:

```swift
import SwiftUI

@main
struct AdBlockerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

`App/ContentView.swift` (tymczasowo):

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("AdBlocker")
    }
}
```

`Blockers/Shared/ContentBlockerRequestHandler.swift`:

```swift
import Foundation

/// Przekazuje Safari plik reguł wbudowany w rozszerzenie (wspólny dla 3 blokerów).
final class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        guard let url = Bundle.main.url(forResource: "blockerList", withExtension: "json"),
              let attachment = NSItemProvider(contentsOf: url) else {
            context.cancelRequest(withError: NSError(
                domain: "pl.local.adblocker", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Brak pliku blockerList.json w rozszerzeniu"]
            ))
            return
        }
        let item = NSExtensionItem()
        item.attachments = [attachment]
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
```

```bash
git rm -q Blockers/Ads/.gitkeep Blockers/Trackers/.gitkeep Blockers/Cookies/.gitkeep
```

- [ ] **Step 3: Uruchom testy i sprawdź, że NIE przechodzą**

```bash
git add -A && git commit -m "test: projekt XcodeGen i testy logiki aplikacji" && git push
bash scripts/ci-wait.sh
```

Expected: `CI: FAIL` w kroku „Testy aplikacji” z `cannot find 'BlockerCatalog' in scope`. Kroki XcodeGen i build-rules przechodzą.

- [ ] **Step 4: Implementacja logiki aplikacji**

`App/BlockerCatalog.swift`:

```swift
import Foundation

struct BlockerInfo: Identifiable, Equatable {
    let key: String
    let title: String
    var id: String { key }
}

enum BlockerCatalog {
    static let all = [
        BlockerInfo(key: "ads", title: "Reklamy"),
        BlockerInfo(key: "trackers", title: "Trackery"),
        BlockerInfo(key: "cookies", title: "Cookies/RODO"),
    ]

    /// Identyfikator rozszerzenia wyliczany z faktycznego bundle ID aplikacji,
    /// bo Sideloadly może zmienić jego prefiks przy podpisywaniu.
    static func identifier(appBundleID: String, key: String) -> String {
        "\(appBundleID).\(key)"
    }
}
```

`App/RulesManifest.swift`:

```swift
import Foundation

/// Kopia kontraktu `rules-manifest.json` generowanego przez tools/build-rules (Manifest.swift).
struct RulesManifest: Decodable, Equatable {
    struct Entry: Decodable, Equatable {
        let key: String
        let sourceRules: Int
        let safariRules: Int
        let discarded: Int
        let errors: Int
    }

    let builtAt: Date
    let blockers: [Entry]

    /// Zwraca nil, gdy pliku brak lub jest uszkodzony — aplikacja pokazuje wtedy „Brak danych”.
    static func load(from data: Data?) -> RulesManifest? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RulesManifest.self, from: data)
    }

    func ruleCountText(for key: String) -> String {
        guard let entry = blockers.first(where: { $0.key == key }) else { return "Brak danych o regułach" }
        let base = "\(entry.safariRules) reguł"
        return entry.discarded > 0 ? "\(base) (odrzucono \(entry.discarded))" : base
    }

    func builtAtText(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return "Listy zbudowane: \(formatter.string(from: builtAt))"
    }
}
```

`App/BlockerStatusModel.swift`:

```swift
import SafariServices
import SwiftUI

enum BlockerState: Equatable {
    case unknown, enabled, disabled
}

@MainActor
final class BlockerStatusModel: ObservableObject {
    @Published private(set) var states: [String: BlockerState] = [:]
    let manifest: RulesManifest?
    private let appBundleID: String

    init(bundle: Bundle = .main) {
        appBundleID = bundle.bundleIdentifier ?? ""
        let url = bundle.url(forResource: "rules-manifest", withExtension: "json")
        manifest = RulesManifest.load(from: url.flatMap { try? Data(contentsOf: $0) })
    }

    func ruleCountText(for key: String) -> String {
        manifest?.ruleCountText(for: key) ?? "Brak danych o regułach"
    }

    var builtAtText: String {
        manifest?.builtAtText() ?? "Brak informacji o dacie zbudowania list"
    }

    func refresh() async {
        for blocker in BlockerCatalog.all {
            let id = BlockerCatalog.identifier(appBundleID: appBundleID, key: blocker.key)
            states[blocker.key] = await fetchState(identifier: id)
        }
    }

    private func fetchState(identifier: String) async -> BlockerState {
        await withCheckedContinuation { continuation in
            SFContentBlockerManager.getStateOfContentBlocker(withIdentifier: identifier) { state, error in
                if error != nil {
                    continuation.resume(returning: .unknown)
                } else {
                    continuation.resume(returning: (state?.isEnabled ?? false) ? .enabled : .disabled)
                }
            }
        }
    }
}
```

`App/ContentView.swift` (pełna zamiana):

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var model = BlockerStatusModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section("Blokery Safari") {
                    ForEach(BlockerCatalog.all) { blocker in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(blocker.title).font(.headline)
                                Text(model.ruleCountText(for: blocker.key))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusBadge(state: model.states[blocker.key] ?? .unknown)
                        }
                    }
                }
                Section("Listy filtrów") {
                    Text(model.builtAtText)
                }
                Section("Jak włączyć") {
                    Text("1. Otwórz Ustawienia → Aplikacje → Safari → Rozszerzenia (na iOS 17 i starszym: Ustawienia → Safari → Rozszerzenia).\n2. Włącz „Reklamy”, „Trackery” i „Cookies/RODO”.\n3. Wróć tutaj — status odświeży się sam.")
                    Button("Otwórz Ustawienia") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
            .navigationTitle("AdBlocker")
        }
        .task { await model.refresh() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await model.refresh() }
            }
        }
    }
}

struct StatusBadge: View {
    let state: BlockerState

    var body: some View {
        switch state {
        case .enabled:
            Label("Włączony", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .disabled:
            Label("Wyłączony", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        case .unknown:
            Label("Nieznany", systemImage: "questionmark.circle").foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 5: Uruchom testy i sprawdź, że przechodzą**

```bash
git add -A && git commit -m "feat: aplikacja ze statusem blokerów i 3 rozszerzenia Content Blocker" && git push
bash scripts/ci-wait.sh
```

Expected: `CI: PASS`, a w logu kroku „Testy aplikacji” `** TEST SUCCEEDED **` (7 testów). Jeśli XcodeGen odrzuci którąś właściwość `info`, popraw `project.yml` na podstawie komunikatu i powtórz. Nie usuwaj wymaganych kluczy `NSExtension`.

---

### Task 5: Budowanie `.ipa`, weryfikacja i publikacja Release

**Files:**
- Create: `scripts/package-ipa.sh`, `scripts/verify-ipa.sh`
- Test: `scripts/test-verify-ipa.sh`
- Modify: `.github/workflows/build.yml` (wersja końcowa)

**Interfaces:**
- Consumes: schemat `AdBlocker` i targety z Task 4; `App/Resources/rules-manifest.json` z Task 3.
- Produces:
  - `bash scripts/package-ipa.sh <ścieżka .app> <ścieżka .ipa>`
  - `bash scripts/verify-ipa.sh <ipa>` (kod 0 = OK)
  - artefakt `AdBlocker-ipa`
  - Release `build-YYYYMMDD-HHMM` z plikiem `AdBlocker.ipa` (tylko `main`)

- [ ] **Step 1: Napisz test, który nie przejdzie**

`scripts/test-verify-ipa.sh`:

```bash
#!/usr/bin/env bash
# Sprawdza, że verify-ipa.sh akceptuje poprawną paczkę i odrzuca niekompletne.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"

# make_ipa <nazwa> <liczba reguł w każdym blokerze> [pomiń bloker] [pomiń manifest]
make_ipa() {
  local name="$1" count="$2" skip="${3:-}" no_manifest="${4:-}"
  local app="$WORK/$name/Payload/AdBlocker.app"
  mkdir -p "$app"
  [ -z "$no_manifest" ] && echo '{"builtAt":"2026-10-15T12:00:00Z","blockers":[]}' > "$app/rules-manifest.json"
  for ext in AdsBlocker TrackersBlocker CookiesBlocker; do
    [ "$ext" = "$skip" ] && continue
    mkdir -p "$app/PlugIns/$ext.appex"
    python3 -c 'import json,sys; print(json.dumps([{"trigger":{"url-filter":"x"},"action":{"type":"block"}}]*int(sys.argv[1])))' \
      "$count" > "$app/PlugIns/$ext.appex/blockerList.json"
  done
  (cd "$WORK/$name" && zip -qr "$WORK/$name.ipa" Payload)
  echo "$WORK/$name.ipa"
}

expect_fail() {
  if bash "$DIR/verify-ipa.sh" "$1" > /dev/null 2>&1; then
    echo "BŁĄD: paczka powinna zostać odrzucona: $2"
    exit 1
  fi
}

bash "$DIR/verify-ipa.sh" "$(make_ipa ok 1000)"
expect_fail "$(make_ipa missing-ext 1000 CookiesBlocker)" "brak blokera Cookies"
expect_fail "$(make_ipa few-rules 5)" "za mało reguł"
expect_fail "$(make_ipa no-manifest 1000 '' yes)" "brak manifestu"
echo "test-verify-ipa: OK"
```

Dodaj krok do workflow (tymczasowo na końcu pliku, przed pełną wersją z Step 4):

```yaml
      - name: Test skryptu weryfikacji .ipa
        run: bash scripts/test-verify-ipa.sh
```

- [ ] **Step 2: Uruchom test i sprawdź, że NIE przechodzi**

```bash
git add -A && git commit -m "test: test skryptu weryfikacji ipa" && git push
bash scripts/ci-wait.sh
```

Expected: `CI: FAIL` w kroku „Test skryptu weryfikacji .ipa” z `verify-ipa.sh: No such file or directory`.

- [ ] **Step 3: Implementacja skryptów**

`scripts/verify-ipa.sh`:

```bash
#!/usr/bin/env bash
# Sprawdza, że .ipa zawiera aplikację, manifest i 3 blokery z prawdziwymi regułami.
set -euo pipefail
IPA="$1"
MIN_RULES=1000
WORK="$(mktemp -d)"
unzip -q "$IPA" -d "$WORK"
APP="$WORK/Payload/AdBlocker.app"
[ -d "$APP" ] || { echo "::error::Brak Payload/AdBlocker.app w $IPA"; exit 1; }
[ -f "$APP/rules-manifest.json" ] || { echo "::error::Brak rules-manifest.json w aplikacji"; exit 1; }
for ext in AdsBlocker TrackersBlocker CookiesBlocker; do
  JSON="$APP/PlugIns/$ext.appex/blockerList.json"
  [ -f "$JSON" ] || { echo "::error::Brak $ext.appex/blockerList.json"; exit 1; }
  COUNT="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$JSON")"
  [ "$COUNT" -ge "$MIN_RULES" ] || { echo "::error::$ext ma tylko $COUNT reguł (minimum $MIN_RULES)"; exit 1; }
  echo "$ext: $COUNT reguł"
done
echo "verify-ipa: OK"
```

`scripts/package-ipa.sh`:

```bash
#!/usr/bin/env bash
# Pakuje zbudowaną aplikację .app do niepodpisanego .ipa (Payload/AdBlocker.app).
set -euo pipefail
APP="$1"
OUT="$2"
[ -d "$APP" ] || { echo "::error::Brak $APP"; exit 1; }
mkdir -p "$(dirname "$OUT")"
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
WORK="$(mktemp -d)"
mkdir -p "$WORK/Payload"
cp -R "$APP" "$WORK/Payload/"
rm -f "$OUT_ABS"
(cd "$WORK" && zip -qry "$OUT_ABS" Payload)
echo "Utworzono $OUT_ABS ($(du -h "$OUT_ABS" | cut -f1))"
```

- [ ] **Step 4: Workflow w wersji końcowej**

`.github/workflows/build.yml` (pełna zawartość):

```yaml
name: build

on:
  push:
    branches: ["**"]
  schedule:
    - cron: "0 4 * * 1" # co poniedziałek 04:00 UTC — świeże listy filtrów
  workflow_dispatch:

permissions:
  contents: write

jobs:
  build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable

      - uses: actions/cache@v4
        with:
          path: tools/build-rules/.build
          key: spm-${{ runner.os }}-${{ hashFiles('tools/build-rules/Package.swift') }}

      - name: Testy build-rules
        working-directory: tools/build-rules
        run: swift test

      - name: Generowanie reguł
        working-directory: tools/build-rules
        run: swift run -c release build-rules "$GITHUB_WORKSPACE"

      - name: Podgląd manifestu
        run: cat App/Resources/rules-manifest.json

      - name: Generowanie projektu Xcode
        run: |
          brew install xcodegen
          xcodegen generate

      - name: Testy aplikacji (symulator)
        run: bash scripts/ci-test-app.sh

      - name: Build aplikacji (bez podpisu)
        run: |
          xcodebuild build \
            -project AdBlocker.xcodeproj \
            -scheme AdBlocker \
            -configuration Release \
            -sdk iphoneos \
            -derivedDataPath build/dd \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

      - name: Pakowanie .ipa
        run: bash scripts/package-ipa.sh build/dd/Build/Products/Release-iphoneos/AdBlocker.app build/AdBlocker.ipa

      - name: Test skryptu weryfikacji .ipa
        run: bash scripts/test-verify-ipa.sh

      - name: Weryfikacja .ipa
        run: bash scripts/verify-ipa.sh build/AdBlocker.ipa

      - uses: actions/upload-artifact@v4
        with:
          name: AdBlocker-ipa
          path: build/AdBlocker.ipa

      - name: Publikacja Release
        if: github.ref == 'refs/heads/main'
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          TAG="build-$(date -u +%Y%m%d-%H%M)"
          {
            echo "Automatyczny build AdBlocker. Pobierz AdBlocker.ipa i zainstaluj przez Sideloadly (instrukcja w README)."
            echo
            echo '```json'
            cat App/Resources/rules-manifest.json
            echo '```'
          } > build/release-notes.md
          gh release create "$TAG" build/AdBlocker.ipa --title "AdBlocker $TAG" --notes-file build/release-notes.md
```

- [ ] **Step 5: Uruchom i sprawdź, że przechodzi**

```bash
git add -A && git commit -m "feat: pakowanie, weryfikacja i publikacja AdBlocker.ipa" && git push
bash scripts/ci-wait.sh
gh run view "$(gh run list --branch v1 --limit 1 --json databaseId -q '.[0].databaseId')" --log | grep -E "reguł$|verify-ipa: OK|test-verify-ipa: OK|Utworzono"
```

Expected:
- `CI: PASS`;
- `test-verify-ipa: OK`, `verify-ipa: OK` oraz 3 linie `…Blocker: N reguł`;
- na gałęzi `v1` brak kroku Release (pominięty);
- artefakt `AdBlocker-ipa` widoczny w `gh run view`.

---

### Task 6: README, pierwszy Release i instalacja na iPhonie

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: Release z Task 5, checklista ze spec.
- Produces: instrukcja dla użytkownika; zweryfikowana instalacja na iPhonie 14 Pro.

- [ ] **Step 1: README**

`README.md`:

````markdown
# AdBlocker — blokowanie reklam w Safari na iPhonie

Własna aplikacja z trzema blokerami Safari: **Reklamy** (EasyList + Polskie Filtry), **Trackery** (EasyPrivacy) i **Cookies/RODO** (EasyList Cookie + Polskie Filtry RODO).
GitHub buduje ją automatycznie co tydzień ze świeżymi listami. Ty instalujesz ją z Windowsa przez Sideloadly darmowym Apple ID.

> Działa tylko w Safari (oraz w przeglądarkach wbudowanych w aplikacje, które używają Safari). Chrome na iOS nie obsługuje blokerów.

## Pierwsza instalacja (Windows)

1. Zainstaluj **iTunes** i **iCloud** w wersjach ze strony Apple (nie z Microsoft Store). Sideloadly ich wymaga.
2. Zainstaluj **Sideloadly** ze strony sideloadly.io.
3. Pobierz najnowszy plik `AdBlocker.ipa` z zakładki **Releases** tego repozytorium.
4. Podłącz iPhone'a kablem, odblokuj go i potwierdź „Ufaj temu komputerowi”.
5. W Sideloadly:
   - przeciągnij `AdBlocker.ipa`;
   - wpisz swój Apple ID;
   - kliknij **Start**.
   
   Hasło wpisujesz sam, w oknie Sideloadly.
6. Na iPhonie:
   1. **Ustawienia → Prywatność i ochrona → Tryb dewelopera** → włącz i uruchom telefon ponownie. Opcja pojawia się dopiero po pierwszej próbie instalacji.
   2. **Ustawienia → Ogólne → VPN i urządzenia** → Twój Apple ID → **Ufaj**.
   3. **Ustawienia → Aplikacje → Safari → Rozszerzenia** (iOS 17 i starszy: Ustawienia → Safari → Rozszerzenia) → włącz **Reklamy**, **Trackery** i **Cookies/RODO**.
7. Otwórz aplikację AdBlocker. Wszystkie 3 blokery powinny mieć status **Włączony**.

## Odnawianie co 7 dni

Darmowe Apple ID podpisuje aplikację na 7 dni. Masz dwie możliwości:
- **Automatycznie:** włącz w Sideloadly automatyczne odświeżanie i trzymaj Sideloadly uruchomione na komputerze w tej samej sieci Wi-Fi co iPhone. Wymaga jednorazowego włączenia synchronizacji przez Wi-Fi w iTunes.
- **Ręcznie:** co tydzień pobierz najnowszy `AdBlocker.ipa` z Releases i zainstaluj go jak wyżej. Dostajesz przy tym świeże listy filtrów.

## Biała lista

Jeśli jakaś strona działa źle:
1. Dopisz jej domenę do `filters/whitelist.txt` (np. `example.com`).
2. Zatwierdź i wypchnij zmianę na `main`.
3. Po kilku minutach w Releases pojawi się nowa wersja. Zainstaluj ją.

## Zmiana list filtrów

Adresy list są w `filters/sources.json` (klucze `ads`, `trackers`, `cookies`, tylko adresy `https://`).

## Checklista testu ręcznego (po każdej instalacji)

- [ ] Aplikacja pokazuje 3 blokery jako **Włączony**, datę zbudowania list i liczbę reguł.
- [ ] Strona testowa adblocka (np. d3ward.github.io/toolz/adblock) pokazuje zablokowane domeny reklamowe.
- [ ] wp.pl i onet.pl w Safari nie pokazują banerów reklamowych.
- [ ] Na 3 polskich stronach z banerem cookies baner się nie pojawia.
- [ ] Strona dopisana do białej listy działa i ma reklamy (test działania wyjątków).
- [ ] Po wyłączeniu blokera w Ustawieniach aplikacja pokazuje **Wyłączony**.

## Jak to działa (dla ciekawych)

- `tools/build-rules`: pobiera listy, łączy je z białą listą i konwertuje przez [SafariConverterLib](https://github.com/AdguardTeam/SafariConverterLib) do formatu Safari (maks. 150 000 reguł i 10 MB na bloker).
- `project.yml`: opis projektu dla XcodeGen (aplikacja + 3 rozszerzenia Content Blocker).
- `.github/workflows/build.yml`: testy → generowanie reguł → build bez podpisu → `AdBlocker.ipa` → Release.
````

- [ ] **Step 2: Merge do `main` i pierwszy Release (z użytkownikiem)**

Zapytaj w czacie: „Wszystko przeszło na gałęzi v1. Czy mogę zmergować v1 do main? To opublikuje pierwszy Release w publicznym repo.” Dopiero po „tak”:

```bash
git add README.md && git commit -m "docs: instrukcja instalacji i checklista testów"
git push
bash scripts/ci-wait.sh
git checkout main && git merge --ff-only v1 && git push
bash scripts/ci-wait.sh
gh release list --limit 1
```

Expected: oba runy `CI: PASS`, a `gh release list` pokazuje `AdBlocker build-YYYYMMDD-HHMM`.

- [ ] **Step 3: Instalacja i checklista na iPhonie (użytkownik)**

Przeprowadź użytkownika przez sekcję „Pierwsza instalacja” README krok po kroku, jeden krok na wiadomość. Potem przejdźcie razem checklistę. Jeśli status blokera to „Nieznany” mimo włączenia w Ustawieniach, Sideloadly zmienił bundle ID inaczej, niż zakłada `BlockerCatalog.identifier`. Poproś wtedy o zrzut ekranu z Sideloadly z bundle ID i dopasuj wyliczanie. Wyniki checklisty zapisz w opisie Release albo w commicie.
