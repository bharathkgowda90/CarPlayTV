import CarPlay
import Observation
import SourcesKit
import UIKit

/// CarPlay scene using the navigation-app approach: the app gets a `CPWindow` it can
/// draw into (normally a map). We put the video canvas there, and a transparent
/// `CPMapTemplate` on top supplies the on-screen buttons.
@MainActor
final class CarPlaySceneDelegate: UIResponder, @preconcurrency CPTemplateApplicationSceneDelegate {
    private let model = AppModel.shared
    private var interfaceController: CPInterfaceController?
    private var carWindow: CPWindow?
    private var mapTemplate: CPMapTemplate?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        self.interfaceController = interfaceController
        carWindow = window
        window.rootViewController = VideoCanvasViewController(model: model)

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
        window.rootViewController = nil
        self.interfaceController = nil
        carWindow = nil
        mapTemplate = nil
    }

    // MARK: - Templates

    private func makeMapTemplate() -> CPMapTemplate {
        let template = CPMapTemplate()
        template.automaticallyHidesNavigationBar = true
        template.hidesButtonsWithNavigationBar = true
        template.leadingNavigationBarButtons = [
            CPBarButton(title: "Channels") { [weak self] _ in self?.showChannelList() },
        ]
        template.trailingNavigationBarButtons = [
            CPBarButton(title: "Line") { [weak self] _ in self?.model.player.switchLine() },
        ]
        template.mapButtons = makeMapButtons()
        return template
    }

    private func makeMapButtons() -> [CPMapButton] {
        [
            mapButton(symbol: "backward.fill") { $0.player.previous() },
            mapButton(symbol: model.player.isPlaying ? "pause.fill" : "play.fill") { $0.player.togglePlayPause() },
            mapButton(symbol: "forward.fill") { $0.player.next() },
        ]
    }

    private func mapButton(symbol: String, action: @escaping (AppModel) -> Void) -> CPMapButton {
        let button = CPMapButton { [weak self] _ in
            guard let self else { return }
            action(self.model)
        }
        button.image = UIImage(systemName: symbol)
        return button
    }

    private func showChannelList() {
        guard let interfaceController else { return }

        var remaining = CPListTemplate.maximumItemCount
        var sections: [CPListSection] = []
        for group in model.channelGroups.prefix(CPListTemplate.maximumSectionCount) where remaining > 0 {
            let items = group.channels.prefix(remaining).map(makeListItem)
            remaining -= items.count
            sections.append(CPListSection(items: items, header: group.name, sectionIndexTitle: nil))
        }

        let list = CPListTemplate(title: "Channels", sections: sections)
        list.emptyViewTitleVariants = ["No channels yet"]
        list.emptyViewSubtitleVariants = ["Add a playlist in CarPlayTV on your iPhone."]
        interfaceController.pushTemplate(list, animated: true, completion: nil)
    }

    private func makeListItem(for channel: Channel) -> CPListItem {
        let detail = channel.streamURLs.count > 1 ? "\(channel.streamURLs.count) lines" : nil
        let item = CPListItem(text: channel.name, detailText: detail)
        item.isPlaying = channel == model.player.currentChannel
        item.handler = { [weak self] _, completion in
            self?.model.play(channel)
            self?.interfaceController?.popTemplate(animated: true, completion: nil)
            completion()
        }
        return item
    }

    // MARK: - State

    /// Re-renders the play/pause button whenever playback state changes.
    private func observePlaybackState() {
        guard interfaceController != nil else { return }
        withObservationTracking {
            mapTemplate?.mapButtons = makeMapButtons()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observePlaybackState() }
        }
    }
}
