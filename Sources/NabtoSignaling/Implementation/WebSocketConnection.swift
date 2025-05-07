import Foundation

protocol WebSocketObserver: AnyObject {
    func socket(_ ws: WebSocketConnection, didGetMessage channelId: String, message: String, authorized: Bool)
    func socket(_ ws: WebSocketConnection, didPeerConnect channelId: String)
    func socket(_ ws: WebSocketConnection, didPeerDisconnect channelId: String)
    func socket(_ ws: WebSocketConnection, didConnectionError channelId: String, errorCode: String)
    func socket(_ ws: WebSocketConnection, didCloseOrError channelId: String)
    func socketDidOpen(_ ws: WebSocketConnection)
}

struct RoutingMessage: Codable {
    enum RoutingMessageType: String, Codable {
        case message = "MESSAGE"
        case error = "ERROR"
        case peerConnected = "PEER_CONNECTED"
        case peerOffline = "PEER_OFFLINE"
        case ping = "PING"
        case pong = "PONG"
    }

    var type: RoutingMessageType
    var channelId: String?
    var message: String?
    var authorized: Bool?
    var errorCode: String?
    var errorMessage: String?
}

class WebSocketConnection: NSObject, URLSessionDelegate, URLSessionWebSocketDelegate {
    weak var observer: WebSocketObserver?
    private var socket: URLSessionWebSocketTask? = nil
    private var isConnected = false
    private var pongCounter = 0

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        isConnected = true
        self.observer?.socketDidOpen(self)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isConnected = false
        self.observer?.socket(self, didCloseOrError: "closed")
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCompleteWithError error: Error?) {
        if error != nil {
            // @TODO: sending "error" seems incorrect? review this later
            self.observer?.socket(self, didCloseOrError: "error")
        }   
    }

    func connect(_ endpoint: String, observer: WebSocketObserver) {
        self.observer = observer
        let urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
        socket = urlSession.webSocketTask(with: URL(string: endpoint)!)
        socket?.resume()
        Task { await receiveMessage() }
    }

    func close() {
        socket?.cancel(with: .goingAway, reason: nil)
    }

    func sendMessage(_ channelId: String, _ message: String) {
        let routingMessage = RoutingMessage(
            type: .message,
            channelId: channelId,
            message: message
        )
        send(routingMessage)
    }

    func sendError(_ channelId: String, _ errorCode: String, _ errorMessage: String = "") {
        let routingMessage = RoutingMessage(
            type: .message,
            channelId: channelId,
            errorCode: errorCode,
            errorMessage: errorMessage
        )
        send(routingMessage)
    }

    func sendPing() {
        let routingMessage = RoutingMessage(type: .ping)
        send(routingMessage)
    }

    func sendPong() {
        let routingMessage = RoutingMessage(type: .pong)
        send(routingMessage)
    }

    func checkAlive(timeout: Int) {
        // @TODO
    }

    private func receiveMessage() async {
        var isActive = true
        while isActive && socket?.closeCode == .invalid {
            do {
                let maybeMessage = try await socket?.receive()

                if let message = maybeMessage {
                    switch message {
                        case let .string(string):
                            handleIncomingMessage(string)
                        case let .data(data):
                            if let string = String(data: data, encoding: .utf8) {
                                handleIncomingMessage(string)
                            }
                        @unknown default:
                            print("Unknown message received!")
                    }
                }
            } catch {
                // @TODO: print error?
                isActive = false
            }
        }
    }

    private func handleIncomingMessage(_ msg: String) {
        do {
            let jsonDecoder = JSONDecoder()
            let routingMessage = try jsonDecoder.decode(RoutingMessage.self, from: msg.data(using: .utf8)!)

            switch routingMessage.type {
                case .message:
                    observer?.socket(self, didGetMessage: routingMessage.channelId!, message: routingMessage.message!, authorized: routingMessage.authorized ?? false)
                case .error:
                    observer?.socket(self, didConnectionError: routingMessage.channelId!, errorCode: routingMessage.errorCode!)
                case .peerConnected:
                    observer?.socket(self, didPeerConnect: routingMessage.channelId!)
                case .peerOffline:
                    observer?.socket(self, didPeerDisconnect: routingMessage.channelId!)
                case .ping:
                    sendPong()
                case .pong:
                    pongCounter += 1

            }
        } catch {
            // @TODO
        }
    }

    private func send(_ msg: RoutingMessage) {
        if (!isConnected) {
            return
        }

        let encoder = JSONEncoder()
        do {
            let jsonData = try encoder.encode(msg)
            let json = String(data: jsonData, encoding: .utf8)!
            let webSocketMessage = URLSessionWebSocketTask.Message.string(json)
            socket?.send(webSocketMessage) { error in
                 if let error = error {
                    // @TODO: Error handling
                    print("Failed to send websocket message: \(error)")
                 }
            }
        } catch {
            // @TODO: error handling
            print("Failed to send websocket message: \(error)")
        }
    }
}
