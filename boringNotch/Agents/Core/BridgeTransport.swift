//
//  BridgeTransport.swift
//  boringNotch
//
//  Agent Activity Integration - local bridge protocol.
//

import Darwin
import Foundation

enum AgentBridgeError: Error, LocalizedError {
    case missingField(String)
    case unsupportedEvent(String)

    var errorDescription: String? {
        switch self {
        case let .missingField(field):
            "Missing bridge event field: \(field)"
        case let .unsupportedEvent(type):
            "Unsupported bridge event type: \(type)"
        }
    }
}

struct AgentBridgeTransport {
    static var socketPath: String {
        "\(userHomeDirectory)/Library/Containers/theboringteam.boringnotch/Data/tmp/boring-agent.sock"
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private var userHomeDirectory: String {
    if let user = getpwuid(getuid()), let home = user.pointee.pw_dir {
        return String(cString: home)
    }
    return NSHomeDirectory()
}

struct AgentBridgeMessage: Codable, Sendable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var event: AgentBridgeEvent
    var expectsResponse: Bool = false
    var responseStyle: AgentBridgeResponseStyle? = nil
}

enum AgentBridgeResponseStyle: String, Codable, Sendable, Hashable {
    case codexPermissionRequest
    case claudePermissionRequest
    case claudeQuestion
}

struct AgentBridgeResponse: Codable, Sendable, Hashable {
    var stdout: String?

    static let acknowledged = AgentBridgeResponse(stdout: nil)
}

struct AgentBridgeEvent: Codable, Sendable, Hashable {
    enum EventType: String, Codable, Sendable, Hashable {
        case sessionStarted
        case promptSubmitted
        case statusUpdated
        case permissionRequested
        case permissionResolved
        case questionAsked
        case questionAnswered
        case sessionStopped
        case sessionFailed
    }

    var type: EventType
    var sessionID: String
    var tool: AgentTool? = nil
    var title: String? = nil
    var cwd: String? = nil
    var summary: String? = nil
    var reason: String? = nil
    var at: Date? = nil
    var permissionRequest: PermissionRequest? = nil
    var requestID: String? = nil
    var resolution: PermissionResolution? = nil
    var questionPrompt: QuestionPrompt? = nil
    var questionID: String? = nil
    var questionResponse: QuestionPromptResponse? = nil

    func toAgentEvent() throws -> AgentEvent {
        let eventDate = at ?? Date()

        switch type {
        case .sessionStarted:
            return .sessionStarted(
                sessionID: sessionID,
                tool: tool ?? .other,
                title: try title.required("title"),
                cwd: cwd,
                at: eventDate
            )
        case .promptSubmitted:
            return .promptSubmitted(
                sessionID: sessionID,
                summary: summary ?? "Prompt submitted",
                at: eventDate
            )
        case .statusUpdated:
            return .statusUpdated(
                sessionID: sessionID,
                summary: summary ?? "Working",
                at: eventDate
            )
        case .permissionRequested:
            return .permissionRequested(
                sessionID: sessionID,
                request: try permissionRequest.required("permissionRequest")
            )
        case .permissionResolved:
            return .permissionResolved(
                sessionID: sessionID,
                requestID: try requestID.required("requestID"),
                resolution: try resolution.required("resolution"),
                at: eventDate
            )
        case .questionAsked:
            return .questionAsked(
                sessionID: sessionID,
                prompt: try questionPrompt.required("questionPrompt")
            )
        case .questionAnswered:
            return .questionAnswered(
                sessionID: sessionID,
                questionID: try questionID.required("questionID"),
                response: try questionResponse.required("questionResponse"),
                at: eventDate
            )
        case .sessionStopped:
            return .sessionStopped(sessionID: sessionID, at: eventDate)
        case .sessionFailed:
            return .sessionFailed(sessionID: sessionID, reason: reason, at: eventDate)
        }
    }
}

private extension Optional {
    func required(_ field: String) throws -> Wrapped {
        guard let value = self else { throw AgentBridgeError.missingField(field) }
        return value
    }
}
