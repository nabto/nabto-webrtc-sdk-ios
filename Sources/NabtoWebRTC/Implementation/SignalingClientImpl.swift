let CHECK_ALIVE_TIMEOUT = 1000.0

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
    private var requireOnline: Bool
    
    private var reconnectCounter = 0
    private var openedWebSockets = 0

    var connectionState: SignalingConnectionState = .new { didSet { notifyConnectionState() } }
    var backend: Backend
    var webSocket = WebSocketConnection()
    var signalingChannel_: SignalingChannelImpl! = nil
    var signalingChannel: SignalingChannel! { get { self.signalingChannel_ } }

    init(endpointUrl: String, productId: String, deviceId: String, requireOnline: Bool) {
        self.endpointUrl = endpointUrl
        self.productId = productId
        self.deviceId = deviceId
        self.requireOnline = requireOnline

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
        if let deviceOnline = response.deviceOnline {
            signalingChannel_.channelState = deviceOnline ? .online : .offline
        }

        if self.requireOnline && signalingChannel_.channelState != .online {
            throw SignalingClientError.connectError("The requested device is not online, try again later.")
        }

        webSocket.connect(response.signalingUrl, observer: self)
    }

    func close() {
        if closed { return }
        closed = true
        signalingChannel_.close()
        webSocket.close()
        connectionState = .closed
    }

    func sendRoutingMessage(channelId: String, message: String) {
        webSocket.sendMessage(channelId, message)
    }

    func sendError(channelId: String, errorCode: String, errorMessage: String) {
        webSocket.sendError(channelId, errorCode)
    }

    func socket(_ ws: WebSocketConnection, didGetMessage channelId: String, message: String, authorized: Bool) {
        signalingChannel_.handleRoutingMessage(message)
    }

    func socket(_ ws: WebSocketConnection, didPeerConnect channelId: String) {
        signalingChannel_.handlePeerConnected()
    }

    func socket(_ ws: WebSocketConnection, didPeerDisconnect channelId: String) {
        signalingChannel_.handlePeerOffline()
    }

    func socket(_ ws: WebSocketConnection, didConnectionError channelId: String, errorCode: String) {
        if let code = SignalingErrorCode(rawValue: errorCode) {
            let err = SignalingError(errorCode: code, errorMessage: "Swift SDK is missing a more detailed error message.") // @TODO
            signalingChannel_.handleError(err)
        }
    }

    func checkAlive() {
        self.webSocket.checkAlive(timeout: CHECK_ALIVE_TIMEOUT)
    }

    func socket(_ ws: WebSocketConnection, didCloseOrError channelId: String) {
        waitReconnect()
    }

    func socketDidOpen(_ ws: WebSocketConnection) {
        reconnectCounter = 0
        openedWebSockets += 1
        signalingChannel_.handleWebSocketConnect(wasReconnected: openedWebSockets > 1)
        connectionState = .connected
    }

    private func waitReconnect() {
        // @TODO
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