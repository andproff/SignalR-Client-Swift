//
//  JSONHubProtocol.swift
//  SignalRClient
//
//  Created by Pawel Kadluczka on 8/27/17.
//  Copyright © 2017 Pawel Kadluczka. All rights reserved.
//

import Foundation

public class JSONHubProtocol: HubProtocol {
    private static let recordSeparator = UInt8(0x1e)
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger: Logger
    public let name = "json"
    public let version = 1
    public let type = ProtocolType.Text

    public init(logger: Logger,
                encoder: JSONEncoder = JSONEncoder(),
                decoder: JSONDecoder = JSONDecoder()) {
        self.logger = logger
        self.encoder = encoder
        self.decoder = decoder
    }

    public func parseMessages(input: Data) throws -> [HubMessage] {
        let payloads = input.split(separator: JSONHubProtocol.recordSeparator)
        // do not try to parse the last payload if it is not terminated with record sparator
        var count = payloads.count
        if count > 0 && input.last != JSONHubProtocol.recordSeparator {
            logger.log(logLevel: .warning, message: "Partial message received. Here be dragons...")
            count = count - 1
        }

        logger.log(logLevel: .debug, message: "Payload contains \(count) message(s)")

        return try payloads[0..<count].map{ try createHubMessage(payload: $0) }
    }

    public func createHubMessage(payload: Data) throws -> HubMessage {
        logger.log(logLevel: .debug, message: "Message received: \(String(data: payload, encoding: .utf8) ?? "(empty)")")

        do {
            var message: HubMessage
            let messageType = try getMessageType(payload: payload)
            switch messageType {
            case .Invocation:
                message = try decoder.decode(ClientInvocationMessage.self, from: payload)
            case .StreamItem:
                message = try decoder.decode(StreamItemMessage.self, from: payload)
            case .Completion:
                message = try decoder.decode(CompletionMessage.self, from: payload)
            case .Ping:
                message = PingMessage.instance
            case .Close:
                message = try decoder.decode(CloseMessage.self, from: payload)
            default:
                logger.log(logLevel: .error, message: "Unsupported messageType: \(messageType)")
                throw SignalRError.unknownMessageType
            }
            message.payload = payload
            return message
        } catch {
            throw SignalRError.protocolViolation(underlyingError: error)
        }
    }

    private func getMessageType(payload: Data) throws -> MessageType {
        struct MessageTypeHelper: Decodable {
            let type: MessageType

            private enum CodingKeys: String, CodingKey { case type }
        }

        do {
            return try decoder.decode(MessageTypeHelper.self, from: payload).type
        } catch {
            logger.log(logLevel: .error, message: "Getting messageType failed: \(error)")
            throw SignalRError.protocolViolation(underlyingError: error)
        }
    }

    public func writeMessage(message: HubMessage) throws -> Data {
        var payload = try createMessageData(message: message)
        payload.append(JSONHubProtocol.recordSeparator)
        return payload
    }

    private func createMessageData(message: HubMessage) throws -> Data {
        switch message.type {
        case .Invocation:
            return try encoder.encode(message as! ServerInvocationMessage)
        case .StreamItem:
            return try encoder.encode(message as! StreamItemMessage)
        case .StreamInvocation:
            return try encoder.encode(message as! StreamInvocationMessage)
        case .CancelInvocation:
            return try encoder.encode(message as! CancelInvocationMessage)
        case .Completion:
            return try encoder.encode(message as! CompletionMessage)
        default:
            throw SignalRError.invalidOperation(message: "Unexpected MessageType.")
        }
    }
}
