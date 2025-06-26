import Foundation
import NabtoWebRTC

public protocol MessageTransportObserver: AnyObject {
    func messageTransport(_ transport: MessageTransport, didGet message: WebrtcSignalingMessage)
    func messageTransport(_ transport: MessageTransport, didError error: Error)
    func messageTransport(_ transport: MessageTransport, didFinishSetup iceServers: [SignalingIceServer])
}

public protocol MessageTransport {
    func sendWebrtcSignalingMessage(_ message: WebrtcSignalingMessage) throws
    func addObserver(_ observer: MessageTransportObserver)
    func removeObserver(_ observer: MessageTransportObserver)
}

public struct ClientMessageTransportSharedSecretOptions {
    public var sharedSecret: String
    public var keyId: String?
}

public enum ClientMessageTransportOptions {
    case none
    case sharedSecret(ClientMessageTransportSharedSecretOptions)
}

public func createClientMessageTransport(client: SignalingClient, options: ClientMessageTransportOptions) throws -> MessageTransport {
    let transport = ClientMessageTransportImpl(client: client, options: options)
    try transport.start()
    return transport
}

public class ClientMessageTransportImpl: MessageTransport {
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
            case .sharedSecret(let sharedSecretOptions):
                self.messageSigner = JWTMessageSigner(sharedSecret: sharedSecretOptions.sharedSecret, keyId: sharedSecretOptions.keyId)
        }
    }

    public func start() throws {
        client.addObserver(self)
        try sendSignalingMessage(SignalingSetupRequest())
    }

    public func close() {
        client.removeObserver(self)
    }

    public func addObserver(_ observer: any MessageTransportObserver) {
        let id = ObjectIdentifier(observer)
        observations[id] = Observation(observer: observer)
    }

    public func removeObserver(_ observer: any MessageTransportObserver) {
        let id = ObjectIdentifier(observer)        
        observations.removeValue(forKey: id)
    }

    public func sendWebrtcSignalingMessage(_ message: WebrtcSignalingMessage) throws {
        if let candidate = message.candidate {
            try sendSignalingMessage(candidate)
        } else if let description = message.description {
            try sendSignalingMessage(description)
        }
    }

    private func sendSignalingMessage(_ message: SignalingMessage) throws {
        let encoded = message.toJson()
        let signed = try messageSigner.signMessage(encoded)
        client.sendMessage(signed)
    }

    private func handleMessage(_ message: JSONValue) {
        do {
            let verified = try messageSigner.verifyMessage(message)
            let decoded = SignalingMessageUnion.fromJson(verified)
            switch state {
                case .setup:
                    if decoded.setupResponse != nil {
                        self.state = .signaling
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
        handleMessage(message)
    }

    public func signalingClient(_ client: any SignalingClient, didChannelStateChange channelState: SignalingChannelState) {
        
    }

    public func signalingClient(_ client: any SignalingClient, didError error: any Error) {
        
    }

    public func signalingClientDidSignalingReconnect(_ client: any SignalingClient) {
        
    }
}
