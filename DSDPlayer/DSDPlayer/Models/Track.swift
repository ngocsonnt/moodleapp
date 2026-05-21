import Foundation

struct Track: Identifiable, Hashable {
    let id = UUID()
    let url: URL

    var title: String { url.deletingPathExtension().lastPathComponent }
    var ext: String { url.pathExtension.lowercased() }
    var formatLabel: String { ext.uppercased() }

    var isDSD: Bool { ext == "dsf" || ext == "dff" }

    static let supportedExtensions: Set<String> = [
        "dsf", "dff",
        "flac", "wav", "aif", "aiff", "m4a", "mp3", "caf"
    ]
}
