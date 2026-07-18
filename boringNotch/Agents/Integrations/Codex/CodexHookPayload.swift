//
//  CodexHookPayload.swift
//  boringNotch
//
//  Tolerant parser for Codex hook JSON.
//

import Foundation

enum CodexHookParserError: Error, LocalizedError {
    case invalidJSON
    case unsupportedHook(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            "Invalid Codex hook JSON"
        case let .unsupportedHook(name):
            "Unsupported Codex hook: \(name)"
        }
    }
}

struct CodexHookPayload {
    static func bridgeEvents(from data: Data, now: Date = Date()) throws -> [AgentBridgeEvent] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else {
            throw CodexHookParserError.invalidJSON
        }
        return try bridgeEvents(from: payload, now: now)
    }

    static func bridgeEvents(from payload: [String: Any], now: Date = Date()) throws -> [AgentBridgeEvent] {
        let hookName = hookEventName(in: payload)
        let normalizedHookName = normalize(hookName)
        let sessionID = stringValue(in: payload, keys: ["session_id", "sessionID", "sessionId", "conversation_id", "conversationID"])
            ?? stableSessionID(for: payload)
        let cwd = stringValue(in: payload, keys: ["cwd", "workspace", "workspace_path", "repository", "repo_path"])
            ?? ProcessInfo.processInfo.environment["PWD"]

        switch normalizedHookName {
        case "sessionstart", "start":
            return [
                AgentBridgeEvent(
                    type: .sessionStarted,
                    sessionID: sessionID,
                    tool: .codex,
                    title: title(for: cwd),
                    cwd: cwd,
                    at: now
                )
            ]

        case "userpromptsubmit", "promptsubmitted", "promptsubmit":
            return [
                .startedIfNeeded(sessionID: sessionID, cwd: cwd, at: now),
                AgentBridgeEvent(
                    type: .promptSubmitted,
                    sessionID: sessionID,
                    summary: promptSummary(in: payload),
                    at: now
                )
            ]

        case "pretooluse", "toolstart":
            return [
                .startedIfNeeded(sessionID: sessionID, cwd: cwd, at: now),
                AgentBridgeEvent(
                    type: .statusUpdated,
                    sessionID: sessionID,
                    summary: toolSummary(in: payload, fallback: "Using tool"),
                    at: now
                )
            ]

        case "posttooluse", "toolfinish":
            return [
                .startedIfNeeded(sessionID: sessionID, cwd: cwd, at: now),
                AgentBridgeEvent(
                    type: .statusUpdated,
                    sessionID: sessionID,
                    summary: toolSummary(in: payload, fallback: "Tool finished"),
                    at: now
                )
            ]

        case "permissionrequest", "permissionrequested", "approvalrequest", "approvalrequested":
            return [
                .startedIfNeeded(sessionID: sessionID, cwd: cwd, at: now),
                AgentBridgeEvent(
                    type: .permissionRequested,
                    sessionID: sessionID,
                    permissionRequest: PermissionRequest(
                        id: stringValue(in: payload, keys: ["request_id", "requestID", "permission_id", "permissionID"]) ?? UUID().uuidString,
                        toolName: toolName(in: payload),
                        commandSummary: commandSummary(in: payload),
                        pathSummary: pathSummary(in: payload),
                        requestedAt: now
                    )
                )
            ]

        case "stop", "sessionstop", "sessionend":
            return [
                AgentBridgeEvent(
                    type: .sessionStopped,
                    sessionID: sessionID,
                    at: now
                )
            ]

        default:
            throw CodexHookParserError.unsupportedHook(hookName)
        }
    }

    private static func hookEventName(in payload: [String: Any]) -> String {
        stringValue(in: payload, keys: ["hook_event_name", "hookEventName", "event", "type", "name"])
            ?? "unknown"
    }

    private static func title(for cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "Codex" }
        let lastComponent = URL(fileURLWithPath: (cwd as NSString).expandingTildeInPath).lastPathComponent
        return lastComponent.isEmpty ? "Codex" : "Codex - \(lastComponent)"
    }

    private static func stableSessionID(for payload: [String: Any]) -> String {
        if let cwd = stringValue(in: payload, keys: ["cwd", "workspace", "workspace_path"]) {
            return "codex:\(cwd)"
        }
        return "codex:default"
    }

    private static func promptSummary(in payload: [String: Any]) -> String {
        let prompt = stringValue(in: payload, keys: ["prompt", "user_prompt", "userPrompt", "message"])
        return summarize(prompt, fallback: "Prompt submitted")
    }

    private static func toolSummary(in payload: [String: Any], fallback: String) -> String {
        let tool = toolName(in: payload)
        if let command = commandSummary(in: payload), !command.isEmpty {
            return "\(tool): \(command)"
        }
        return tool == "tool" ? fallback : "\(tool) running"
    }

    private static func toolName(in payload: [String: Any]) -> String {
        stringValue(in: payload, keys: ["tool_name", "toolName", "tool", "command_name", "commandName"])
            ?? nestedStringValue(in: payload, containerKeys: ["tool_input", "toolInput", "input"], keys: ["tool_name", "toolName", "name"])
            ?? "tool"
    }

    private static func commandSummary(in payload: [String: Any]) -> String? {
        stringValue(in: payload, keys: ["command", "cmd", "command_summary", "commandSummary"])
            ?? nestedStringValue(in: payload, containerKeys: ["tool_input", "toolInput", "input"], keys: ["command", "cmd", "script"])
    }

    private static func pathSummary(in payload: [String: Any]) -> String? {
        stringValue(in: payload, keys: ["path", "file_path", "filePath", "cwd"])
            ?? nestedStringValue(in: payload, containerKeys: ["tool_input", "toolInput", "input"], keys: ["path", "file_path", "filePath", "cwd"])
    }

    private static func summarize(_ value: String?, fallback: String) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return fallback
        }
        if value.count <= 90 { return value }
        let end = value.index(value.startIndex, offsetBy: 87)
        return "\(value[..<end])..."
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func stringValue(in payload: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = payload[key] as? String, !value.isEmpty { return value }
            if let value = payload[key] as? CustomStringConvertible { return value.description }
        }
        return nil
    }

    private static func nestedStringValue(in payload: [String: Any], containerKeys: [String], keys: [String]) -> String? {
        for containerKey in containerKeys {
            if let nested = payload[containerKey] as? [String: Any],
               let value = stringValue(in: nested, keys: keys) {
                return value
            }
        }
        return nil
    }
}

private extension AgentBridgeEvent {
    static func startedIfNeeded(sessionID: String, cwd: String?, at: Date) -> AgentBridgeEvent {
        AgentBridgeEvent(
            type: .sessionStarted,
            sessionID: sessionID,
            tool: .codex,
            title: cwd.map { "Codex - \(URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).lastPathComponent)" } ?? "Codex",
            cwd: cwd,
            at: at
        )
    }
}
