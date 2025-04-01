enum SignalingClientError: Error {
    case connectError(String)
}

class SignalingClientImpl: SignalingClient, WebSocketObserver {
    struct Observation {
        weak var observer: SignalingClientObserver?
    }

    private var observations = [ObjectIdentifier: Observation]()
    private var closed = false
    private var endpointUrl: String
    private var productId: String
    private var deviceId: String
    
    private var reconnectCounter = 0
    private var openedWebSockets = 0

    var connectionState: SignalingConnectionState = .new { didSet { notifyConnectionState() } }
    var backend: Backend
    var webSocket = WebSocketConnection()
    var signalingChannel_: SignalingChannelImpl! = nil
    var signalingChannel: SignalingChannel! { get { self.signalingChannel_ } }

    init(endpointUrl: String, productId: String, deviceId: String) {
        self.endpointUrl = endpointUrl
        self.productId = productId
        self.deviceId = deviceId

        self.backend = Backend(endpointUrl: endpointUrl, productId: productId, deviceId: deviceId)
        self.signalingChannel_ = SignalingChannelImpl(signalingClient: self, channelId: "not_connected")
    }

    func connect() async throws {
        try await doConnect(accessToken: nil)
    }

    func connect(accessToken: String) async throws {
        try await doConnect(accessToken: accessToken)
    }

    func doConnect(accessToken: String?) async throws {
        if (connectionState != .new) {
            throw SignalingClientError.connectError("SignalingClient.connect can only be called once!")
        }

        connectionState = .connecting
        let response = try await backend.doClientConnect(accessToken)
        
        signalingChannel_.channelId = response.channelId
        if response.deviceOnline ?? false {
            signalingChannel_.channelState = .online
        }

        webSocket.connect(self.endpointUrl, observer: self)
    }

    func close() {
        if closed { return }
        closed = true
        signalingChannel_.close()
        webSocket.close()
        connectionState = .closed
    }


    func socket(_ ws: WebSocketConnection, didGetMessage channelId: String, message: String, authorized: Bool) {
        // Signaling channel handle routing message
        fatalError("NOT IMPLEMENTED")
    }

    func socket(_ ws: WebSocketConnection, didPeerConnect channelId: String) {
        // Signaling channel handle peer connected
        fatalError("NOT IMPLEMENTED")
    }

    func socket(_ ws: WebSocketConnection, didConnectionError channelId: String, errorCode: String) {
        // Signaling channel handle peer offline
        fatalError("NOT IMPLEMENTED")
    }

    func socket(_ ws: WebSocketConnection, didCloseOrError channelId: String) {
        // Signaling channel handle error
        fatalError("NOT IMPLEMENTED")
    }

    func socketDidOpen(_ ws: WebSocketConnection) {
        reconnectCounter = 0
        openedWebSockets += 1
        signalingChannel_.handleWebSocketConnect(wasReconnected: openedWebSockets > 1)
        connectionState = .connected
    }

    private func notifyConnectionState() {
        for (id, observation) in observations {
            guard let observer = observation.observer else {
                observations.removeValue(forKey: id)
                continue
            }

            observer.signalingClient(self, didConnectionStateChange: self.connectionState)
        }
    }

    func addObserver(_ observer: SignalingClientObserver) {
        let id = ObjectIdentifier(observer)
        observations[id] = Observation(observer: observer)
    }

    func removeObserver(_ observer: SignalingClientObserver) {
        let id = ObjectIdentifier(observer)
        observations.removeValue(forKey: id)
    }
}