import Dispatch

let CHECK_ALIVE_TIMEOUT = 1000.0

class SignalingClientImpl: SignalingClient, ReliabilityHandler {
    struct Observation {
        weak var observer: SignalingClientObserver?
    }

    var connectionState: SignalingConnectionState = .new
    var channelState: SignalingChannelState = .new

    private var observations = [ObjectIdentifier: Observation]()
    private var closed = false
    private var endpointUrl: String
    private var productId: String
    private var deviceId: String
    private var signalingUrl: String?
    private var requireOnline: Bool
    private var accessToken: String?
    private var backend: Backend

    private var reliabilityLayer: Reliability! = nil
    private var webSocket = WebSocketConnection()
    private var connectionId = "";

    private var isReconnecting = false
    private var reconnectCounter = 0
    private var openedWebSockets = 0

    init(endpointUrl: String, productId: String, deviceId: String, requireOnline: Bool, accessToken: String?) {
        self.endpointUrl = endpointUrl
        self.productId = productId
        self.deviceId = deviceId
        self.requireOnline = requireOnline
        self.accessToken = accessToken

        self.backend = Backend(endpointUrl: endpointUrl, productId: productId, deviceId: deviceId)
        self.reliabilityLayer = Reliability(handler: self)
    }

    private func setConnectionState(_ state: SignalingConnectionState) async {
        connectionState = state
        await notifyConnectionState()
    }

    private func setChannelState(_ state: SignalingChannelState) async {
        channelState = state
        await notifyChannelState()
    }

    func start() async throws {
        if (connectionState != .new) {
            throw SignalingClientError.connectError("SignalingClient.connect can only be called once!")
        }
        await setConnectionState(.connecting)

        let response: ClientConnectResponse
        do {
            response = try await backend.doClientConnect(accessToken)
        } catch {
            await handleError(error)
            return
        }
        
        self.connectionId = response.channelId
        if let deviceOnline = response.deviceOnline {
            await setChannelState(deviceOnline ? .connected : .disconnected)
        }

        if self.requireOnline && self.channelState != .connected {
            await handleError(SignalingClientError.connectError("The requested device is not online, try again later."))
        }

        self.signalingUrl = response.signalingUrl
        webSocket.connect(response.signalingUrl, observer: self)
    }

    func close() async {
        if closed { return }
        closed = true

        await sendError(.init(
            errorCode: SignalingErrorCode.channelClosed,
            errorMessage: "Signaling client channel was closed"
        ))
        webSocket.close()
        await setConnectionState(.closed)
        await setChannelState(.disconnected)
    }

    func sendRoutingMessage(_ msg: ReliabilityData) {
        webSocket.sendMessage(self.connectionId, msg)
    }

    func sendMessage(_ msg: JSONValue) async {
        await reliabilityLayer.sendReliableMessage(msg)
    }

    func sendError(_ error: SignalingError) async {
        webSocket.sendError(self.connectionId, error)
    }

    func checkAlive() async {
        await self.webSocket.checkAlive(timeout: CHECK_ALIVE_TIMEOUT)
    }

    func handleWebSocketConnect(wasReconnected: Bool) async {
        if channelState == .closed || channelState == .failed {
            return
        }
        await reliabilityLayer.handleConnect()
        if wasReconnected {
            await notifySignalingReconnect()
        }
    }

    func handlePeerConnected() async {
        await setChannelState(.connected)
        await reliabilityLayer.handlePeerConnected()
    }

    func handlePeerOffline() async {
        await setChannelState(.disconnected)
    }

    func handleRoutingMessage(_ message: ReliabilityData) async {
        let reliableMessage = await reliabilityLayer.handleRoutingMessage(message)
        if let msg = reliableMessage {
            await notifyMessage(msg)
        }
    }

    func handleError(_ error: Error) async {
        if channelState == .closed || channelState == .failed {
            return
        }
        await setConnectionState(.failed)
        await notifyError(error)
    }

    private func reconnect() async {
        if connectionState == .failed || connectionState == .closed {
            return
        }

        isReconnecting = true
        await setConnectionState(.connecting)

        if let url = self.signalingUrl {
            webSocket.connect(url, observer: self)
        }
    }

    private func waitReconnect() async {
        if connectionState == .failed || connectionState == .closed {
            return
        }

        if connectionState == .waitRetry {
            return
        }

        if reconnectCounter > 7 {
            isReconnecting = false
            await setConnectionState(.failed)
            return
        }

        await setConnectionState(.waitRetry)
        let reconnectWait =  (1 << reconnectCounter)
        reconnectCounter += 1

        Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(reconnectWait * 1000000000))
                await self.reconnect()
            } catch {
                // @TODO: Logging
            }
        }
    }

    private func notifyConnectionState() async {
        for (id, observation) in observations {
            guard let observer = observation.observer else {
                observations.removeValue(forKey: id)
                continue
            }

            await observer.signalingClient(self, didConnectionStateChange: self.connectionState)
        }
    }

    private func notifyChannelState() async {
        for (id, observation) in observations {
            guard let observer = observation.observer else {
                observations.removeValue(forKey: id)
                continue
            }

            await observer.signalingClient(self, didChannelStateChange: self.channelState)
        }
    }

    private func notifySignalingReconnect() async {
        for (id, observation) in observations {
            guard let observer = observation.observer else {
                observations.removeValue(forKey: id)
                continue
            }

            await observer.signalingClientDidConnectionReconnect(self)
        }
    }

    private func notifyError(_ error: Error) async {
        for (id, observation) in observations {
            guard let observer = observation.observer else {
                observations.removeValue(forKey: id)
                continue
            }

            await observer.signalingClient(self, didError: error)
        }
    }

    private func notifyMessage(_ message: JSONValue) async {
        for (id, observation) in observations {
            guard let observer = observation.observer else {
                observations.removeValue(forKey: id)
                continue
            }

            await observer.signalingClient(self, didGetMessage: message)
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

extension SignalingClientImpl: WebSocketObserver {
    func socketDidOpen(_ ws: WebSocketConnection) async {
        reconnectCounter = 0
        openedWebSockets += 1
        await handleWebSocketConnect(wasReconnected: openedWebSockets > 1)
        await setConnectionState(.connected)
    }

    func socket(_ ws: WebSocketConnection, didGetMessage channelId: String, message: ReliabilityData, authorized: Bool) async {
        await handleRoutingMessage(message)
    }

    func socket(_ ws: WebSocketConnection, didPeerConnect channelId: String) async {
        await handlePeerConnected()
    }

    func socket(_ ws: WebSocketConnection, didPeerDisconnect channelId: String) async {
        await handlePeerOffline()
    }

    func socket(_ ws: WebSocketConnection, didConnectionError channelId: String, errorCode: String, errorMessage: String) async {
        let err = SignalingError(errorCode: .from(string: errorCode), errorMessage: errorMessage)
        await handleError(err)
    }

    func socket(_ ws: WebSocketConnection, didCloseOrError channelId: String) async {
        if connectionState == .failed || connectionState == .closed {
            return
        }

        if openedWebSockets == 0 {
            await handleError(SignalingClientError.runtimeError("The websocket was closed before it opened."))
        } else {
            await waitReconnect()
        }
    }
}
