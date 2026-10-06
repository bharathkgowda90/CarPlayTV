#if os(iOS)
import AVFoundation
import CoreMedia
import Network
import UIKit

/// Shows mirrored frames. The display layer is rotated to match the phone's orientation.
public final class MirrorDisplayView: UIView {
    let displayLayer = AVSampleBufferDisplayLayer()
    private var orientation: UInt8 = 1

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        displayLayer.videoGravity = .resizeAspect
        layer.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func enqueue(_ sampleBuffer: CMSampleBuffer, orientation: UInt8) {
        if orientation != self.orientation {
            self.orientation = orientation
            setNeedsLayout()
        }
        let renderer = displayLayer.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(sampleBuffer)
    }

    func clear() {
        displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // CGImagePropertyOrientation: 1 up, 3 down, 6 right, 8 left.
        let angle: CGFloat
        switch orientation {
        case 3: angle = .pi
        case 6: angle = .pi / 2
        case 8: angle = -.pi / 2
        default: angle = 0
        }
        let sideways = orientation == 6 || orientation == 8
        displayLayer.transform = CATransform3DIdentity
        displayLayer.bounds = CGRect(x: 0, y: 0,
                                     width: sideways ? bounds.height : bounds.width,
                                     height: sideways ? bounds.width : bounds.height)
        displayLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        displayLayer.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        CATransaction.commit()
    }
}

/// App side of screen mirroring: accepts the broadcast extension's loopback connection,
/// rebuilds H.264 sample buffers and shows them on registered displays.
@MainActor
public final class MirrorReceiver {
    public var onActiveChange: ((Bool) -> Void)?
    public private(set) var isActive = false

    private var listener: NWListener?
    private var connection: NWConnection?
    private var reader = MirrorStreamReader()
    private var formatDescription: CMVideoFormatDescription?
    private var currentSPS = Data()
    private var currentPPS = Data()
    private var displays: [WeakDisplay] = []

    public init() {}

    public func register(_ display: MirrorDisplayView) {
        displays.removeAll { $0.view == nil || $0.view === display }
        displays.append(WeakDisplay(view: display))
    }

    public func unregister(_ display: MirrorDisplayView) {
        displays.removeAll { $0.view == nil || $0.view === display }
    }

    /// Listens on the loopback interface only.
    public func start() throws {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: MirrorProtocol.port)!)
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    public func stop() {
        disconnect()
        listener?.cancel()
        listener = nil
    }

    /// Ends the current mirroring session; the extension sees the connection close and
    /// stops the broadcast.
    public func disconnect() {
        connection?.cancel()
        connection = nil
        setActive(false)
    }

    // MARK: - Private

    private func accept(_ newConnection: NWConnection) {
        connection?.cancel()
        connection = newConnection
        reader = MirrorStreamReader()
        formatDescription = nil
        newConnection.stateUpdateHandler = { [weak self, weak newConnection] state in
            MainActor.assumeIsolated {
                guard let self, let newConnection, self.connection === newConnection else { return }
                switch state {
                case .ready: self.setActive(true)
                case .failed, .cancelled: self.disconnect()
                default: break
                }
            }
        }
        newConnection.start(queue: .main)
        receive(on: newConnection)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 512 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, self.connection === connection else { return }
                if let data {
                    for message in self.reader.append(data) { self.handle(message) }
                }
                if isComplete || error != nil || self.reader.isCorrupt {
                    self.disconnect()
                } else {
                    self.receive(on: connection)
                }
            }
        }
    }

    private func handle(_ message: MirrorMessage) {
        switch message {
        case .format(let sps, let pps):
            guard sps != currentSPS || pps != currentPPS || formatDescription == nil else { return }
            currentSPS = sps
            currentPPS = pps
            formatDescription = Self.makeFormat(sps: sps, pps: pps)
        case .frame(_, _, let orientation, let data):
            guard let formatDescription, let sample = Self.makeSample(data: data, format: formatDescription) else { return }
            displays.removeAll { $0.view == nil }
            for display in displays.compactMap(\.view) {
                display.enqueue(sample, orientation: orientation)
            }
        }
    }

    private func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if !active {
            for display in displays.compactMap(\.view) { display.clear() }
        }
        onActiveChange?(active)
    }

    private static func makeFormat(sps: Data, pps: Data) -> CMVideoFormatDescription? {
        var format: CMVideoFormatDescription?
        let status = sps.withUnsafeBytes { spsBytes in
            pps.withUnsafeBytes { ppsBytes -> OSStatus in
                let pointers = [spsBytes.bindMemory(to: UInt8.self).baseAddress!, ppsBytes.bindMemory(to: UInt8.self).baseAddress!]
                let sizes = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: nil, parameterSetCount: 2, parameterSetPointers: pointers,
                    parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &format)
            }
        }
        return status == noErr ? format : nil
    }

    private static func makeSample(data: Data, format: CMVideoFormatDescription) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: data.count,
                                                 blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                                                 dataLength: data.count, flags: kCMBlockBufferAssureMemoryNowFlag,
                                                 blockBufferOut: &block) == kCMBlockBufferNoErr, let block else { return nil }
        let copied = data.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count)
        }
        guard copied == kCMBlockBufferNoErr else { return nil }

        var sample: CMSampleBuffer?
        var size = data.count
        guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
                                        sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 1,
                                        sampleSizeArray: &size, sampleBufferOut: &sample) == noErr, let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let first = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(first,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}

private struct WeakDisplay {
    weak var view: MirrorDisplayView?
}
#endif
