import LibraryKit
import SourcesKit
import SwiftUI

/// One item in a list. Tapping plays it, or opens a series.
struct ChannelRow: View {
    @Environment(AppModel.self) private var model
    let channel: Channel
    let list: [Channel]

    var body: some View {
        if channel.isContainer {
            NavigationLink { SeriesView(series: channel) } label: { label }
        } else {
            Button { model.play(channel, in: list) } label: { label }
                .contextMenu { favoriteButton }
                .swipeActions(edge: .leading) { favoriteButton.tint(.yellow) }
        }
    }

    private var label: some View {
        HStack(spacing: 12) {
            ArtworkView(url: channel.logoURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name).foregroundStyle(.primary).lineLimit(2)
                HStack(spacing: 6) {
                    if let latency = model.health[channel.id]?.latencyMilliseconds {
                        Text("\(latency) ms")
                    } else if model.health[channel.id]?.isReachable == false {
                        Text("Offline")
                    }
                    if channel.streamURLs.count > 1 { Text("\(channel.streamURLs.count) lines") }
                    if let position = model.library.resumePosition(for: channel), let duration = channel.durationSeconds ?? model.library.history.first(where: { $0.id == channel.id })?.duration {
                        Text("\(Format.time(position)) of \(Format.time(duration))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if model.library.isFavorite(channel) {
                Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
            }
            if model.player.currentChannel?.id == channel.id {
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint)
            }
        }
    }

    private var favoriteButton: some View {
        Button {
            model.library.toggleFavorite(channel)
        } label: {
            Label(model.library.isFavorite(channel) ? "Remove Favorite" : "Add to Favorites",
                  systemImage: model.library.isFavorite(channel) ? "star.slash" : "star")
        }
    }
}

struct ArtworkView: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Image(systemName: "tv").foregroundStyle(.secondary)
        }
        .frame(width: 56, height: 36)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct GroupView: View {
    @Environment(AppModel.self) private var model
    let group: ChannelGroup

    var body: some View {
        let channels = model.visibleChannels(group.channels)
        List(channels) { channel in
            ChannelRow(channel: channel, list: channels)
        }
        .navigationTitle(group.name)
    }
}

struct SeriesView: View {
    @Environment(AppModel.self) private var model
    let series: Channel
    @State private var seasons: [ChannelGroup] = []
    @State private var error: String?
    @State private var isLoading = true

    var body: some View {
        List {
            if let overview = series.overview, !overview.isEmpty {
                Section { Text(overview).font(.callout).foregroundStyle(.secondary) }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            ForEach(seasons) { season in
                Section(season.name) {
                    ForEach(season.channels) { episode in
                        ChannelRow(channel: episode, list: seasons.flatMap(\.channels))
                    }
                }
            }
        }
        .overlay { if isLoading { ProgressView() } }
        .navigationTitle(series.name)
        .task {
            do { seasons = try await model.children(of: series) } catch { self.error = error.localizedDescription }
            isLoading = false
        }
    }
}

enum Format {
    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--" }
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
