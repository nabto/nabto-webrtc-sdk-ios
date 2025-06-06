import Foundation

struct ReliabilityData: Codable {
    enum MessageType: String, Codable {
        case ack = "ACK"
        case data = "DATA"
    }

    let type: MessageType
    let seq: Int
    let data: JSONValue?
}

protocol ReliabilityHandler: AnyObject {
    func sendRoutingMessage(_ msg: ReliabilityData)
}

class Reliability {
    private var unackedMessages: [ReliabilityData] = []
    private var recvSeq = 0
    private var sendSeq = 0
    private weak var handler: ReliabilityHandler?

    init(handler: ReliabilityHandler) {
        self.handler = handler
    }

    func sendReliableMessage(_ data: JSONValue) {
        let encoded = ReliabilityData(
            type: .data,
            seq: sendSeq,
            data: data
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

    func handleRoutingMessage(_ message: ReliabilityData) -> JSONValue? {
        if message.type == .ack {
            handleAck(message)
            return nil
        } else {
            return handleReliabilityMessage(message)
        }
    }

    private func handleReliabilityMessage(_ message: ReliabilityData) -> JSONValue? {
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
        return message.data
    }

    private func handleAck(_ ack: ReliabilityData) {
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
        let ack = ReliabilityData(type: .ack, seq: seq, data: nil)
        handler?.sendRoutingMessage(ack)
    }
}
