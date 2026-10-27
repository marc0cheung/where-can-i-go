import Foundation

/// Web search engine used to look up a country from the country detail card.
enum SearchEngine: String, CaseIterable, Identifiable {
    case google
    case bing
    case duckDuckGo

    static let storageKey = "searchEngine"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .google: "Google"
        case .bing: "Bing"
        case .duckDuckGo: "DuckDuckGo"
        }
    }

    func searchURL(for query: String) -> URL? {
        var components: URLComponents
        switch self {
        case .google: components = URLComponents(string: "https://www.google.com/search")!
        case .bing: components = URLComponents(string: "https://www.bing.com/search")!
        case .duckDuckGo: components = URLComponents(string: "https://duckduckgo.com/")!
        }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }
}
