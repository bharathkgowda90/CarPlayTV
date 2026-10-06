import XCTest
@testable import ReceiverKit

final class ReceiverKitTests: XCTestCase {
    func testUPnPTime() {
        XCTAssertEqual(UPnPTime.format(3725.9), "1:02:05")
        XCTAssertEqual(UPnPTime.format(nil), "0:00:00")
        XCTAssertEqual(UPnPTime.parse("01:02:05.500"), 3725.5)
        XCTAssertEqual(UPnPTime.parse("0:00:10"), 10)
        XCTAssertNil(UPnPTime.parse("10"))
    }

    func testSOAPParseActionAndArguments() throws {
        let body = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>
        <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
        <InstanceID>0</InstanceID>
        <CurrentURI>http://192.168.1.5:32400/video.mkv?a=1&amp;b=2</CurrentURI>
        <CurrentURIMetaData>&lt;DIDL-Lite&gt;&lt;item&gt;&lt;dc:title&gt;Tom &amp;amp; Jerry&lt;/dc:title&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;</CurrentURIMetaData>
        </u:SetAVTransportURI></s:Body></s:Envelope>
        """
        let request = try XCTUnwrap(SOAP.parse(Data(body.utf8)))
        XCTAssertEqual(request.action, "SetAVTransportURI")
        XCTAssertEqual(request.arguments["InstanceID"], "0")
        XCTAssertEqual(request.arguments["CurrentURI"], "http://192.168.1.5:32400/video.mkv?a=1&b=2")
        XCTAssertEqual(DIDLLite.title(from: request.arguments["CurrentURIMetaData"]), "Tom & Jerry")
    }

    func testSOAPResponseEscapesValues() {
        let data = SOAP.response(action: "GetPositionInfo", serviceType: UPnPDocuments.avTransport, values: [("TrackURI", "a&b")])
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("<u:GetPositionInfoResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">"))
        XCTAssertTrue(text.contains("<TrackURI>a&amp;b</TrackURI>"))
    }

    func testDocumentsAreWellFormedXML() {
        for document in [
            UPnPDocuments.deviceDescription(friendlyName: "CarPlayTV <Bob's iPhone>", udn: "1234"),
            UPnPDocuments.avTransportSCPD, UPnPDocuments.renderingControlSCPD, UPnPDocuments.connectionManagerSCPD,
        ] {
            XCTAssertTrue(XMLParser(data: Data(document.utf8)).parse(), document)
        }
    }

    func testSSDPSearchHandling() {
        let search = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n"
        let target = SSDP.searchTarget(in: search)
        XCTAssertEqual(target, UPnPDocuments.deviceType)

        let responses = SSDP.responses(for: target!, udn: "abc", location: "http://10.0.0.2:5000/description.xml")
        XCTAssertEqual(responses.count, 1)
        XCTAssertTrue(responses[0].contains("USN: uuid:abc::urn:schemas-upnp-org:device:MediaRenderer:1\r\n"))
        XCTAssertTrue(responses[0].hasSuffix("\r\n\r\n"))

        XCTAssertEqual(SSDP.responses(for: "ssdp:all", udn: "abc", location: "x").count, 6)
        XCTAssertNil(SSDP.searchTarget(in: "NOTIFY * HTTP/1.1\r\nNT: upnp:rootdevice\r\n\r\n"))
    }

    func testHTTPParserWaitsForFullBody() throws {
        let head = "POST /control/AVTransport?x=1 HTTP/1.1\r\nHost: a\r\nContent-Length: 5\r\nSOAPACTION: \"x#Play\"\r\n\r\n"
        XCTAssertNil(HTTPParser.parse(Data((head + "ab").utf8)))
        let request = try XCTUnwrap(HTTPParser.parse(Data((head + "abcde").utf8)))
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/control/AVTransport")
        XCTAssertEqual(request.header("SOAPAction"), "\"x#Play\"")
        XCTAssertEqual(request.body, Data("abcde".utf8))
    }

    @MainActor
    func testAVTransportDrivesDelegate() async throws {
        let player = FakePlayer()
        let service = MediaRendererService(friendlyName: "Test", udn: "u", delegate: player)

        let set = SOAPRequest(action: "SetAVTransportURI", arguments: [
            "InstanceID": "0", "CurrentURI": "http://h/v.mp4",
            "CurrentURIMetaData": "<DIDL-Lite><item><dc:title>Clip</dc:title></item></DIDL-Lite>",
        ])
        let setResult = await service.avTransport(set)
        XCTAssertNotNil(setResult)
        XCTAssertEqual(player.loaded, URL(string: "http://h/v.mp4"))
        XCTAssertEqual(player.title, "Clip")

        _ = await service.avTransport(SOAPRequest(action: "Seek", arguments: ["Unit": "REL_TIME", "Target": "0:01:30"]))
        XCTAssertEqual(player.seekedTo, 90)

        player.status = RendererStatus(state: .playing, position: 95, duration: 600)
        let infoResult = await service.avTransport(SOAPRequest(action: "GetPositionInfo", arguments: [:]))
        let info = try XCTUnwrap(infoResult)
        let values = Dictionary(uniqueKeysWithValues: info)
        XCTAssertEqual(values["RelTime"], "0:01:35")
        XCTAssertEqual(values["TrackDuration"], "0:10:00")
        XCTAssertEqual(values["TrackURI"], "http://h/v.mp4")

        let transportResult = await service.avTransport(SOAPRequest(action: "GetTransportInfo", arguments: [:]))
        let transport = try XCTUnwrap(transportResult)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: transport)["CurrentTransportState"], "PLAYING")

        let bogus = await service.avTransport(SOAPRequest(action: "Bogus", arguments: [:]))
        XCTAssertNil(bogus)
    }
}

@MainActor
private final class FakePlayer: MediaRendererDelegate {
    var loaded: URL?
    var title: String?
    var seekedTo: Double?
    var status = RendererStatus(state: .stopped, position: 0, duration: nil)

    func renderer(load url: URL, title: String?) { loaded = url; self.title = title }
    func rendererPlay() {}
    func rendererPause() {}
    func rendererStop() {}
    func renderer(seekTo seconds: Double) { seekedTo = seconds }
    func rendererSetVolume(_ volume: Int) {}
    func rendererStatus() -> RendererStatus { status }
}
