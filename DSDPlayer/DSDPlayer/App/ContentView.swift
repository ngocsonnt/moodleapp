import SwiftUI

struct ContentView: View {
    @EnvironmentObject var player: PlayerState

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "folder") }

            PlayerView()
                .tabItem { Label("Now Playing", systemImage: "play.circle") }
                .badge(player.isPlaying ? "▶" : nil)
        }
    }
}
