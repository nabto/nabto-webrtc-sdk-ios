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

    // TODO this function could be called from multiple concurrent threads which could lead to concurrency problems.
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
            Log.reliability.info("Received a message with seq \(message.seq), the expected recvSeq is \(self.recvSeq). This is expected on initial connect or on reconnect.")
            return nil
        }

        recvSeq += 1
        return message.data
    }

    // TODO handle ack could be called from the websocket receive thread while a
    // message is being sent, both modifying unackedMessages.
    private func handleAck(_ ack: ReliabilityData) {
        if let first = unackedMessages.first {
            if first.seq == ack.seq {
                unackedMessages.remove(at: 0)
            } else {
                Log.reliability.info("Received an ACK for sequence number \(ack.seq) but first unacked data item has sequence number \(first.seq)")
            }
        } else {
            Log.reliability.info("Received ACK but there is no unacked data.")
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
