import Foundation

protocol WebSocketObserver: AnyObject {
    func socket(_ ws: WebSocketConnection, didGetMessage channelId: String, message: ReliabilityData, authorized: Bool) async
    func socket(_ ws: WebSocketConnection, didPeerConnect channelId: String) async
    func socket(_ ws: WebSocketConnection, didPeerDisconnect channelId: String) async
    func socket(_ ws: WebSocketConnection, didConnectionError channelId: String, errorCode: String, errorMessage: String) async
    func socket(_ ws: WebSocketConnection, didCloseOrError channelId: String) async
    func socketDidOpen(_ ws: WebSocketConnection) async
}

struct RoutingMessageError: Codable {
    var code: String
    var message: String?
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
    var message: ReliabilityData?
    var authorized: Bool?
    var error: RoutingMessageError?
}

fileprivate enum SocketEvent {
    case didOpenWithProtocol(protocol: String?)
    case didCloseWith(closeCode: URLSessionWebSocketTask.CloseCode?, reason: Data?)
    case didCompleteWithError(error: (any Error)?)
}

fileprivate typealias WebSocketStream = AsyncThrowingStream<URLSessionWebSocketTask.Message, Error>

fileprivate class SocketStream: AsyncSequence {
    typealias AsyncIterator = WebSocketStream.Iterator
    typealias Element = URLSessionWebSocketTask.Message

    private var continuation: WebSocketStream.Continuation?
    private let task: URLSessionWebSocketTask

    private lazy var stream: WebSocketStream = {
        return WebSocketStream { continuation in
            self.continuation = continuation
            waitForNextValue()
        }
    }()

    private func waitForNextValue() {
        guard task.closeCode == .invalid else {
            continuation?.finish()
            return
        }

        task.receive(completionHandler: { [weak self] result in
            guard let continuation = self?.continuation else {
                return
            }

            do {
                let message = try result.get()
                continuation.yield(message)
                self?.waitForNextValue()
            } catch {
                continuation.finish(throwing: error)
            }
        })
    }

    init(task: URLSessionWebSocketTask) {
        self.task = task
        task.resume()
    }

    deinit {
        continuation?.finish()
    }

    func makeAsyncIterator() -> AsyncIterator {
        return stream.makeAsyncIterator()
    }

    func cancel() async throws {
        task.cancel(with: .goingAway, reason: nil)
        continuation?.finish()
    }
}

class WebSocketConnection: NSObject, URLSessionDelegate, URLSessionWebSocketDelegate {
    weak var observer: WebSocketObserver?
    private var socket: URLSessionWebSocketTask? = nil
    private var isConnected = false
    private var pongCounter = 0

    private typealias EventStream = AsyncStream<SocketEvent>
    private var socketStream: SocketStream?
    private var eventStream: EventStream?
    private var eventContinuation: EventStream.Continuation?

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol prtcl: String?) {
        isConnected = true
        eventContinuation?.yield(.didOpenWithProtocol(protocol: prtcl))
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isConnected = false
        eventContinuation?.yield(.didCloseWith(closeCode: closeCode, reason: reason))
        eventContinuation?.finish()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if error != nil {
            eventContinuation?.yield(.didCompleteWithError(error: error))
            eventContinuation?.finish()
        }
    }

    func connect(_ endpoint: String, observer: WebSocketObserver) async {
        self.observer = observer
        self.eventContinuation?.finish()

        let (stream, cont) = AsyncStream.makeStream(of: SocketEvent.self)
        self.eventStream = stream
        self.eventContinuation = cont

        let urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
        socket = urlSession.webSocketTask(with: URL(string: endpoint)!)
        Task {
            guard let eventStream = eventStream else {
                return
            }

            for await event in eventStream {
                switch event {
                    case .didCloseWith(_, _):
                        // @TODO: Return more data than just "closed"?
                        await self.observer?.socket(self, didCloseOrError: "closed")
                    case .didCompleteWithError(_):
                        // @TODO: Return more data than just "error"?
                        await self.observer?.socket(self, didCloseOrError: "error")
                    case .didOpenWithProtocol(_):
                        await self.observer?.socketDidOpen(self)
                }
            }
        }

        self.socketStream = SocketStream(task: socket!)
        Task {
            guard let stream = self.socketStream else {
                return
            }

            do {
                for try await message in stream {
                    switch message {
                        case let .string(string):
                            await handleIncomingMessage(string)
                        case let .data(data):
                            if let string = String(data: data, encoding: .utf8) {
                                await handleIncomingMessage(string)
                            }
                        @unknown default:
                            Log.webSocket.debug("Unknown message received!")
                    }
                }
            } catch {
                Log.webSocket.error("Failed to handle incoming websocket message: \(error)")
            }
        }
    }

    func close() {
        socket?.cancel(with: .goingAway, reason: nil)
    }

    func sendMessage(_ channelId: String, _ message: ReliabilityData) {
        let routingMessage = RoutingMessage(
            type: .message,
            channelId: channelId,
            message: message
        )
        send(routingMessage)
    }

    func sendError(_ channelId: String, _ error: SignalingError) {
        let routingMessage = RoutingMessage(
            type: .message,
            channelId: channelId,
            error: RoutingMessageError(code: error.errorCode.stringValue, message: error.errorMessage)
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

    func checkAlive(timeout: Double) async {
        let currentPongCounter = self.pongCounter
        sendPing()
        Task {
            let timeoutNanos = UInt64(timeout * 1000000)
            do {
                try await Task.sleep(nanoseconds: timeoutNanos)
                if currentPongCounter == self.pongCounter {
                    await self.observer?.socket(self, didCloseOrError: "timeout")
                }
            } catch {
                Log.webSocket.warning("CheckAlive : \(error)")
            }
        }
    }

    private func handleIncomingMessage(_ msg: String) async {
        do {
            let jsonDecoder = JSONDecoder()
            let routingMessage = try jsonDecoder.decode(RoutingMessage.self, from: msg.data(using: .utf8)!)

            switch routingMessage.type {
                case .message:
                    await observer?.socket(self, didGetMessage: routingMessage.channelId!, message: routingMessage.message!, authorized: routingMessage.authorized ?? false)
                case .error:
                    await observer?.socket(self, didConnectionError: routingMessage.channelId!, errorCode: routingMessage.error!.code, errorMessage: routingMessage.error!.message ?? "Missing detailed error information")
                case .peerConnected:
                    await observer?.socket(self, didPeerConnect: routingMessage.channelId!)
                case .peerOffline:
                    await observer?.socket(self, didPeerDisconnect: routingMessage.channelId!)
                case .ping:
                    sendPong()
                case .pong:
                    pongCounter += 1

            }
        } catch {
            Log.webSocket.error("Failed to handle incoming websocket message: \(error)")
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
                    Log.webSocket.error("Failed to send websocket message: \(error)")
                 }
            }
        } catch {
            Log.webSocket.error("Failed to send websocket message: \(error)")
        }
    }
}
