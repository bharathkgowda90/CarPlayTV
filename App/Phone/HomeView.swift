import LibraryKit
import SourcesKit
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                if model.contents.isEmpty && model.localVideos.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing here yet", systemImage: "play.tv")
                    } description: {
                        Text("CarPlayTV doesn't include any content. Add your own playlist, Xtream account, Jellyfin or Emby server, or import videos in Sources.")
                    }
                }

                let resume = model.library.continueWatching
                if !resume.isEmpty {
                    Section("Continue Watching") {
                        ForEach(resume.prefix(10)) { entry in
                            ChannelRow(channel: entry.channel, list: resume.map(\.channel))
                        }
                    }
                }

                if !model.library.favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(model.library.favorites) { channel in
                            ChannelRow(channel: channel, list: model.library.favorites)
                        }
                    }
                }

                if !model.localVideos.isEmpty {
                    Section("On this iPhone") {
                        ForEach(model.localVideos) { video in
                            ChannelRow(channel: video, list: model.localVideos)
                        }
                    }
                }

                ForEach(model.contents) { content in
                    Section {
                        if content.isLoading && content.groups.isEmpty {
                            ProgressView()
                        } else if let error = content.error {
                            Text(error).foregroundStyle(.red)
                        }
                        ForEach(model.visibleGroups(of: content)) { group in
                            NavigationLink {
                                GroupView(group: group)
                            } label: {
                                LabeledContent(group.name, value: "\(group.channels.count)")
                            }
                        }
                    } header: {
                        Text(content.source.name)
                    }
                }
            }
            .navigationTitle("CarPlayTV")
            .refreshable { await model.reloadAll() }
        }
    }
}

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        NavigationStack {
            let results = model.search(query)
            List(results) { channel in
                ChannelRow(channel: channel, list: results)
            }
            .overlay {
                if !query.isEmpty && results.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Channels, movies, series")
        }
    }
}
