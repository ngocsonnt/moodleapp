import Foundation

struct SavedFolder: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var bookmark: Data

    enum ResolveError: Error { case staleBookmark, accessDenied }

    /// Resolves the bookmark to a URL. Caller is responsible for
    /// calling `startAccessingSecurityScopedResource()` before reading
    /// and the matching stop when done.
    func resolveURL() throws -> URL {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        return url
    }
}
