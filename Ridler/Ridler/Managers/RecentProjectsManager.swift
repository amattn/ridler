import Foundation
import os

class RecentProjectsManager: ObservableObject {
    private static let logger = Logger(subsystem: "com.amattn.Ridler", category: "RecentProjects")
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
        Self.logger.debug("Added recent project: \(standardized.path)")
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
