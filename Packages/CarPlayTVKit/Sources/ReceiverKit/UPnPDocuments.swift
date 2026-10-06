import Foundation

/// Device and service descriptions for a UPnP AV MediaRenderer.
public enum UPnPDocuments {
    public static let avTransport = "urn:schemas-upnp-org:service:AVTransport:1"
    public static let renderingControl = "urn:schemas-upnp-org:service:RenderingControl:1"
    public static let connectionManager = "urn:schemas-upnp-org:service:ConnectionManager:1"
    public static let deviceType = "urn:schemas-upnp-org:device:MediaRenderer:1"

    public static let sinkProtocolInfo = [
        "video/mp4", "video/x-matroska", "video/quicktime", "video/x-msvideo", "video/mpeg", "video/mp2t",
        "video/webm", "video/x-flv", "application/vnd.apple.mpegurl", "application/x-mpegURL",
        "audio/mpeg", "audio/mp4", "audio/aac", "audio/flac", "audio/wav", "audio/x-wav",
    ].map { "http-get:*:\($0):*" }.joined(separator: ",")

    public static func deviceDescription(friendlyName: String, udn: String) -> String {
        func service(_ type: String, _ id: String) -> String {
            "<service><serviceType>\(type)</serviceType><serviceId>urn:upnp-org:serviceId:\(id)</serviceId>"
                + "<SCPDURL>/\(id).xml</SCPDURL><controlURL>/control/\(id)</controlURL><eventSubURL>/event/\(id)</eventSubURL></service>"
        }
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <root xmlns="urn:schemas-upnp-org:device-1-0" xmlns:dlna="urn:schemas-dlna-org:device-1-0">
        <specVersion><major>1</major><minor>0</minor></specVersion>
        <device>
        <deviceType>\(deviceType)</deviceType>
        <friendlyName>\(XMLText.escape(friendlyName))</friendlyName>
        <manufacturer>CarPlayTV</manufacturer>
        <modelName>CarPlayTV</modelName>
        <modelDescription>Video player for the CarPlay display</modelDescription>
        <modelNumber>1</modelNumber>
        <UDN>uuid:\(udn)</UDN>
        <dlna:X_DLNADOC>DMR-1.50</dlna:X_DLNADOC>
        <serviceList>\(service(avTransport, "AVTransport"))\(service(renderingControl, "RenderingControl"))\(service(connectionManager, "ConnectionManager"))</serviceList>
        </device>
        </root>
        """
    }

    // MARK: - Service descriptions

    private struct Action {
        let name: String
        let arguments: [(name: String, direction: String, variable: String)]
    }

    private struct Variable {
        let name: String
        let type: String
        var events = false
        var allowed: [String] = []
    }

    private static func scpd(actions: [Action], variables: [Variable]) -> String {
        let actionXML = actions.map { action in
            let args = action.arguments.map {
                "<argument><name>\($0.name)</name><direction>\($0.direction)</direction><relatedStateVariable>\($0.variable)</relatedStateVariable></argument>"
            }.joined()
            return "<action><name>\(action.name)</name><argumentList>\(args)</argumentList></action>"
        }.joined()
        let variableXML = variables.map { variable in
            let allowed = variable.allowed.isEmpty ? "" :
                "<allowedValueList>" + variable.allowed.map { "<allowedValue>\($0)</allowedValue>" }.joined() + "</allowedValueList>"
            return "<stateVariable sendEvents=\"\(variable.events ? "yes" : "no")\"><name>\(variable.name)</name><dataType>\(variable.type)</dataType>\(allowed)</stateVariable>"
        }.joined()
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <scpd xmlns="urn:schemas-upnp-org:service-1-0"><specVersion><major>1</major><minor>0</minor></specVersion><actionList>\(actionXML)</actionList><serviceStateTable>\(variableXML)</serviceStateTable></scpd>
        """
    }

    private static let instance = ("InstanceID", "in", "A_ARG_TYPE_InstanceID")

    public static let avTransportSCPD = scpd(actions: [
        Action(name: "SetAVTransportURI", arguments: [instance, ("CurrentURI", "in", "AVTransportURI"), ("CurrentURIMetaData", "in", "AVTransportURIMetaData")]),
        Action(name: "SetNextAVTransportURI", arguments: [instance, ("NextURI", "in", "NextAVTransportURI"), ("NextURIMetaData", "in", "NextAVTransportURIMetaData")]),
        Action(name: "GetMediaInfo", arguments: [instance, ("NrTracks", "out", "NumberOfTracks"), ("MediaDuration", "out", "CurrentMediaDuration"),
                                                 ("CurrentURI", "out", "AVTransportURI"), ("CurrentURIMetaData", "out", "AVTransportURIMetaData"),
                                                 ("NextURI", "out", "NextAVTransportURI"), ("NextURIMetaData", "out", "NextAVTransportURIMetaData"),
                                                 ("PlayMedium", "out", "PlaybackStorageMedium"), ("RecordMedium", "out", "RecordStorageMedium"),
                                                 ("WriteStatus", "out", "RecordMediumWriteStatus")]),
        Action(name: "GetTransportInfo", arguments: [instance, ("CurrentTransportState", "out", "TransportState"),
                                                     ("CurrentTransportStatus", "out", "TransportStatus"), ("CurrentSpeed", "out", "TransportPlaySpeed")]),
        Action(name: "GetPositionInfo", arguments: [instance, ("Track", "out", "CurrentTrack"), ("TrackDuration", "out", "CurrentTrackDuration"),
                                                    ("TrackMetaData", "out", "CurrentTrackMetaData"), ("TrackURI", "out", "CurrentTrackURI"),
                                                    ("RelTime", "out", "RelativeTimePosition"), ("AbsTime", "out", "AbsoluteTimePosition"),
                                                    ("RelCount", "out", "RelativeCounterPosition"), ("AbsCount", "out", "AbsoluteCounterPosition")]),
        Action(name: "GetDeviceCapabilities", arguments: [instance, ("PlayMedia", "out", "PossiblePlaybackStorageMedia"),
                                                          ("RecMedia", "out", "PossibleRecordStorageMedia"), ("RecQualityModes", "out", "PossibleRecordQualityModes")]),
        Action(name: "GetTransportSettings", arguments: [instance, ("PlayMode", "out", "CurrentPlayMode"), ("RecQualityMode", "out", "CurrentRecordQualityMode")]),
        Action(name: "GetCurrentTransportActions", arguments: [instance, ("Actions", "out", "CurrentTransportActions")]),
        Action(name: "Stop", arguments: [instance]),
        Action(name: "Play", arguments: [instance, ("Speed", "in", "TransportPlaySpeed")]),
        Action(name: "Pause", arguments: [instance]),
        Action(name: "Seek", arguments: [instance, ("Unit", "in", "A_ARG_TYPE_SeekMode"), ("Target", "in", "A_ARG_TYPE_SeekTarget")]),
        Action(name: "Next", arguments: [instance]),
        Action(name: "Previous", arguments: [instance]),
    ], variables: [
        Variable(name: "TransportState", type: "string", allowed: ["STOPPED", "PLAYING", "PAUSED_PLAYBACK", "TRANSITIONING", "NO_MEDIA_PRESENT"]),
        Variable(name: "TransportStatus", type: "string", allowed: ["OK", "ERROR_OCCURRED"]),
        Variable(name: "PlaybackStorageMedium", type: "string"),
        Variable(name: "RecordStorageMedium", type: "string"),
        Variable(name: "PossiblePlaybackStorageMedia", type: "string"),
        Variable(name: "PossibleRecordStorageMedia", type: "string"),
        Variable(name: "CurrentPlayMode", type: "string", allowed: ["NORMAL"]),
        Variable(name: "TransportPlaySpeed", type: "string", allowed: ["1"]),
        Variable(name: "RecordMediumWriteStatus", type: "string"),
        Variable(name: "CurrentRecordQualityMode", type: "string"),
        Variable(name: "PossibleRecordQualityModes", type: "string"),
        Variable(name: "NumberOfTracks", type: "ui4"),
        Variable(name: "CurrentTrack", type: "ui4"),
        Variable(name: "CurrentTrackDuration", type: "string"),
        Variable(name: "CurrentMediaDuration", type: "string"),
        Variable(name: "CurrentTrackMetaData", type: "string"),
        Variable(name: "CurrentTrackURI", type: "string"),
        Variable(name: "AVTransportURI", type: "string"),
        Variable(name: "AVTransportURIMetaData", type: "string"),
        Variable(name: "NextAVTransportURI", type: "string"),
        Variable(name: "NextAVTransportURIMetaData", type: "string"),
        Variable(name: "RelativeTimePosition", type: "string"),
        Variable(name: "AbsoluteTimePosition", type: "string"),
        Variable(name: "RelativeCounterPosition", type: "i4"),
        Variable(name: "AbsoluteCounterPosition", type: "i4"),
        Variable(name: "CurrentTransportActions", type: "string"),
        Variable(name: "LastChange", type: "string", events: true),
        Variable(name: "A_ARG_TYPE_SeekMode", type: "string", allowed: ["REL_TIME", "ABS_TIME", "TRACK_NR"]),
        Variable(name: "A_ARG_TYPE_SeekTarget", type: "string"),
        Variable(name: "A_ARG_TYPE_InstanceID", type: "ui4"),
    ])

    public static let renderingControlSCPD = scpd(actions: [
        Action(name: "ListPresets", arguments: [instance, ("CurrentPresetNameList", "out", "PresetNameList")]),
        Action(name: "SelectPreset", arguments: [instance, ("PresetName", "in", "A_ARG_TYPE_PresetName")]),
        Action(name: "GetMute", arguments: [instance, ("Channel", "in", "A_ARG_TYPE_Channel"), ("CurrentMute", "out", "Mute")]),
        Action(name: "SetMute", arguments: [instance, ("Channel", "in", "A_ARG_TYPE_Channel"), ("DesiredMute", "in", "Mute")]),
        Action(name: "GetVolume", arguments: [instance, ("Channel", "in", "A_ARG_TYPE_Channel"), ("CurrentVolume", "out", "Volume")]),
        Action(name: "SetVolume", arguments: [instance, ("Channel", "in", "A_ARG_TYPE_Channel"), ("DesiredVolume", "in", "Volume")]),
    ], variables: [
        Variable(name: "PresetNameList", type: "string"),
        Variable(name: "Mute", type: "boolean"),
        Variable(name: "Volume", type: "ui2"),
        Variable(name: "LastChange", type: "string", events: true),
        Variable(name: "A_ARG_TYPE_Channel", type: "string", allowed: ["Master"]),
        Variable(name: "A_ARG_TYPE_InstanceID", type: "ui4"),
        Variable(name: "A_ARG_TYPE_PresetName", type: "string", allowed: ["FactoryDefaults"]),
    ])

    public static let connectionManagerSCPD = scpd(actions: [
        Action(name: "GetProtocolInfo", arguments: [("Source", "out", "SourceProtocolInfo"), ("Sink", "out", "SinkProtocolInfo")]),
        Action(name: "GetCurrentConnectionIDs", arguments: [("ConnectionIDs", "out", "CurrentConnectionIDs")]),
        Action(name: "GetCurrentConnectionInfo", arguments: [
            ("ConnectionID", "in", "A_ARG_TYPE_ConnectionID"), ("RcsID", "out", "A_ARG_TYPE_RcsID"),
            ("AVTransportID", "out", "A_ARG_TYPE_AVTransportID"), ("ProtocolInfo", "out", "A_ARG_TYPE_ProtocolInfo"),
            ("PeerConnectionManager", "out", "A_ARG_TYPE_ConnectionManager"), ("PeerConnectionID", "out", "A_ARG_TYPE_ConnectionID"),
            ("Direction", "out", "A_ARG_TYPE_Direction"), ("Status", "out", "A_ARG_TYPE_ConnectionStatus"),
        ]),
    ], variables: [
        Variable(name: "SourceProtocolInfo", type: "string", events: true),
        Variable(name: "SinkProtocolInfo", type: "string", events: true),
        Variable(name: "CurrentConnectionIDs", type: "string", events: true),
        Variable(name: "A_ARG_TYPE_ConnectionStatus", type: "string", allowed: ["OK", "ContentFormatMismatch", "InsufficientBandwidth", "UnreliableChannel", "Unknown"]),
        Variable(name: "A_ARG_TYPE_ConnectionManager", type: "string"),
        Variable(name: "A_ARG_TYPE_Direction", type: "string", allowed: ["Input", "Output"]),
        Variable(name: "A_ARG_TYPE_ProtocolInfo", type: "string"),
        Variable(name: "A_ARG_TYPE_ConnectionID", type: "i4"),
        Variable(name: "A_ARG_TYPE_AVTransportID", type: "i4"),
        Variable(name: "A_ARG_TYPE_RcsID", type: "i4"),
    ])
}
