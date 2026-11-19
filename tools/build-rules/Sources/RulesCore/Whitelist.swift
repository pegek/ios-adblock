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
