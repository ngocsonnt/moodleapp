import SwiftUI

struct FolderDetailView: View {
    let folder: SavedFolder
    @EnvironmentObject var player: PlayerState

    @State private var resolvedURL: URL?
    @State private var scopeActive = false
    @State private var tracks: [Track] = []
    @State private var subfolders: [URL] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

            if let resolved = resolvedURL, !subfolders.isEmpty {
                Section("Subfolders") {
                    ForEach(subfolders, id: \.self) { sub in
                        NavigationLink(value: SubfolderRef(parentURL: resolved, url: sub)) {
                            Label(sub.lastPathComponent, systemImage: "folder")
                        }
                    }
                }
            }

            if !tracks.isEmpty {
                Section("Tracks (\(tracks.count))") {
                    ForEach(tracks) { track in
                        TrackRow(track: track, isCurrent: player.currentTrack == track) {
                            player.play(track: track, in: tracks, folderURL: resolvedURL)
                        }
                    }
                }
            } else if subfolders.isEmpty && errorMessage == nil && resolvedURL != nil {
                ContentUnavailableView(
                    "No audio files",
                    systemImage: "music.note.list",
                    description: Text("This folder doesn't contain any supported audio files.")
                )
            }
        }
        .navigationTitle(folder.name)
        .navigationDestination(for: SubfolderRef.self) { ref in
            SubfolderDetailView(parentURL: ref.parentURL, folderURL: ref.url)
        }
        .task { load() }
        .onDisappear { releaseScope() }
    }

    private func load() {
        do {
            let url = try folder.resolveURL()
            scopeActive = url.startAccessingSecurityScopedResource()
            resolvedURL = url
            (tracks, subfolders) = try Self.scanDirectory(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func releaseScope() {
        if scopeActive, let url = resolvedURL {
            url.stopAccessingSecurityScopedResource()
        }
        scopeActive = false
    }

    static func scanDirectory(url: URL) throws -> (tracks: [Track], subfolders: [URL]) {
        let items = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var tracks: [Track] = []
        var folders: [URL] = []
        for item in items {
            let resourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues?.isDirectory == true {
                folders.append(item)
            } else if Track.supportedExtensions.contains(item.pathExtension.lowercased()) {
                tracks.append(Track(url: item))
            }
        }
        tracks.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        folders.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        return (tracks, folders)
    }
}

struct SubfolderRef: Hashable {
    let parentURL: URL
    let url: URL
}

struct SubfolderDetailView: View {
    let parentURL: URL
    let folderURL: URL
    @EnvironmentObject var player: PlayerState

    @State private var tracks: [Track] = []
    @State private var subfolders: [URL] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
            if !subfolders.isEmpty {
                Section("Subfolders") {
                    ForEach(subfolders, id: \.self) { sub in
                        NavigationLink(value: SubfolderRef(parentURL: parentURL, url: sub)) {
                            Label(sub.lastPathComponent, systemImage: "folder")
                        }
                    }
                }
            }
            if !tracks.isEmpty {
                Section("Tracks (\(tracks.count))") {
                    ForEach(tracks) { track in
                        TrackRow(track: track, isCurrent: player.currentTrack == track) {
                            player.play(track: track, in: tracks, folderURL: parentURL)
                        }
                    }
                }
            }
        }
        .navigationTitle(folderURL.lastPathComponent)
        .task { load() }
    }

    private func load() {
        do {
            let result = try FolderDetailView.scanDirectory(url: folderURL)
            tracks = result.tracks
            subfolders = result.subfolders
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: track.isDSD ? "waveform.path" : "music.note")
                    .foregroundStyle(track.isDSD ? Color.accentColor : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(track.formatLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

