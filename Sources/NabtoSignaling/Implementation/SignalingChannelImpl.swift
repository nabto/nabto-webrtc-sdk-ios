class SignalingChannelImpl: SignalingChannel {
    struct Observation {
        weak var observer: SignalingChannelObserver?
    }

    private var observations = [ObjectIdentifier: Observation]()
    public var channelId: String = ""

    var channelState: SignalingChannelState = .new {
        didSet { notifyChannelState() }
    }

    init(signalingClient: SignalingClientImpl, channelId: String) {

    }

    func sendMessage(_ msg: String) {
        
    }

    func sendError(errorCode: String, errorMessage: String) {
        
    }

    func checkAlive() {
        
    }

    func handleWebSocketConnect(wasReconnected: Bool) {
        // @TODO
    }

    func close() {
        
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