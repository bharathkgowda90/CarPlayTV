import Foundation
import Network

/// Announces the renderer on the local network and answers M-SEARCH discovery.
/// Joining the SSDP multicast group needs the `com.apple.developer.networking.multicast`
/// entitlement on iOS.
final class SSDPAdvertiser: @unchecked Sendable {
    private let queue = DispatchQueue(label: "CarPlayTV.SSDP")
    private var group: NWConnectionGroup?
    private var timer: DispatchSourceTimer?
    private let udn: String
    private let location: String

    var onStateChange: (@Sendable (NWConnectionGroup.State) -> Void)?

    init(udn: String, location: String) {
        self.udn = udn
        self.location = location
    }

    func start() throws {
        let multicast = try NWMulticastGroup(for: [.hostPort(host: NWEndpoint.Host(SSDP.multicastHost),
                                                             port: NWEndpoint.Port(rawValue: SSDP.port)!)])
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        let group = NWConnectionGroup(with: multicast, using: parameters)
        group.setReceiveHandler(maximumMessageSize: 16 * 1024, rejectOversizedMessages: true) { [weak self] message, content, _ in
            guard let self, let content, let text = String(data: content, encoding: .utf8),
                  let target = SSDP.searchTarget(in: text) else { return }
            for response in SSDP.responses(for: target, udn: self.udn, location: self.location) {
                message.reply(content: Data(response.utf8))
            }
        }
        group.stateUpdateHandler = { [weak self] state in
            self?.onStateChange?(state)
            if case .ready = state { self?.announce(alive: true) }
        }
        group.start(queue: queue)
        self.group = group

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 30, repeating: 300)
        timer.setEventHandler { [weak self] in self?.announce(alive: true) }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        announce(alive: false)
        let group = self.group
        self.group = nil
        queue.asyncAfter(deadline: .now() + 0.3) { group?.cancel() }
    }

    private func announce(alive: Bool) {
        guard let group else { return }
        for target in SSDP.targets(udn: udn) {
            let message = SSDP.notify(nt: target.nt, usn: target.usn, location: location, alive: alive)
            group.send(content: Data(message.utf8)) { _ in }
        }
    }
}
