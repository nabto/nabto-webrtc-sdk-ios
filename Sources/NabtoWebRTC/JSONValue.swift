import Foundation

public enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
    
    public var asBool: Bool? {
        if case .bool(let value) = self {
            return value
        } else {
            return nil
        }
    }

    public var asNumber: Double? {
        if case .number(let value) = self {
            return value
        } else {
            return nil
        }
    }

    public var asString: String? {
        if case .string(let value) = self {
            return value
        } else {
            return nil
        }
    }

    public var asArray: [JSONValue]? {
        if case .array(let value) = self {
            return value
        } else {
            return nil
        }
    }

    public var asObject: [String: JSONValue]? {
        if case .object(let value) = self {
            return value
        } else {
            return nil
        }
    }
}

extension JSONValue: Codable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid JSON"))
        }
    }
}
