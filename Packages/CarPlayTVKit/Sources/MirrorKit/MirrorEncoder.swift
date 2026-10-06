#if os(iOS)
import CoreMedia
import Foundation
import VideoToolbox

/// Hardware H.264 encoder used by the broadcast extension. Scales frames down so the
/// extension stays well inside its memory limit, and caps the frame rate.
public final class MirrorEncoder: @unchecked Sendable {
    public var onMessage: ((MirrorMessage) -> Void)?

    private let maxLongSide: Int
    private let minFrameInterval: Double
    private var session: VTCompressionSession?
    private var transfer: VTPixelTransferSession?
    private var size: (width: Int32, height: Int32) = (0, 0)
    private var lastTimestamp: Double = -1
    private var forceKeyframe = true
    private let lock = NSLock()

    public init(maxLongSide: Int = 1280, maxFramesPerSecond: Double = 30) {
        self.maxLongSide = maxLongSide
        self.minFrameInterval = 1 / maxFramesPerSecond
    }

    deinit {
        if let session { VTCompressionSessionInvalidate(session) }
        if let transfer { VTPixelTransferSessionInvalidate(transfer) }
    }

    public func requestKeyframe() {
        lock.withLock { forceKeyframe = true }
    }

    public func encode(_ sampleBuffer: CMSampleBuffer, orientation: UInt8) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let seconds = pts.seconds
        guard seconds.isFinite, seconds - lastTimestamp >= minFrameInterval * 0.9 else { return }
        lastTimestamp = seconds

        let target = scaledSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        if session == nil || target.width != size.width || target.height != size.height {
            guard makeSession(width: target.width, height: target.height) else { return }
        }
        guard let session, let transfer, let pool = VTCompressionSessionGetPixelBufferPool(session) else { return }

        var scaled: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &scaled) == kCVReturnSuccess, let scaled,
              VTPixelTransferSessionTransferImage(transfer, from: pixelBuffer, to: scaled) == noErr else { return }

        let keyframe = lock.withLock { () -> Bool in
            defer { forceKeyframe = false }
            return forceKeyframe
        }
        let properties: CFDictionary? = keyframe ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil

        VTCompressionSessionEncodeFrame(session, imageBuffer: scaled, presentationTimeStamp: pts, duration: .invalid,
                                        frameProperties: properties, infoFlagsOut: nil) { [weak self] status, _, encoded in
            guard status == noErr, let encoded, let self else { return }
            self.emit(encoded, orientation: orientation)
        }
    }

    // MARK: - Private

    private func scaledSize(width: Int, height: Int) -> (width: Int32, height: Int32) {
        let longSide = max(width, height)
        let scale = longSide > maxLongSide ? Double(maxLongSide) / Double(longSide) : 1
        func even(_ value: Double) -> Int32 { Int32(value.rounded()) & ~1 }
        return (even(Double(width) * scale), even(Double(height) * scale))
    }

    private func makeSession(width: Int32, height: Int32) -> Bool {
        if let session { VTCompressionSessionInvalidate(session) }
        session = nil
        var created: VTCompressionSession?
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        guard VTCompressionSessionCreate(allocator: nil, width: width, height: height, codecType: kCMVideoCodecType_H264,
                                         encoderSpecification: nil, imageBufferAttributes: attributes as CFDictionary,
                                         compressedDataAllocator: nil, outputCallback: nil, refcon: nil,
                                         compressionSessionOut: &created) == noErr, let created else { return false }

        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 120 as CFNumber)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_AverageBitRate, value: 4_000_000 as CFNumber)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: 30 as CFNumber)
        VTCompressionSessionPrepareToEncodeFrames(created)

        if transfer == nil {
            var newTransfer: VTPixelTransferSession?
            VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &newTransfer)
            transfer = newTransfer
        }
        session = created
        size = (width, height)
        requestKeyframe()
        return transfer != nil
    }

    private func emit(_ sampleBuffer: CMSampleBuffer, orientation: UInt8) {
        var isKeyframe = true
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false),
           CFArrayGetCount(attachments) > 0 {
            let first = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self)
            isKeyframe = !CFDictionaryContainsKey(first, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque())
        }

        if isKeyframe, let format = CMSampleBufferGetFormatDescription(sampleBuffer),
           let sps = parameterSet(format, index: 0), let pps = parameterSet(format, index: 1) {
            onMessage?(.format(sps: sps, pps: pps))
        }

        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let length = CMBlockBufferGetDataLength(block)
        var data = Data(count: length)
        let status = data.withUnsafeMutableBytes { bytes in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
        }
        guard status == kCMBlockBufferNoErr else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        onMessage?(.frame(timestamp: timestamp, isKeyframe: isKeyframe, orientation: orientation, data: data))
    }

    private func parameterSet(_ format: CMFormatDescription, index: Int) -> Data? {
        var pointer: UnsafePointer<UInt8>?
        var size = 0
        let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format, parameterSetIndex: index, parameterSetPointerOut: &pointer,
            parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
        guard status == noErr, let pointer else { return nil }
        return Data(bytes: pointer, count: size)
    }
}
#endif
