import Foundation

/**
 * JSONValue is used to represent arbitrary JSON values (numbers/strings/arrays/objects).
 * It implements Equatable and Codable interfaces and as such can be used with JSONEncoder and JSONDecoder.
 * To convert a Codable to/from a JSONValue you may use JSONValueEncoder and JSONValueDecoder.
 */
public enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
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

extension JSONValue {
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

/**
 * JSONValueEncoder is used for converting an object that implements the Encodable intraface into a JSONValue
 */
public class JSONValueEncoder {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    public func encode<T>(_ value: T) throws -> JSONValue where T : Encodable {
        let data = try encoder.encode(value)
        return try decoder.decode(JSONValue.self, from: data)
    }
}

/**
 * JSONValueDecoder is used for converting a JSONValue into an object that implements the Decodable interface.
 */
public class JSONValueDecoder {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    public func decode<T>(_ type: T.Type, from json: JSONValue) throws -> T where T : Decodable {
        let data = try encoder.encode(json)
        return try decoder.decode(type, from: data)
    }
}
