import Foundation
import NabtoWebRTC

@globalActor
fileprivate actor ClientMessageTransportActor: GlobalActor {
    static let shared = ClientMessageTransportActor()
}

class ClientMessageTransportImpl: MessageTransport {
    struct Observation {
        weak var observer: MessageTransportObserver?
    }

    enum State {
        case setup, signaling
    }

    private let observerLock = NSLock()
    private var observations = [ObjectIdentifier: Observation]()
    private var state = State.setup
    private let client: SignalingClient
    private let messageSigner: MessageSigner

    internal init(client: SignalingClient, options: ClientMessageTransportOptions) {
        self.client = client
        switch options {
            case .none:
                self.messageSigner = NoneMessageSigner()
            case .sharedSecret(let sharedSecret, let keyId):
                self.messageSigner = JWTMessageSigner(sharedSecret: sharedSecret, keyId: keyId)
        }
    }

    public func start() {
        client.addObserver(self)
        Task {
            do {
                try await sendSignalingMessage(SignalingSetupRequest())
            } catch {
                notifyError(error)
            }
        }
    }

    public func close() {
        client.removeObserver(self)
    }

    public func addObserver(_ observer: any MessageTransportObserver) {
        observerLock.withLock {
            let id = ObjectIdentifier(observer)
            observations[id] = Observation(observer: observer)
        }
    }

    public func removeObserver(_ observer: any MessageTransportObserver) {
        observerLock.withLock {
            let id = ObjectIdentifier(observer)
            observations.removeValue(forKey: id)
        }
    }

    public func sendWebrtcSignalingMessage(_ message: WebrtcSignalingMessage) {
        Task {
            do {
                if let candidate = message.candidate {
                    try await sendSignalingMessage(candidate)
                } else if let description = message.description {
                    try await sendSignalingMessage(description)
                }
            } catch {
                notifyError(error)
            }
        }
    }

    @ClientMessageTransportActor
    private func sendSignalingMessage(_ message: SignalingMessage) async throws {
        let encoded = message.toJson()
        let signed = try messageSigner.signMessage(encoded)
        client.sendMessage(signed)
    }

    @ClientMessageTransportActor
    private func handleMessage(_ message: JSONValue) async {
        do {
            let verified = try messageSigner.verifyMessage(message)
            let decoded = SignalingMessageUnion.fromJson(verified)
            switch state {
                case .setup:
                    if let setupResponse = decoded.setupResponse {
                        self.state = .signaling
                        notifySetupDone(setupResponse.iceServers)
                        return
                    }
                case .signaling:
                    if let candidate = decoded.candidate {
                        notifyMessage(WebrtcSignalingMessage(candidate: candidate))
                        return
                    }

                    if let description = decoded.description {
                        notifyMessage(WebrtcSignalingMessage(description: description))
                        return
                    }
            }
        } catch {
            notifyError(error)
        }
    }

    private func notify(code: (_ observer: any MessageTransportObserver) -> Void) {
        for (id, observation) in observations {
            guard let observer = observation.observer else {
                observations.removeValue(forKey: id)
                continue
            }
            code(observer)
        }
    }

    private func notifyError(_ error: Error) {
        notify { obs in obs.messageTransport(self, didError: error) }
    }

    private func notifyMessage(_ message: WebrtcSignalingMessage) {
        notify { obs in obs.messageTransport(self, didGet: message) }
    }

    private func notifySetupDone(_ iceServers: [SignalingIceServer]) {
        notify { obs in obs.messageTransport(self, didFinishSetup: iceServers) }
    }
}

extension ClientMessageTransportImpl: SignalingClientObserver {
    public func signalingClient(_ client: any SignalingClient, didConnectionStateChange connectionState: SignalingConnectionState) {
        
    }

    public func signalingClient(_ client: any SignalingClient, didGetMessage message: JSONValue) {
        Task { await handleMessage(message) }
    }

    public func signalingClient(_ client: any SignalingClient, didChannelStateChange channelState: SignalingChannelState) {
        
    }

    public func signalingClient(_ client: any SignalingClient, didError error: any Error) {
        
    }

    public func signalingClientDidConnectionReconnect(_ client: any SignalingClient) {
        
    }
}
