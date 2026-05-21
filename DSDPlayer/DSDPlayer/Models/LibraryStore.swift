import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var folders: [SavedFolder] = []

    private let defaultsKey = "DSDPlayer.savedFolders.v1"

    init() {
        load()
    }

    func addFolder(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let folder = SavedFolder(name: url.lastPathComponent, bookmark: bookmark)
            if !folders.contains(where: { $0.name == folder.name }) {
                folders.append(folder)
                save()
            }
        } catch {
            print("[LibraryStore] Failed to bookmark folder: \(error)")
        }
    }

    func remove(at offsets: IndexSet) {
        folders.remove(atOffsets: offsets)
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        folders.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode([SavedFolder].self, from: data) else {
            return
        }
        folders = saved
    }
}
