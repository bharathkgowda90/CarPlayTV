#if os(iOS)
import AVFoundation
import UIKit

/// A video surface used on the iPhone and on the car window. It holds an
/// `AVPlayerLayer` for the hardware engine, a plain view the software engine draws
/// into, and a label for external subtitles.
public final class VideoHostView: UIView {
    public let playerLayer = AVPlayerLayer()
    public let softwareDrawable = UIView()
    private let subtitleLabel = UILabel()

    /// Hosts with higher priority win when an engine can only draw in one place
    /// (the car screen beats the phone).
    public var priority: Int

    public init(priority: Int = 0) {
        self.priority = priority
        super.init(frame: .zero)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)

        softwareDrawable.backgroundColor = .clear
        softwareDrawable.isUserInteractionEnabled = false
        addSubview(softwareDrawable)

        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center
        subtitleLabel.textColor = .white
        subtitleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        subtitleLabel.shadowColor = .black
        subtitleLabel.shadowOffset = CGSize(width: 1, height: 1)
        subtitleLabel.isHidden = true
        addSubview(subtitleLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public var videoGravity: AVLayerVideoGravity {
        get { playerLayer.videoGravity }
        set { playerLayer.videoGravity = newValue }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
        softwareDrawable.frame = bounds
        // Scale subtitles with the surface so they stay readable on wide car screens.
        subtitleLabel.font = .systemFont(ofSize: max(16, bounds.height * 0.05), weight: .semibold)
        let width = bounds.width * 0.9
        let size = subtitleLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        subtitleLabel.frame = CGRect(x: (bounds.width - width) / 2, y: bounds.height - size.height - bounds.height * 0.06,
                                     width: width, height: size.height)
    }

    func setSubtitle(_ text: String?) {
        guard subtitleLabel.text != text else { return }
        subtitleLabel.text = text
        subtitleLabel.isHidden = text == nil
        setNeedsLayout()
    }
}
#endif
