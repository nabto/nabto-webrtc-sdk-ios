import Foundation
import NabtoWebRTC

actor ClientMessageTransportImpl: MessageTransport {
    struct Observation {
        weak var observer: MessageTransportObserver?
    }

    enum State {
        case setup, signaling
    }

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

    public func start() async throws {
        await client.addObserver(self)
        try await sendSignalingMessage(SignalingSetupRequest())
    }

    public func close() async {
        await client.removeObserver(self)
    }

    public func addObserver(_ observer: any MessageTransportObserver) {
        let id = ObjectIdentifier(observer)
        observations[id] = Observation(observer: observer)
    }

    public func removeObserver(_ observer: any MessageTransportObserver) {
        let id = ObjectIdentifier(observer)
        observations.removeValue(forKey: id)
    }

    public func sendWebrtcSignalingMessage(_ message: WebrtcSignalingMessage) async throws {
        if let candidate = message.candidate {
            try await sendSignalingMessage(candidate)
        } else if let description = message.description {
            try await sendSignalingMessage(description)
        }
    }

    private func sendSignalingMessage(_ message: SignalingMessage) async throws {
        let encoded = message.toJson()
        let signed = try messageSigner.signMessage(encoded)
        await client.sendMessage(signed)
    }

    private func handleMessage(_ message: JSONValue) async {
        do {
            let verified = try messageSigner.verifyMessage(message)
            let decoded = SignalingMessageUnion.fromJson(verified)
            switch state {
                case .setup:
                    if let setupResponse = decoded.setupResponse {
                        self.state = .signaling
                        await notifySetupDone(setupResponse.iceServers)
                        return
                    }
                case .signaling:
                    if let candidate = decoded.candidate {
                        await notifyMessage(WebrtcSignalingMessage(candidate: candidate))
                        return
                    }

                    if let description = decoded.description {
                        await notifyMessage(WebrtcSignalingMessage(description: description))
                        return
                    }
            }
        } catch {
            await notifyError(error)
        }
    }

    private func notifyError(_ error: Error) async {
        for (id, observation) in observations {
            guard let observer = observation.observer else {
                observations.removeValue(forKey: id)
                continue
            }
            await observer.messageTransport(self, didError: error)
        }
    }

    private func notifyMessage(_ message: WebrtcSignalingMessage) async {
        for (id, observation) in observations {
            guard let observer = observation.observer else {
                observations.removeValue(forKey: id)
                continue
            }
            await observer.messageTransport(self, didGet: message)
        }
    }

    private func notifySetupDone(_ iceServers: [SignalingIceServer]) async {
        for (id, observation) in observations {
            guard let observer = observation.observer else {
                observations.removeValue(forKey: id)
                continue
            }
            await observer.messageTransport(self, didFinishSetup: iceServers)
        }
    }
}

extension ClientMessageTransportImpl: SignalingClientObserver {
    public func signalingClient(_ client: any SignalingClient, didConnectionStateChange connectionState: SignalingConnectionState) async {
        
    }

    public func signalingClient(_ client: any SignalingClient, didGetMessage message: JSONValue) async {
        await handleMessage(message)
    }

    public func signalingClient(_ client: any SignalingClient, didChannelStateChange channelState: SignalingChannelState) async {
        
    }

    public func signalingClient(_ client: any SignalingClient, didError error: any Error) async {
        
    }

    public func signalingClientDidConnectionReconnect(_ client: any SignalingClient) async {
        
    }
}
