import Observation
import UIKit

/// Root view controller of the CarPlay window: full-screen video, plus a message when
/// there is nothing to show or video is paused because the car is moving.
@MainActor
final class VideoCanvasViewController: UIViewController {
    private let model: AppModel
    private lazy var playerView = PlayerLayerView(player: model.player.player)
    private let messageLabel = UILabel()

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        playerView.frame = view.bounds
        playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(playerView)

        messageLabel.textColor = .white
        messageLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(messageLabel)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            messageLabel.centerYAnchor.constraint(equalTo: guide.centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),
        ])

        observeState()
    }

    private func observeState() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeState() }
        }
    }

    private func render() {
        let videoAllowed = model.driveMonitor.isVideoAllowed
        // Hiding the layer stops video on the car screen; the player keeps playing audio.
        playerView.isHidden = !videoAllowed

        let message: String?
        if !videoAllowed {
            message = "Video paused while driving.\nAudio keeps playing."
        } else if let error = model.player.errorMessage {
            message = error
        } else if model.player.currentChannel == nil {
            message = "Tap Channels, or pick something on your iPhone."
        } else {
            message = nil
        }
        messageLabel.text = message
        messageLabel.isHidden = message == nil
    }
}
