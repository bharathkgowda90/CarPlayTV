import AVFoundation
import PlaybackKit
import SwiftUI
import UniformTypeIdentifiers

struct MiniPlayerBar: View {
    @Environment(AppModel.self) private var model
    let open: () -> Void

    var body: some View {
        let player = model.player
        HStack(spacing: 12) {
            Button(action: open) {
                HStack {
                    ArtworkView(url: player.currentChannel?.logoURL)
                    VStack(alignment: .leading) {
                        Text(player.currentChannel?.name ?? "").lineLimit(1).foregroundStyle(.primary)
                        Text(model.isCarConnected ? "On the car display" : (player.isLoading ? "Loading…" : player.engineKind == .software ? "Software decoder" : ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3)
            }
            Button { player.next() } label: { Image(systemName: "forward.fill").font(.title3) }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct PlayerScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var importingSubtitles = false
    @State private var subtitleError: String?
    @State private var scrubPosition: Double?

    var body: some View {
        let player = model.player
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    videoArea(player)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.currentChannel?.name ?? "Nothing playing").font(.title3.bold())
                        if let group = player.currentChannel?.group { Text(group).foregroundStyle(.secondary) }
                        if let error = player.errorMessage { Text(error).foregroundStyle(.red).font(.callout) }
                    }

                    if player.canSeek, let duration = player.duration {
                        VStack(spacing: 2) {
                            Slider(value: Binding(
                                get: { scrubPosition ?? player.currentTime },
                                set: { scrubPosition = $0 }
                            ), in: 0...max(duration, 1)) { editing in
                                if !editing, let target = scrubPosition {
                                    player.seek(to: target)
                                    scrubPosition = nil
                                }
                            }
                            HStack {
                                Text(Format.time(scrubPosition ?? player.currentTime))
                                Spacer()
                                Text("-" + Format.time(duration - (scrubPosition ?? player.currentTime)))
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                    } else if player.isLive {
                        Label("Live", systemImage: "dot.radiowaves.left.and.right").font(.caption.bold()).foregroundStyle(.red)
                    }

                    transportControls(player)
                    optionsSection(player)
                }
                .padding()
            }
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                }
                if let channel = player.currentChannel {
                    ToolbarItem(placement: .primaryAction) {
                        Button { model.library.toggleFavorite(channel) } label: {
                            Image(systemName: model.library.isFavorite(channel) ? "star.fill" : "star")
                        }
                    }
                }
            }
            .fileImporter(isPresented: $importingSubtitles, allowedContentTypes: [UTType(filenameExtension: "srt") ?? .plainText, UTType(filenameExtension: "vtt") ?? .plainText, .plainText]) { result in
                guard case .success(let url) = result else { return }
                Task {
                    do { try await player.loadExternalSubtitles(from: url); subtitleError = nil }
                    catch { subtitleError = error.localizedDescription }
                }
            }
        }
    }

    @ViewBuilder
    private func videoArea(_ player: PlayerController) -> some View {
        ZStack {
            if !model.driveMonitor.isVideoAllowed {
                Label("Video paused while driving. Audio keeps playing.", systemImage: "car.fill")
                    .foregroundStyle(.orange)
            } else if model.isCarConnected && player.engineKind == .software {
                Label("Playing on the car display", systemImage: "carplay")
            } else {
                VideoSurface(player: player)
            }
            if player.isLoading { ProgressView().tint(.white) }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func transportControls(_ player: PlayerController) -> some View {
        HStack {
            Spacer()
            Button { player.previous() } label: { Image(systemName: "backward.fill") }
            Spacer()
            if player.canSeek {
                Button { player.skip(by: -15) } label: { Image(systemName: "gobackward.15") }
                Spacer()
            }
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 52))
            }
            Spacer()
            if player.canSeek {
                Button { player.skip(by: 15) } label: { Image(systemName: "goforward.15") }
                Spacer()
            }
            Button { player.next() } label: { Image(systemName: "forward.fill") }
            Spacer()
        }
        .font(.title2)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func optionsSection(_ player: PlayerController) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let channel = player.currentChannel, channel.streamURLs.count > 1 {
                Button { player.switchLine() } label: {
                    Label("Line \(player.currentLineIndex + 1) of \(channel.streamURLs.count) – switch", systemImage: "arrow.triangle.swap")
                }
            }

            Picker("Picture", selection: Binding(
                get: { player.videoGravity == .resizeAspectFill ? 1 : 0 },
                set: { player.setVideoGravity($0 == 1 ? .resizeAspectFill : .resizeAspect) }
            )) {
                Text("Fit").tag(0)
                Text("Fill").tag(1)
            }
            .pickerStyle(.segmented)

            if player.audioTracks.count > 1 {
                Menu {
                    ForEach(player.audioTracks) { track in
                        Button { player.selectAudioTrack(id: track.id) } label: {
                            if track.id == player.selectedAudioTrackID { Label(track.name, systemImage: "checkmark") } else { Text(track.name) }
                        }
                    }
                } label: { Label("Audio track", systemImage: "speaker.wave.2") }
            }

            Menu {
                Button("Off") { player.selectSubtitleTrack(id: nil); player.clearExternalSubtitles() }
                ForEach(player.subtitleTracks) { track in
                    Button { player.selectSubtitleTrack(id: track.id) } label: {
                        if track.id == player.selectedSubtitleTrackID { Label(track.name, systemImage: "checkmark") } else { Text(track.name) }
                    }
                }
                Divider()
                Button("Load subtitle file (.srt, .vtt)…") { importingSubtitles = true }
            } label: {
                Label(player.externalSubtitleName ?? "Subtitles", systemImage: "captions.bubble")
            }
            if let subtitleError { Text(subtitleError).font(.caption).foregroundStyle(.red) }

            if player.externalSubtitleName != nil && !model.pro.isPro {
                Button("Adjust subtitle timing (Pro)") {
                    model.paywallReason = "Subtitle timing adjustment is part of CarPlayTV Pro."
                }
            } else if player.externalSubtitleName != nil {
                Stepper(value: Binding(get: { player.subtitleOffset }, set: { player.subtitleOffset = $0 }),
                        in: -30...30, step: 0.25) {
                    Text("Subtitle delay: \(player.subtitleOffset, specifier: "%+.2f") s")
                }
            }

            LabeledContent("Decoder", value: player.engineKind == .software ? "Software (VLC)" : "Hardware")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
