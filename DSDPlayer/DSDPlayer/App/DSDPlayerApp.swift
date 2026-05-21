import SwiftUI

@main
struct DSDPlayerApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var player = PlayerState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(player)
        }
    }
}
