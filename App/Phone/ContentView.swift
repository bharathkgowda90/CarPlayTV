import AVFoundation
import SourcesKit
import SwiftUI
import UniformTypeIdentifiers

/// Functional placeholder UI for Phase 0/1. The real design comes in Phase 4.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var playlistAddress = ""
    @State private var streamAddress = ""
    @State private var isImportingFile = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PlayerPanel()
                }

                Section("Add a playlist (M3U / M3U8)") {
                    TextField("https://example.com/playlist.m3u", text: $playlistAddress)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(model.isLoading ? "Loading…" : "Load playlist") {
                        guard let url = URL(string: playlistAddress.trimmingCharacters(in: .whitespaces)) else { return }
                        Task { await model.loadPlaylist(from: url) }
                    }
                    .disabled(playlistAddress.isEmpty || model.isLoading)
                    Button("Import .m3u file…") { isImportingFile = true }
                }

                Section("Play a stream address") {
                    TextField("https://example.com/stream.m3u8", text: $streamAddress)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Play") {
                        guard let url = URL(string: streamAddress.trimmingCharacters(in: .whitespaces)) else { return }
                        model.player.play(url: url)
                    }
                    .disabled(streamAddress.isEmpty)
                }

                if let error = model.loadError {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }

                ForEach(model.channelGroups) { group in
                    Section(group.name) {
                        ForEach(group.channels) { channel in
                            Button {
                                model.play(channel)
                            } label: {
                                ChannelRow(channel: channel, isCurrent: channel == model.player.currentChannel)
                            }
                        }
                    }
                }
            }
            .navigationTitle("CarPlayTV")
            .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.m3uPlaylist, .plainText]) { result in
                if case .success(let url) = result {
                    Task { await model.loadPlaylist(from: url) }
                }
            }
        }
    }
}

private struct ChannelRow: View {
    let channel: Channel
    let isCurrent: Bool

    var body: some View {
        HStack {
            Text(channel.name)
                .foregroundStyle(.primary)
            Spacer()
            if channel.streamURLs.count > 1 {
                Text("\(channel.streamURLs.count) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.tint)
            }
        }
    }
}

private struct PlayerPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.driveMonitor.isVideoAllowed {
                Label("Video paused while driving. Audio keeps playing.", systemImage: "car.fill")
                    .foregroundStyle(.orange)
            } else if model.isCarConnected {
                Label("Playing on the car display", systemImage: "carplay")
            } else {
                PlayerView(player: model.player.player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Text(model.player.currentChannel?.name ?? "Nothing playing")
                .font(.headline)
            if let error = model.player.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack(spacing: 32) {
                Button { model.player.previous() } label: { Image(systemName: "backward.fill") }
                Button { model.player.togglePlayPause() } label: {
                    Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
                }
                Button { model.player.next() } label: { Image(systemName: "forward.fill") }
                if (model.player.currentChannel?.streamURLs.count ?? 0) > 1 {
                    Button("Switch line") { model.player.switchLine() }
                }
            }
            .buttonStyle(.borderless)
            .font(.title2)
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 4)
    }
}

private struct PlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        PlayerLayerView(player: player)
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        view.playerLayer.player = player
    }
}
