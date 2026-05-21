import SwiftUI

struct PlayerView: View {
    @EnvironmentObject var player: PlayerState

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                artwork
                trackInfo
                statusLine
                Spacer()
                transportButtons
                Spacer().frame(height: 12)
            }
            .padding(.horizontal, 24)
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Playback error",
                   isPresented: Binding(
                    get: { player.errorMessage != nil },
                    set: { if !$0 { player.errorMessage = nil } }
                   ),
                   actions: { Button("OK", role: .cancel) {} },
                   message: { Text(player.errorMessage ?? "") })
        }
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(
                    colors: [.accentColor.opacity(0.7), .accentColor.opacity(0.25)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 260, height: 260)
                .shadow(color: .accentColor.opacity(0.3), radius: 20, x: 0, y: 10)
            Image(systemName: player.currentTrack?.isDSD == true
                  ? "waveform.path"
                  : "music.quarternote.3")
                .font(.system(size: 96, weight: .light))
                .foregroundStyle(.white)
                .symbolEffect(.pulse, isActive: player.isPlaying)
        }
    }

    private var trackInfo: some View {
        VStack(spacing: 6) {
            Text(player.currentTrack?.title ?? "No track")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if let t = player.currentTrack {
                Text(t.formatLabel)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
    }

    private var statusLine: some View {
        VStack(spacing: 2) {
            if !player.formatDetail.isEmpty {
                Text(player.formatDetail).font(.caption).foregroundStyle(.secondary)
            }
            if !player.statusMessage.isEmpty {
                Text(player.statusMessage).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: 30)
    }

    private var transportButtons: some View {
        HStack(spacing: 40) {
            Button { player.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
            }
            .disabled(player.queue.isEmpty)

            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.accentColor)
            }
            .disabled(player.currentTrack == nil)

            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
            }
            .disabled(player.queue.isEmpty)
        }
        .foregroundStyle(.primary)
    }
}
