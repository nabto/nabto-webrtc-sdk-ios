import Foundation

struct ReliabilityMessage: Codable {
    enum MessageType: String, Codable {
        case ack = "ACK"
        case message = "MESSAGE"
    }

    let type: MessageType
    let seq: Int
    let message: String?

    static func fromJson(_ json: String) throws -> ReliabilityMessage {
        return try JSONDecoder().decode(ReliabilityMessage.self, from: json.data(using: .utf8)!)
    }

    static func toJson(_ msg: ReliabilityMessage) -> String {
        return String(data: try! JSONEncoder().encode(msg), encoding: .utf8)!
    }
}

protocol ReliabilityHandler: AnyObject {
    func sendRoutingMessage(_ msg: ReliabilityMessage)
}

class Reliability {
    private var unackedMessages: [ReliabilityMessage] = []
    private var recvSeq = 0
    private var sendSeq = 0
    private weak var handler: ReliabilityHandler?

    init(handler: ReliabilityHandler) {
        self.handler = handler
    }

    func sendReliableMessage(_ message: String) {
        let encoded = ReliabilityMessage(
            type: .message,
            seq: sendSeq,
            message: message
        )
        sendSeq += 1
        unackedMessages.append(encoded)
        handler?.sendRoutingMessage(encoded)
    }

    func handlePeerConnected() {
        sendUnackedMessages()
    }

    func handleConnect() {
        sendUnackedMessages()
    }

    func handleRoutingMessage(_ message: ReliabilityMessage) -> String? {
        if message.type == .ack {
            handleAck(message)
            return nil
        } else {
            return handleReliabilityMessage(message)
        }
    }

    private func handleReliabilityMessage(_ message: ReliabilityMessage) -> String? {
        if message.seq <= recvSeq {
            // Message was expected or retransmitted
            sendAck(message.seq)
        }

        if message.seq != recvSeq {
            // Message is out of order
            // @TODO: Logging
            return nil
        }

        recvSeq += 1
        return message.message
    }

    private func handleAck(_ ack: ReliabilityMessage) {
        if let first = unackedMessages.first { 
            if first.seq == ack.seq {
                unackedMessages.remove(at: 0)
            } else {
                // @TODO logging
            }
        } else {
            // @TODO: Log that ACK was received but unacked messages is empty
        }
    }

    private func sendUnackedMessages() {
        for msg in unackedMessages {
            handler?.sendRoutingMessage(msg)
        }
    }

    private func sendAck(_ seq: Int) {
        let ack = ReliabilityMessage(type: .ack, seq: seq, message: nil)
        handler?.sendRoutingMessage(ack)
    }
}
