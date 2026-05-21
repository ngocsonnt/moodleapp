import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var library: LibraryStore
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            Group {
                if library.folders.isEmpty {
                    emptyState
                } else {
                    folderList
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showPicker = true } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .accessibilityLabel("Add music folder")
                }
                if !library.folders.isEmpty {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
            }
            .sheet(isPresented: $showPicker) {
                FolderPicker(
                    onPicked: { url in
                        library.addFolder(url: url)
                        showPicker = false
                    },
                    onCancel: { showPicker = false }
                )
                .ignoresSafeArea()
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No music folders yet", systemImage: "folder.badge.questionmark")
        } description: {
            Text("Tap the + button to add a folder containing .dsf, .flac, .wav, or other audio files.")
        } actions: {
            Button("Add folder") { showPicker = true }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var folderList: some View {
        List {
            Section {
                ForEach(library.folders) { folder in
                    NavigationLink(value: folder) {
                        Label(folder.name, systemImage: "folder.fill")
                    }
                }
                .onDelete(perform: library.remove)
                .onMove(perform: library.move)
            } footer: {
                Text("Folders are bookmarked, so the app keeps access after you close it.")
            }
        }
        .navigationDestination(for: SavedFolder.self) { folder in
            FolderDetailView(folder: folder)
        }
    }
}
