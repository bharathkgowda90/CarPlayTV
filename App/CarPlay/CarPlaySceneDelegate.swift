import CarPlay
import LibraryKit
import Observation
import SourcesKit
import UIKit

/// CarPlay scene using the navigation-app approach: the app gets a `CPWindow` it can
/// draw into (normally a map). We put the video canvas there, and a transparent
/// `CPMapTemplate` on top supplies the buttons. Browsing uses list templates.
@MainActor
final class CarPlaySceneDelegate: UIResponder, @preconcurrency CPTemplateApplicationSceneDelegate {
    private let model = AppModel.shared
    private var interfaceController: CPInterfaceController?
    private var carWindow: CPWindow?
    private var canvas: VideoCanvasViewController?
    private var mapTemplate: CPMapTemplate?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        self.interfaceController = interfaceController
        carWindow = window
        let canvas = VideoCanvasViewController(model: model)
        self.canvas = canvas
        window.rootViewController = canvas

        let template = makeMapTemplate()
        mapTemplate = template
        interfaceController.setRootTemplate(template, animated: false, completion: nil)

        model.isCarConnected = true
        observePlaybackState()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        model.isCarConnected = false
        canvas?.tearDown()
        canvas = nil
        window.rootViewController = nil
        self.interfaceController = nil
        carWindow = nil
        mapTemplate = nil
    }

    // MARK: - Map template (controls over the video)

    private func makeMapTemplate() -> CPMapTemplate {
        let template = CPMapTemplate()
        template.automaticallyHidesNavigationBar = true
        template.hidesButtonsWithNavigationBar = true
        template.leadingNavigationBarButtons = [
            CPBarButton(title: "Browse") { [weak self] _ in self?.showBrowseRoot() },
        ]
        template.trailingNavigationBarButtons = makeTrailingButtons()
        template.mapButtons = makeMapButtons()
        return template
    }

    private func makeTrailingButtons() -> [CPBarButton] {
        var buttons: [CPBarButton] = []
        if (model.player.currentChannel?.streamURLs.count ?? 0) > 1 {
            buttons.append(CPBarButton(title: "Line") { [weak self] _ in self?.model.player.switchLine() })
        }
        let fill = model.player.videoGravity == .resizeAspectFill
        buttons.append(CPBarButton(title: fill ? "Fit" : "Fill") { [weak self] _ in
            guard let player = self?.model.player else { return }
            player.setVideoGravity(player.videoGravity == .resizeAspectFill ? .resizeAspect : .resizeAspectFill)
        })
        return buttons
    }

    private func makeMapButtons() -> [CPMapButton] {
        var buttons = [mapButton(symbol: "backward.fill") { $0.player.previous() }]
        if model.player.canSeek {
            buttons.append(mapButton(symbol: "gobackward.15") { $0.player.skip(by: -15) })
        }
        buttons.append(mapButton(symbol: model.player.isPlaying ? "pause.fill" : "play.fill") { $0.player.togglePlayPause() })
        buttons.append(mapButton(symbol: "forward.fill") { $0.player.next() })
        return buttons
    }

    private func mapButton(symbol: String, action: @escaping (AppModel) -> Void) -> CPMapButton {
        let button = CPMapButton { [weak self] _ in
            guard let self else { return }
            action(self.model)
        }
        button.image = UIImage(systemName: symbol)
        return button
    }

    /// Re-renders buttons whenever playback state changes.
    private func observePlaybackState() {
        guard interfaceController != nil, let mapTemplate else { return }
        withObservationTracking {
            mapTemplate.mapButtons = makeMapButtons()
            mapTemplate.trailingNavigationBarButtons = makeTrailingButtons()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observePlaybackState() }
        }
    }

    // MARK: - Browsing

    private func showBrowseRoot() {
        var items: [CPListItem] = []

        let resume = model.library.continueWatching.map(\.channel)
        if !resume.isEmpty {
            items.append(folderItem("Continue Watching", detail: "\(resume.count)") { [weak self] in
                self?.pushChannelList(title: "Continue Watching", channels: resume)
            })
        }
        let favorites = model.library.favorites
        if !favorites.isEmpty {
            items.append(folderItem("Favorites", detail: "\(favorites.count)") { [weak self] in
                self?.pushChannelList(title: "Favorites", channels: favorites)
            })
        }
        if !model.localVideos.isEmpty {
            let videos = model.localVideos
            items.append(folderItem("On this iPhone", detail: "\(videos.count)") { [weak self] in
                self?.pushChannelList(title: "On this iPhone", channels: videos)
            })
        }
        for content in model.contents {
            let groups = model.visibleGroups(of: content)
            items.append(folderItem(content.source.name, detail: content.error ?? content.source.kindLabel) { [weak self] in
                self?.pushGroupList(title: content.source.name, groups: groups)
            })
        }

        let list = CPListTemplate(title: "Browse", sections: [CPListSection(items: Array(items.prefix(CPListTemplate.maximumItemCount)))])
        list.emptyViewTitleVariants = ["Nothing to watch yet"]
        list.emptyViewSubtitleVariants = ["Add a source in CarPlayTV on your iPhone."]
        interfaceController?.pushTemplate(list, animated: true, completion: nil)
    }

    private func pushGroupList(title: String, groups: [ChannelGroup]) {
        // A source with a single group goes straight to its items.
        if groups.count == 1, let only = groups.first {
            pushChannelList(title: only.name, channels: only.channels)
            return
        }
        let items = groups.prefix(CPListTemplate.maximumItemCount).map { group in
            folderItem(group.name, detail: "\(group.channels.count)") { [weak self] in
                self?.pushChannelList(title: group.name, channels: group.channels)
            }
        }
        let list = CPListTemplate(title: title, sections: [CPListSection(items: Array(items))])
        list.emptyViewTitleVariants = ["No channels"]
        interfaceController?.pushTemplate(list, animated: true, completion: nil)
    }

    private func pushChannelList(title: String, channels: [Channel]) {
        let visible = Array(channels.prefix(CPListTemplate.maximumItemCount))
        let items = visible.map { channel in makeListItem(for: channel, queue: channels) }
        let list = CPListTemplate(title: title, sections: [CPListSection(items: items)])
        list.emptyViewTitleVariants = ["Nothing here"]
        interfaceController?.pushTemplate(list, animated: true, completion: nil)
        loadImages(for: Array(zip(items, visible)))
    }

    private func pushSeasons(of series: Channel, completion: @escaping () -> Void) {
        Task {
            let seasons = (try? await model.children(of: series)) ?? []
            let allEpisodes = seasons.flatMap(\.channels)
            let sections = seasons.prefix(CPListTemplate.maximumSectionCount).map { season in
                CPListSection(items: season.channels.prefix(CPListTemplate.maximumItemCount).map {
                    makeListItem(for: $0, queue: allEpisodes)
                }, header: season.name, sectionIndexTitle: nil)
            }
            let list = CPListTemplate(title: series.name, sections: Array(sections))
            list.emptyViewTitleVariants = ["No episodes"]
            interfaceController?.pushTemplate(list, animated: true, completion: nil)
            completion()
        }
    }

    private func makeListItem(for channel: Channel, queue: [Channel]) -> CPListItem {
        var detail: String?
        if channel.isContainer {
            detail = "Series"
        } else if let position = model.library.resumePosition(for: channel) {
            detail = "Resume at \(Self.format(position))"
        } else if let latency = model.health[channel.id]?.latencyMilliseconds {
            detail = "\(latency) ms"
        }
        let item = CPListItem(text: channel.name, detailText: detail)
        item.isPlaying = channel.id == model.player.currentChannel?.id
        item.accessoryType = channel.isContainer ? .disclosureIndicator : .none
        item.handler = { [weak self] _, completion in
            guard let self else { completion(); return }
            if channel.isContainer {
                self.pushSeasons(of: channel, completion: completion)
                return
            }
            self.model.play(channel, in: queue)
            self.interfaceController?.popToRootTemplate(animated: true, completion: nil)
            completion()
        }
        return item
    }

    private func folderItem(_ title: String, detail: String?, action: @escaping () -> Void) -> CPListItem {
        let item = CPListItem(text: title, detailText: detail)
        item.accessoryType = .disclosureIndicator
        item.handler = { _, completion in
            action()
            completion()
        }
        return item
    }

    private func loadImages(for pairs: [(CPListItem, Channel)]) {
        for (item, channel) in pairs.prefix(40) {
            guard let url = channel.logoURL else { continue }
            Task {
                if let image = await ImageCache.shared.image(for: url) { item.setImage(image) }
            }
        }
    }

    private static func format(_ seconds: Double) -> String {
        let total = Int(seconds)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}
