//
//  HubProtocol.swift
//  SignalRClient
//
//  Created by Pawel Kadluczka on 8/27/17.
//  Copyright © 2017 Pawel Kadluczka. All rights reserved.
//

import Foundation

public enum ProtocolType: Int {
    case Text = 1
    case Binary
}

public protocol HubProtocol {
    var name: String { get }
    var version: Int { get }
    var type: ProtocolType { get }
    func parseMessages(input: Data) throws -> [HubMessage]
    func writeMessage(message: HubMessage) throws -> Data
}

public enum MessageType: Int, Codable {
    case Invocation = 1
    case StreamItem = 2
    case Completion = 3
    case StreamInvocation = 4
    case CancelInvocation = 5
    case Ping = 6
    case Close = 7
}

public protocol HubMessage {
    var type: MessageType { get }
    var payload: Data? { set get }
}

public class ServerInvocationMessage: HubMessage, Encodable {
    public let type = MessageType.Invocation
    public let invocationId: String?
    public let target: String
    public let arguments: [Encodable]
    public let streamIds: [String]?
    public var payload: Data?

    convenience init(target: String, arguments: [Encodable], streamIds: [String]?) {
        self.init(invocationId: nil, target: target, arguments: arguments, streamIds: streamIds)
    }

    init(invocationId: String?, target: String, arguments: [Encodable], streamIds: [String]?) {
        self.invocationId = invocationId
        self.target = target
        self.arguments = arguments
        self.streamIds = streamIds
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(target, forKey: .target)
        try container.encodeIfPresent(invocationId, forKey: .invocationId)

        var argumentsContainer = container.nestedUnkeyedContainer(forKey: .arguments)
        try arguments.forEach {
            try argumentsContainer.encode(AnyEncodable(value:$0))
        }
        if let streamIds = streamIds {
            try container.encode(streamIds, forKey: .streamIds)
        }
    }

    enum CodingKeys : String, CodingKey {
        case type
        case target
        case invocationId
        case arguments
        case streamIds
    }
}

public class ClientInvocationMessage: HubMessage, Decodable {
    public let type = MessageType.Invocation
    public let target: String
    private var arguments: UnkeyedDecodingContainer?
    public var payload: Data?

    public required init (from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try container.decode(String.self, forKey: .target)
        if container.contains(.arguments) {
            arguments = try container.nestedUnkeyedContainer(forKey: .arguments)
        }
    }

    public func getArgument<T: Decodable>(type: T.Type) throws -> T {
        guard arguments != nil else {
            throw SignalRError.invalidOperation(message: "No arguments exist.")
        }

        return try arguments!.decode(T.self)
    }

    var hasMoreArgs : Bool {
        get {
            if arguments != nil {
                return !arguments!.isAtEnd
            }

            return false
        }
    }

    enum CodingKeys : String, CodingKey {
        case type
        case target
        case invocationId
        case arguments
    }
}

public class StreamItemMessage: HubMessage, Codable {
    public let type = MessageType.StreamItem
    public let invocationId: String
    let container: KeyedDecodingContainer<StreamItemMessage.CodingKeys>?
    let item: Encodable?
    public var payload: Data?

    public required init (from decoder: Decoder) throws {
        container = try decoder.container(keyedBy: CodingKeys.self)
        invocationId = try container!.decode(String.self, forKey: .invocationId)
        item = nil
    }

    public init (invocationId: String, item: Encodable) {
        self.invocationId = invocationId
        self.item = item
        container = nil
    }

    public func getItem<T: Decodable>(_ type: T.Type) throws -> T {
        guard container != nil else {
            throw SignalRError.invalidOperation(message: "Internal error - StreamItemMessage.container is nil.")
        }

        do {
            return try container!.decode(T.self, forKey: .item)
        } catch {
            throw SignalRError.serializationError(underlyingError: error)
        }
    }

    public func encode(to encoder: Encoder) throws {
        guard item != nil else {
            throw SignalRError.invalidOperation(message: "Internal error - StreamItemMessage.item is nil.")
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(invocationId, forKey: .invocationId)
        try container.encode(AnyEncodable(value: item!), forKey: .item)
    }

    enum CodingKeys : String, CodingKey {
        case type
        case invocationId
        case item
    }
}

public class CompletionMessage: HubMessage, Codable {
    public let type = MessageType.Completion
    public let invocationId: String
    public let error: String?
    public let hasResult: Bool
    let container: KeyedDecodingContainer<CompletionMessage.CodingKeys>?
    public var payload: Data?

    public required init (from decoder: Decoder) throws {
        container = try decoder.container(keyedBy: CodingKeys.self)
        invocationId = try container!.decode(String.self, forKey: .invocationId)
        error = try container!.decodeIfPresent(String.self, forKey: .error)
        hasResult = container!.contains(.result)
    }

    public init (invocationId: String, error: String?) {
        self.invocationId = invocationId
        self.error = error
        hasResult = false
        container = nil
    }

    public func getResult<T: Decodable>(_ type: T.Type) throws -> T? {
        guard container != nil else {
            throw SignalRError.invalidOperation(message: "Internal error - CompletionMessage.container is nil.")
        }

        if hasResult {
            do {
                return try container!.decode(T.self, forKey: .result)
            } catch {
                throw SignalRError.serializationError(underlyingError: error)
            }
        }

        return nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(invocationId, forKey: .invocationId)
        if let error = error {
            try container.encode(error, forKey: .error)
        }
    }

    enum CodingKeys : String, CodingKey {
        case type
        case invocationId
        case error
        case result
    }
}

public class StreamInvocationMessage: HubMessage, Encodable {
    public let type = MessageType.StreamInvocation
    public let invocationId: String
    public let target: String
    public let arguments: [Encodable]
    public let streamIds: [String]?
    public var payload: Data?

    init(invocationId: String, target: String, arguments: [Encodable], streamIds: [String]?) {
        self.invocationId = invocationId
        self.target = target
        self.arguments = arguments
        self.streamIds = streamIds
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(target, forKey: .target)
        try container.encode(invocationId, forKey: .invocationId)
        var argumentsContainer = container.nestedUnkeyedContainer(forKey: .arguments)
        try arguments.forEach {
            try argumentsContainer.encode(AnyEncodable(value: $0))
        }
        if let streamIds = streamIds {
            try container.encode(streamIds, forKey: .streamIds)
        }
    }

    enum CodingKeys : String, CodingKey {
        case type
        case target
        case invocationId
        case arguments
        case streamIds
    }
}

public class CancelInvocationMessage: HubMessage, Encodable {
    public let type = MessageType.CancelInvocation
    public let invocationId: String
    public var payload: Data?

    init(invocationId: String) {
        self.invocationId = invocationId
    }
}

public class PingMessage : HubMessage {
    public let type = MessageType.Ping
    private init() { }
    public var payload: Data?

    static let instance = PingMessage()
}

public class CloseMessage: HubMessage, Decodable {
    public private(set) var type = MessageType.Close
    public let error: String?
    public var payload: Data?

    init(error: String?) {
        self.error = error
    }
}
