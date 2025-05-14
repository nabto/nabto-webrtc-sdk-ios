class SignalingChannelImpl: SignalingChannel, ReliabilityHandler {
    struct Observation {
        weak var observer: SignalingChannelObserver?
    }

    private var observations = [ObjectIdentifier: Observation]()
    private var receivedMessages: [String?] = []
    private var reliabilityLayer: Reliability! = nil
    private var closed = false
    private var handlingReceivedMessages = false
    private weak var signalingClient: SignalingClientImpl?

    var channelId: String
    var channelState: SignalingChannelState = .new { didSet { notifyChannelState() } }

    init(signalingClient: SignalingClientImpl, channelId: String) {
        self.signalingClient = signalingClient
        self.channelId = channelId
        self.reliabilityLayer = Reliability(handler: self)
    }

    func sendRoutingMessage(_ msg: ReliabilityMessage) {
        signalingClient?.sendRoutingMessage(channelId: channelId, message: ReliabilityMessage.toJson(msg))
    }

    func sendMessage(_ msg: String) {
        reliabilityLayer.sendReliableMessage(msg)
    }

    func sendError(errorCode: String, errorMessage: String) {
        signalingClient?.sendError(channelId: channelId, errorCode: errorCode, errorMessage: errorMessage)
    }

    func checkAlive() {
        if channelState == .closed || channelState == .failed {
            return
        }
        signalingClient?.checkAlive()
    }

    func handleWebSocketConnect(wasReconnected: Bool) {
        if channelState == .closed || channelState == .failed {
            return
        }
        reliabilityLayer.handleConnect()
        if wasReconnected {
            notifySignalingReconnect()
        }
    }

    func close() {
        if !closed {
            closed = true
            signalingClient?.sendError(
                channelId: channelId,
                errorCode: "CHANNEL_CLOSED",
                errorMessage: "Signaling client channel was closed"
            )
            signalingClient?.close()
        }
    }

    func handleRoutingMessage(_ message: String) {
        do {
            let parsed = try ReliabilityMessage.fromJson(message)
            let reliableMessage = reliabilityLayer.handleRoutingMessage(parsed)
            receivedMessages.append(reliableMessage)
            handleReceivedMessages()
        } catch {
            // @TODO: Logging
        }
    }

    func handleReceivedMessages() {
        if !handlingReceivedMessages {
            if !receivedMessages.isEmpty {
                handlingReceivedMessages = true
                let msg = receivedMessages.removeFirst()
                if let msg = msg {
                    notifyMessage(msg)
                }
                handlingReceivedMessages = false
                handleReceivedMessages()
            }
        }
    }

    func handlePeerConnected() {
        channelState = .online
        reliabilityLayer.handlePeerConnected()
    }

    func handlePeerOffline() {
        channelState = .offline
    }

    func handleError(_ error: SignalingError) {
        if channelState == .closed || channelState == .failed {
            return
        }
        notifySignalingError(error)
    }

    private func notifyMessage(_ message: String) {
        for (id, observation) in observations {
            guard let observer = observation.observer else {
                observations.removeValue(forKey: id)
                continue
            }

            observer.signalingChannel(self, didGetMessage: message)
        }
    }

    private func notifyChannelState() {
        for (id, observation) in observations {
            guard let observer = observation.observer else {
                observations.removeValue(forKey: id)
                continue
            }

            observer.signalingChannel(self, didChannelStateChange: self.channelState)
        }
    }

    private func notifySignalingReconnect() {
        for (id, observation) in observations {
            guard let observer = observation.observer else {
                observations.removeValue(forKey: id)
                continue
            }

            observer.signalingChannelDidSignalingReconnect(self)
        }
    }

    private func notifySignalingError(_ error: SignalingError) {
        for (id, observation) in observations {
            guard let observer = observation.observer else {
                observations.removeValue(forKey: id)
                continue
            }

            observer.signalingChannel(self, didSignalingError: error)
        }
    }

    func addObserver(_ observer: SignalingChannelObserver) {
        let id = ObjectIdentifier(observer)
        observations[id] = Observation(observer: observer)
    }

    func removeObserver(_ observer: SignalingChannelObserver) {
        let id = ObjectIdentifier(observer)
        observations.removeValue(forKey: id)
    }
}