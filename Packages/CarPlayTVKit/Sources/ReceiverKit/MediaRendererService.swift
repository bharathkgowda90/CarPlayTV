import Foundation
import Network

/// What the controller (the casting app) sees about our playback.
public struct RendererStatus: Sendable {
    public enum State: String, Sendable {
        case stopped = "STOPPED"
        case playing = "PLAYING"
        case paused = "PAUSED_PLAYBACK"
        case transitioning = "TRANSITIONING"
        case noMedia = "NO_MEDIA_PRESENT"
    }

    public var state: State
    public var position: Double
    public var duration: Double?

    public init(state: State, position: Double, duration: Double?) {
        self.state = state
        self.position = position
        self.duration = duration
    }
}

/// The app side of the renderer: actually plays what is cast.
@MainActor
public protocol MediaRendererDelegate: AnyObject {
    func renderer(load url: URL, title: String?)
    func rendererPlay()
    func rendererPause()
    func rendererStop()
    func renderer(seekTo seconds: Double)
    func rendererSetVolume(_ volume: Int)
    func rendererStatus() -> RendererStatus
}

/// A UPnP/DLNA MediaRenderer: other apps' Cast buttons find it on the local network
/// (SSDP) and control it over SOAP (AVTransport, RenderingControl, ConnectionManager).
public final class MediaRendererService: @unchecked Sendable {
    public enum ServiceError: LocalizedError {
        case noLocalNetwork
        public var errorDescription: String? { "Connect the iPhone to Wi-Fi to receive casts." }
    }

    public let friendlyName: String
    public let udn: String
    public private(set) var isRunning = false
    public private(set) var location: String?

    private weak var delegate: MediaRendererDelegate?
    private var server: HTTPServer?
    private var advertiser: SSDPAdvertiser?
    private let lock = NSLock()
    private var currentURI = ""
    private var currentMetadata = ""
    private var volume = 100
    private var muted = false

    public init(friendlyName: String, udn: String, delegate: MediaRendererDelegate) {
        self.friendlyName = friendlyName
        self.udn = udn
        self.delegate = delegate
    }

    public func start() async throws {
        guard !isRunning else { return }
        guard let ip = NetworkInterfaces.localIPv4Address() else { throw ServiceError.noLocalNetwork }
        let server = HTTPServer { [weak self] request in
            await self?.handle(request) ?? .notFound
        }
        let port = try await server.start()
        let location = "http://\(ip):\(port)/description.xml"
        let advertiser = SSDPAdvertiser(udn: udn, location: location)
        try advertiser.start()
        self.server = server
        self.advertiser = advertiser
        self.location = location
        isRunning = true
    }

    public func stop() {
        advertiser?.stop()
        server?.stop()
        advertiser = nil
        server = nil
        isRunning = false
    }

    // MARK: - HTTP routing

    private func handle(_ request: HTTPRequest) async -> HTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/description.xml"):
            return .xml(UPnPDocuments.deviceDescription(friendlyName: friendlyName, udn: udn))
        case ("GET", "/AVTransport.xml"):
            return .xml(UPnPDocuments.avTransportSCPD)
        case ("GET", "/RenderingControl.xml"):
            return .xml(UPnPDocuments.renderingControlSCPD)
        case ("GET", "/ConnectionManager.xml"):
            return .xml(UPnPDocuments.connectionManagerSCPD)
        case ("SUBSCRIBE", _):
            // We don't push events; controllers fall back to polling GetPositionInfo.
            return HTTPResponse(headers: ["SID": "uuid:\(UUID().uuidString)", "TIMEOUT": "Second-1800"])
        case ("UNSUBSCRIBE", _):
            return HTTPResponse()
        case ("POST", "/control/AVTransport"):
            return await control(request, serviceType: UPnPDocuments.avTransport, handler: avTransport)
        case ("POST", "/control/RenderingControl"):
            return await control(request, serviceType: UPnPDocuments.renderingControl, handler: renderingControl)
        case ("POST", "/control/ConnectionManager"):
            return await control(request, serviceType: UPnPDocuments.connectionManager, handler: connectionManager)
        default:
            return .notFound
        }
    }

    private typealias ActionHandler = (SOAPRequest) async -> [(String, String)]?

    private func control(_ request: HTTPRequest, serviceType: String, handler: ActionHandler) async -> HTTPResponse {
        guard let soap = SOAP.parse(request.body) else {
            return HTTPResponse(status: 500, reason: "Internal Server Error", headers: ["Content-Type": "text/xml"],
                                body: SOAP.fault(code: 401, description: "Invalid Action"))
        }
        guard let values = await handler(soap) else {
            return HTTPResponse(status: 500, reason: "Internal Server Error", headers: ["Content-Type": "text/xml"],
                                body: SOAP.fault(code: 401, description: "Invalid Action"))
        }
        return HTTPResponse(headers: ["Content-Type": "text/xml; charset=\"utf-8\""],
                            body: SOAP.response(action: soap.action, serviceType: serviceType, values: values))
    }

    // MARK: - Services

    func avTransport(_ request: SOAPRequest) async -> [(String, String)]? {
        let args = request.arguments
        switch request.action {
        case "SetAVTransportURI":
            guard let uri = args["CurrentURI"], let url = URL(string: uri.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
            let metadata = args["CurrentURIMetaData"] ?? ""
            setCurrent(uri: uri, metadata: metadata)
            let title = DIDLLite.title(from: metadata)
            await MainActor.run { delegate?.renderer(load: url, title: title) }
            return []
        case "SetNextAVTransportURI":
            return []
        case "Play":
            await MainActor.run { delegate?.rendererPlay() }
            return []
        case "Pause":
            await MainActor.run { delegate?.rendererPause() }
            return []
        case "Stop":
            await MainActor.run { delegate?.rendererStop() }
            return []
        case "Seek":
            guard let target = args["Target"], let seconds = UPnPTime.parse(target) else { return nil }
            await MainActor.run { delegate?.renderer(seekTo: seconds) }
            return []
        case "Next", "Previous":
            return []
        case "GetTransportInfo":
            let status = await currentStatus()
            return [("CurrentTransportState", status.state.rawValue), ("CurrentTransportStatus", "OK"), ("CurrentSpeed", "1")]
        case "GetPositionInfo":
            let status = await currentStatus()
            let (uri, metadata) = current()
            return [
                ("Track", uri.isEmpty ? "0" : "1"),
                ("TrackDuration", UPnPTime.format(status.duration)),
                ("TrackMetaData", metadata),
                ("TrackURI", uri),
                ("RelTime", UPnPTime.format(status.position)),
                ("AbsTime", UPnPTime.format(status.position)),
                ("RelCount", "2147483647"),
                ("AbsCount", "2147483647"),
            ]
        case "GetMediaInfo":
            let status = await currentStatus()
            let (uri, metadata) = current()
            return [
                ("NrTracks", uri.isEmpty ? "0" : "1"), ("MediaDuration", UPnPTime.format(status.duration)),
                ("CurrentURI", uri), ("CurrentURIMetaData", metadata), ("NextURI", ""), ("NextURIMetaData", ""),
                ("PlayMedium", "NETWORK"), ("RecordMedium", "NOT_IMPLEMENTED"), ("WriteStatus", "NOT_IMPLEMENTED"),
            ]
        case "GetDeviceCapabilities":
            return [("PlayMedia", "NETWORK"), ("RecMedia", "NOT_IMPLEMENTED"), ("RecQualityModes", "NOT_IMPLEMENTED")]
        case "GetTransportSettings":
            return [("PlayMode", "NORMAL"), ("RecQualityMode", "NOT_IMPLEMENTED")]
        case "GetCurrentTransportActions":
            let status = await currentStatus()
            return [("Actions", status.state == .playing ? "Pause,Stop,Seek" : "Play,Stop,Seek")]
        default:
            return nil
        }
    }

    func renderingControl(_ request: SOAPRequest) async -> [(String, String)]? {
        switch request.action {
        case "GetVolume":
            return [("CurrentVolume", String(lock.withLock { volume }))]
        case "SetVolume":
            guard let value = Int(request.arguments["DesiredVolume"] ?? "") else { return nil }
            let clamped = min(100, max(0, value))
            lock.withLock { volume = clamped }
            await MainActor.run { delegate?.rendererSetVolume(clamped) }
            return []
        case "GetMute":
            return [("CurrentMute", lock.withLock { muted } ? "1" : "0")]
        case "SetMute":
            let mute = ["1", "true"].contains((request.arguments["DesiredMute"] ?? "").lowercased())
            lock.withLock { muted = mute }
            let level = mute ? 0 : lock.withLock { volume }
            await MainActor.run { delegate?.rendererSetVolume(level) }
            return []
        case "ListPresets":
            return [("CurrentPresetNameList", "FactoryDefaults")]
        case "SelectPreset":
            return []
        default:
            return nil
        }
    }

    func connectionManager(_ request: SOAPRequest) async -> [(String, String)]? {
        switch request.action {
        case "GetProtocolInfo":
            return [("Source", ""), ("Sink", UPnPDocuments.sinkProtocolInfo)]
        case "GetCurrentConnectionIDs":
            return [("ConnectionIDs", "0")]
        case "GetCurrentConnectionInfo":
            return [("RcsID", "0"), ("AVTransportID", "0"), ("ProtocolInfo", ""), ("PeerConnectionManager", ""),
                    ("PeerConnectionID", "-1"), ("Direction", "Input"), ("Status", "OK")]
        default:
            return nil
        }
    }

    // MARK: - State

    private func currentStatus() async -> RendererStatus {
        await MainActor.run {
            delegate?.rendererStatus() ?? RendererStatus(state: .noMedia, position: 0, duration: nil)
        }
    }

    private func setCurrent(uri: String, metadata: String) {
        lock.withLock {
            currentURI = uri
            currentMetadata = metadata
        }
    }

    private func current() -> (String, String) {
        lock.withLock { (currentURI, currentMetadata) }
    }
}
