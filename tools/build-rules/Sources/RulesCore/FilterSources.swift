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
