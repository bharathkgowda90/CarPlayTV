import MirrorKit
import Network
import ReplayKit

/// ReplayKit broadcast extension: encodes the iPhone screen and sends it to the
/// CarPlayTV app over a loopback connection; the app draws it on the car display.
final class SampleHandler: RPBroadcastSampleHandler {
    private let encoder = MirrorEncoder()
    private let queue = DispatchQueue(label: "CarPlayTV.Mirror.Send")
    private let lock = NSLock()
    private var connection: NWConnection?
    private var isReady = false
    private var finished = false
    /// Bytes handed to the connection but not yet sent; used to drop frames when the
    /// link can't keep up instead of building latency.
    private var pendingBytes = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        encoder.onMessage = { [weak self] message in self?.send(message) }

        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: MirrorProtocol.port)!, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.lock.withLock { self.isReady = true }
                self.encoder.requestKeyframe()
            case .waiting, .failed:
                self.fail("Open CarPlayTV on the car display, then start mirroring again.")
            case .cancelled:
                self.fail("Mirroring stopped.")
            default:
                break
            }
        }
        connection.start(queue: queue)
        self.connection = connection
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video, lock.withLock({ isReady }) else { return }
        let orientation = (CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber)?.uint8Value ?? 1
        encoder.encode(sampleBuffer, orientation: orientation)
    }

    override func broadcastPaused() {}
    override func broadcastResumed() { encoder.requestKeyframe() }

    override func broadcastFinished() {
        lock.withLock { finished = true }
        connection?.cancel()
    }

    private func send(_ message: MirrorMessage) {
        guard let connection else { return }
        if case .frame(_, let isKeyframe, _, _) = message, !isKeyframe, lock.withLock({ pendingBytes > 3_000_000 }) {
            return
        }
        let data = message.encoded()
        lock.withLock { pendingBytes += data.count }
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            self.lock.withLock { self.pendingBytes -= data.count }
        })
    }

    private func fail(_ reason: String) {
        let shouldFinish = lock.withLock { () -> Bool in
            defer { finished = true }
            return !finished
        }
        guard shouldFinish else { return }
        finishBroadcastWithError(NSError(domain: "CarPlayTV", code: 1, userInfo: [NSLocalizedDescriptionKey: reason]))
    }
}
