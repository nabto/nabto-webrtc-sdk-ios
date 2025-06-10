import Dispatch

let CHECK_ALIVE_TIMEOUT = 1000.0

class SignalingClientImpl: SignalingClient, WebSocketObserver, ReliabilityHandler {
    struct Observation {
        weak var observer: SignalingClientObserver?
    }

    var connectionState: SignalingConnectionState = .new { didSet { notifyConnectionState() } }
    var channelState: SignalingChannelState = .new { didSet { notifyChannelState() } }

    private var observations = [ObjectIdentifier: Observation]()
    private var closed = false
    private var endpointUrl: String
    private var productId: String
    private var deviceId: String
    private var signalingUrl: String?
    private var requireOnline: Bool
    private var backend: Backend

    private var reliabilityLayer: Reliability! = nil
    private var webSocket = WebSocketConnection()
    private var connectionId = "";

    private var handlingReceivedMessages = false
    private var receivedMessages: [JSONValue?] = []

    private var isReconnecting = false
    private var reconnectCounter = 0
    private var openedWebSockets = 0

    init(endpointUrl: String, productId: String, deviceId: String, requireOnline: Bool) {
        self.endpointUrl = endpointUrl
        self.productId = productId
        self.deviceId = deviceId
        self.requireOnline = requireOnline

        self.backend = Backend(endpointUrl: endpointUrl, productId: productId, deviceId: deviceId)
        self.reliabilityLayer = Reliability(handler: self)
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
        
        self.connectionId = response.channelId
        if let deviceOnline = response.deviceOnline {
            self.channelState = deviceOnline ? .online : .offline
        }

        if self.requireOnline && self.channelState != .online {
            throw SignalingClientError.connectError("The requested device is not online, try again later.")
        }

        self.signalingUrl = response.signalingUrl
        webSocket.connect(response.signalingUrl, observer: self)
    }

    func close() {
        if closed { return }
        closed = true

        sendError(
            errorCode: "CHANNEL_CLOSED",
            errorMessage: "Signaling client channel was closed"
        )
        webSocket.close()
        connectionState = .closed
        channelState = .offline
    }

    func sendRoutingMessage(_ msg: ReliabilityData) {
        webSocket.sendMessage(self.connectionId, msg)
    }


    func sendMessage(_ msg: JSONValue) {
        reliabilityLayer.sendReliableMessage(msg)
    }

    func sendError(errorCode: String, errorMessage: String) {
        webSocket.sendError(self.connectionId, errorCode)
    }

    func socket(_ ws: WebSocketConnection, didGetMessage channelId: String, message: ReliabilityData, authorized: Bool) {
        handleRoutingMessage(message)
    }

    func socket(_ ws: WebSocketConnection, didPeerConnect channelId: String) {
        handlePeerConnected()
    }

    func socket(_ ws: WebSocketConnection, didPeerDisconnect channelId: String) {
        handlePeerOffline()
    }

    func socket(_ ws: WebSocketConnection, didConnectionError channelId: String, errorCode: String, errorMessage: String) {
        if let code = SignalingErrorCode(rawValue: errorCode) {
            let err = SignalingError(errorCode: code, errorMessage: errorMessage)
            handleError(err)
        }
    }

    func checkAlive() {
        self.webSocket.checkAlive(timeout: CHECK_ALIVE_TIMEOUT)
    }

    func socket(_ ws: WebSocketConnection, didCloseOrError channelId: String) {
        if connectionState == .failed || connectionState == .closed {
            return
        }

        if openedWebSockets == 0 {
            handleError(SignalingClientError.runtimeError("The websocket was closed before it opened."))
        } else {
            waitReconnect()
        }
    }

    func socketDidOpen(_ ws: WebSocketConnection) {
        reconnectCounter = 0
        openedWebSockets += 1
        handleWebSocketConnect(wasReconnected: openedWebSockets > 1)
        connectionState = .connected
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

    func handlePeerConnected() {
        channelState = .online
        reliabilityLayer.handlePeerConnected()
    }

    func handlePeerOffline() {
        channelState = .offline
    }

    func handleRoutingMessage(_ message: ReliabilityData) {
        let reliableMessage = reliabilityLayer.handleRoutingMessage(message)
        receivedMessages.append(reliableMessage)
        handleReceivedMessages()
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

    func handleError(_ error: Error) {
        if channelState == .closed || channelState == .failed {
            return
        }
        notifyError(error)
    }

    private func reconnect() {
        if connectionState == .failed || connectionState == .closed {
            return
        }

        isReconnecting = true
        connectionState = .connecting

        if let url = self.signalingUrl {
            webSocket.connect(url, observer: self)
        }
    }

    private func waitReconnect() {
        if connectionState == .failed || connectionState == .closed {
            return
        }

        if connectionState == .waitRetry {
            return
        }

        if reconnectCounter > 7 {
            isReconnecting = false
            connectionState = .failed
            return
        }

        connectionState = .waitRetry
        let reconnectWait =  (1 << reconnectCounter)
        reconnectCounter += 1

        DispatchQueue.main.asyncAfter(deadline: .now() + Double(reconnectWait)) {
            self.reconnect()
        }
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

    private func notifyChannelState() {
        for (id, observation) in observations {
            guard let observer = observation.observer else {
                observations.removeValue(forKey: id)
                continue
            }

            observer.signalingClient(self, didChannelStateChange: self.channelState)
        }
    }

    private func notifySignalingReconnect() {
        for (id, observation) in observations {
            guard let observer = observation.observer else {
                observations.removeValue(forKey: id)
                continue
            }

            observer.signalingClientDidSignalingReconnect(self)
        }
    }

    private func notifyError(_ error: Error) {
        for (id, observation) in observations {
            guard let observer = observation.observer else {
                observations.removeValue(forKey: id)
                continue
            }

            observer.signalingClient(self, didError: error)
        }
    }

    private func notifyMessage(_ message: JSONValue) {
        for (id, observation) in observations {
            guard let observer = observation.observer else {
                observations.removeValue(forKey: id)
                continue
            }

            observer.signalingClient(self, didGetMessage: message)
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