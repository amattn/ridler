import Foundation

class RecentProjectsManager: ObservableObject {
    static let shared = RecentProjectsManager()

    private let key = "recentProjectURLs"
    private let maxRecents = 10

    @Published var recentURLs: [URL] = []

    init() {
        loadRecents()
    }

    func addRecent(_ url: URL) {
        var urls = recentURLs
        let standardized = url.standardizedFileURL
        urls.removeAll { $0.standardizedFileURL == standardized }
        urls.insert(standardized, at: 0)
        if urls.count > maxRecents {
            urls = Array(urls.prefix(maxRecents))
        }
        recentURLs = urls
        saveRecents()
    }

    func clearRecents() {
        recentURLs = []
        saveRecents()
    }

    private func loadRecents() {
        guard let bookmarks = UserDefaults.standard.array(forKey: key) as? [Data] else {
            return
        }
        var urls: [URL] = []
        for bookmark in bookmarks {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                urls.append(url.standardizedFileURL)
            }
        }
        recentURLs = urls
    }

    private func saveRecents() {
        let bookmarks = recentURLs.compactMap { url -> Data? in
            try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        UserDefaults.standard.set(bookmarks, forKey: key)
    }
}
