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
