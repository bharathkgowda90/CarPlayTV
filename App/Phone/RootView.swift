import SourcesKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var showPlayer = false
    @State private var openError: String?

    var body: some View {
        TabView {
            Tab("Home", systemImage: "play.tv") { HomeView() }
            Tab("Search", systemImage: "magnifyingglass") { SearchView() }
            Tab("Cast", systemImage: "rectangle.on.rectangle") { CastView() }
            Tab("Sources", systemImage: "list.bullet.rectangle") { SourcesView() }
            Tab("Settings", systemImage: "gearshape") { SettingsView() }
        }
        .safeAreaInset(edge: .bottom) {
            if model.player.currentChannel != nil {
                MiniPlayerBar { showPlayer = true }
                    .padding(.horizontal)
                    .padding(.bottom, 56)
            }
        }
        .fullScreenCover(isPresented: $showPlayer) { PlayerScreen() }
        .sheet(isPresented: .constant(!model.settings.hasAcceptedSafetyNotice)) { SafetyNoticeView() }
        .task { await model.reloadAll() }
        .onOpenURL(perform: open)
        .onReceive(NotificationCenter.default.publisher(for: .carPlayTVStopCasting)) { _ in
            model.stopCasting()
        }
        .alert("Couldn't open file", isPresented: .constant(openError != nil)) {
            Button("OK") { openError = nil }
        } message: {
            Text(openError ?? "")
        }
    }

    /// Handles .m3u playlists and video files opened from Files or shared from other apps.
    private func open(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if ext == "m3u" || ext == "m3u8" {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let copy = support.appendingPathComponent("Playlists", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
                let destination = copy.appendingPathComponent(UUID().uuidString + "." + ext)
                try FileManager.default.copyItem(at: url, to: destination)
                let source = Source(name: url.deletingPathExtension().lastPathComponent, kind: .m3u(url: destination))
                Task { await model.addSource(source, password: nil) }
            } catch {
                openError = error.localizedDescription
            }
        } else if LocalFilesProvider.videoExtensions.contains(ext) {
            do { try model.importLocalVideo(from: url) } catch { openError = error.localizedDescription }
        }
    }
}

struct SafetyNoticeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "car.side.fill").font(.system(size: 56)).foregroundStyle(.orange)
            Text("For passengers only").font(.title.bold())
            Text("Never watch video while driving. CarPlayTV pauses video on the car display when the car is moving; audio keeps playing.\n\nCarPlayTV is a player only. It doesn't include any channels or content. You add your own sources and are responsible for having the right to use them.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("I understand") { model.settings.hasAcceptedSafetyNotice = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(32)
        .interactiveDismissDisabled()
    }
}
