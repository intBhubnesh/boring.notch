//
//  ClaudeHookPayload.swift
//  boringNotch
//
//  Tolerant parser for Claude Code hook JSON.
//

import Foundation

enum ClaudeHookParserError: Error, LocalizedError {
    case invalidJSON
    case unsupportedHook(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            "Invalid Claude hook JSON"
        case let .unsupportedHook(name):
            "Unsupported Claude hook: \(name)"
        }
    }
}

struct ClaudeHookPayload {
    static func bridgeEvents(from data: Data, now: Date = Date()) throws -> [AgentBridgeEvent] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else {
            throw ClaudeHookParserError.invalidJSON
        }
        return try bridgeEvents(from: payload, now: now)
    }

    static func bridgeEvents(from payload: [String: Any], now: Date = Date()) throws -> [AgentBridgeEvent] {
        let hookName = hookEventName(in: payload)
        let normalizedHookName = normalize(hookName)
        let cwd = stringValue(in: payload, keys: ["cwd", "workspace", "workspace_path"])
            ?? ProcessInfo.processInfo.environment["PWD"]
        let sessionID = stringValue(in: payload, keys: ["session_id", "sessionID", "sessionId"])
            ?? cwd.map { "claude:\($0)" }
            ?? "claude:default"

        switch normalizedHookName {
        case "sessionstart":
            return [
                AgentBridgeEvent(
                    type: .sessionStarted,
                    sessionID: sessionID,
                    tool: .claudeCode,
                    title: title(for: cwd),
                    cwd: cwd,
                    summary: "Started Claude Code session",
                    at: now
                )
            ]

        case "userpromptsubmit":
            return [
                .claudeStartedIfNeeded(sessionID: sessionID, cwd: cwd, at: now),
                AgentBridgeEvent(
                    type: .promptSubmitted,
                    sessionID: sessionID,
                    summary: promptSummary(in: payload),
                    at: now
                )
            ]

        case "pretooluse":
            return [
                .claudeStartedIfNeeded(sessionID: sessionID, cwd: cwd, at: now),
                AgentBridgeEvent(
                    type: .statusUpdated,
                    sessionID: sessionID,
                    summary: toolSummary(in: payload, fallback: "Using Claude Code tool"),
                    at: now
                )
            ]

        case "posttooluse":
            return [
                .claudeStartedIfNeeded(sessionID: sessionID, cwd: cwd, at: now),
                AgentBridgeEvent(
                    type: .statusUpdated,
                    sessionID: sessionID,
                    summary: toolResultSummary(in: payload),
                    at: now
                )
            ]

        case "posttoolusefailure":
            return [
                .claudeStartedIfNeeded(sessionID: sessionID, cwd: cwd, at: now),
                AgentBridgeEvent(
                    type: .statusUpdated,
                    sessionID: sessionID,
                    summary: errorSummary(in: payload, fallback: "Claude Code tool failed"),
                    at: now
                )
            ]

        case "permissionrequest":
            if let prompt = questionPrompt(in: payload, now: now) {
                return [
                    .claudeStartedIfNeeded(sessionID: sessionID, cwd: cwd, at: now),
                    AgentBridgeEvent(
                        type: .questionAsked,
                        sessionID: sessionID,
                        questionPrompt: prompt
                    )
                ]
            }

            return [
                .claudeStartedIfNeeded(sessionID: sessionID, cwd: cwd, at: now),
                AgentBridgeEvent(
                    type: .permissionRequested,
                    sessionID: sessionID,
                    permissionRequest: PermissionRequest(
                        id: stringValue(in: payload, keys: ["tool_use_id", "toolUseID", "request_id", "requestID"]) ?? UUID().uuidString,
                        toolName: toolName(in: payload),
                        commandSummary: permissionSummary(in: payload),
                        pathSummary: pathSummary(in: payload),
                        requestedAt: now
                    )
                )
            ]

        case "permissiondenied":
            return [
                .claudeStartedIfNeeded(sessionID: sessionID, cwd: cwd, at: now),
                AgentBridgeEvent(
                    type: .statusUpdated,
                    sessionID: sessionID,
                    summary: errorSummary(in: payload, fallback: "Claude Code permission was denied"),
                    at: now
                )
            ]

        case "notification":
            return [
                .claudeStartedIfNeeded(sessionID: sessionID, cwd: cwd, at: now),
                AgentBridgeEvent(
                    type: .statusUpdated,
                    sessionID: sessionID,
                    summary: notificationSummary(in: payload),
                    at: now
                )
            ]

        case "stop", "sessionend":
            return [
                AgentBridgeEvent(
                    type: .sessionStopped,
                    sessionID: sessionID,
                    at: now
                )
            ]

        case "stopfailure":
            return [
                AgentBridgeEvent(
                    type: .sessionFailed,
                    sessionID: sessionID,
                    reason: errorSummary(in: payload, fallback: "Claude Code session failed"),
                    at: now
                )
            ]

        case "subagentstart":
            let agentType = stringValue(in: payload, keys: ["agent_type", "agentType"]) ?? "subagent"
            return [
                .claudeStartedIfNeeded(sessionID: sessionID, cwd: cwd, at: now),
                AgentBridgeEvent(
                    type: .statusUpdated,
                    sessionID: sessionID,
                    summary: "Started \(agentType) subagent",
                    at: now
                )
            ]

        case "subagentstop":
            let agentType = stringValue(in: payload, keys: ["agent_type", "agentType"]) ?? "subagent"
            return [
                .claudeStartedIfNeeded(sessionID: sessionID, cwd: cwd, at: now),
                AgentBridgeEvent(
                    type: .statusUpdated,
                    sessionID: sessionID,
                    summary: "Finished \(agentType) subagent",
                    at: now
                )
            ]

        case "precompact":
            return [
                .claudeStartedIfNeeded(sessionID: sessionID, cwd: cwd, at: now),
                AgentBridgeEvent(
                    type: .statusUpdated,
                    sessionID: sessionID,
                    summary: "Claude Code is compacting context",
                    at: now
                )
            ]

        default:
            throw ClaudeHookParserError.unsupportedHook(hookName)
        }
    }

    private static func hookEventName(in payload: [String: Any]) -> String {
        stringValue(in: payload, keys: ["hook_event_name", "hookEventName", "event", "type", "name"])
            ?? "unknown"
    }

    private static func title(for cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "Claude Code" }
        let lastComponent = URL(fileURLWithPath: (cwd as NSString).expandingTildeInPath).lastPathComponent
        return lastComponent.isEmpty ? "Claude Code" : "Claude - \(lastComponent)"
    }

    private static func promptSummary(in payload: [String: Any]) -> String {
        let prompt = stringValue(in: payload, keys: ["prompt", "message"])
        return prompt.map { "Prompt: \(summarize($0, fallback: "Prompt submitted"))" } ?? "Prompt submitted"
    }

    private static func toolSummary(in payload: [String: Any], fallback: String) -> String {
        let tool = toolName(in: payload)
        if let input = toolInputPreview(in: payload), !input.isEmpty {
            return "\(tool): \(input)"
        }
        return tool == "tool" ? fallback : "Running \(tool)"
    }

    private static func toolResultSummary(in payload: [String: Any]) -> String {
        let tool = toolName(in: payload)
        if let preview = toolResponsePreview(in: payload), !preview.isEmpty {
            return "\(tool) finished: \(preview)"
        }
        return tool == "tool" ? "Claude Code tool finished" : "\(tool) finished"
    }

    private static func notificationSummary(in payload: [String: Any]) -> String {
        stringValue(in: payload, keys: ["message", "title", "notification_type", "notificationType"])
            ?? "Claude Code notification"
    }

    private static func errorSummary(in payload: [String: Any], fallback: String) -> String {
        stringValue(in: payload, keys: ["error", "error_details", "errorDetails", "message"]) ?? fallback
    }

    private static func permissionSummary(in payload: [String: Any]) -> String? {
        if let description = nestedStringValue(in: payload, containerKeys: ["tool_input", "toolInput", "input"], keys: ["description"]) {
            return description
        }
        if let command = nestedStringValue(in: payload, containerKeys: ["tool_input", "toolInput", "input"], keys: ["command", "cmd"]) {
            return command
        }
        return toolInputPreview(in: payload)
    }

    private static func pathSummary(in payload: [String: Any]) -> String? {
        stringValue(in: payload, keys: ["cwd", "path", "file_path", "filePath"])
            ?? nestedStringValue(in: payload, containerKeys: ["tool_input", "toolInput", "input"], keys: ["path", "file_path", "filePath"])
    }

    private static func questionPrompt(in payload: [String: Any], now: Date) -> QuestionPrompt? {
        guard toolName(in: payload) == "AskUserQuestion" else { return nil }

        let question = nestedStringValue(
            in: payload,
            containerKeys: ["tool_input", "toolInput", "input"],
            keys: ["question", "prompt", "message"]
        ) ?? stringValue(in: payload, keys: ["prompt", "message"])
            ?? firstQuestionText(in: payload)

        guard let question, !question.isEmpty else { return nil }

        let options = questionOptions(in: payload)
        return QuestionPrompt(
            id: stringValue(in: payload, keys: ["tool_use_id", "toolUseID", "question_id", "questionID"]) ?? UUID().uuidString,
            title: firstQuestionHeader(in: payload) ?? "Claude Code question",
            question: question,
            options: options,
            multiSelect: boolValue(in: payload, keys: ["multi_select", "multiSelect"]) ?? false,
            allowsFreeform: options.isEmpty || (boolValue(in: payload, keys: ["allows_freeform", "allowsFreeform"]) ?? true),
            askedAt: now
        )
    }

    private static func questionOptions(in payload: [String: Any]) -> [QuestionOption] {
        let rawOptions = nestedArray(in: payload, containerKeys: ["tool_input", "toolInput", "input"], keys: ["options", "choices"])
            ?? arrayValue(in: payload, keys: ["options", "choices"])
            ?? firstQuestionOptions(in: payload)
            ?? []

        return rawOptions.enumerated().compactMap { index, item in
            if let option = item as? String {
                return QuestionOption(id: option, label: option)
            }
            if let option = item as? [String: Any] {
                let label = stringValue(in: option, keys: ["label", "text", "value"])
                let id = stringValue(in: option, keys: ["id", "value", "label", "text"]) ?? label
                if let label, let id {
                    return QuestionOption(id: id, label: label)
                }
            }
            return QuestionOption(id: "option-\(index)", label: "\(item)")
        }
    }

    private static func firstQuestionText(in payload: [String: Any]) -> String? {
        firstQuestionObject(in: payload).flatMap { question in
            stringValue(in: question, keys: ["question", "prompt", "message"])
        }
    }

    private static func firstQuestionHeader(in payload: [String: Any]) -> String? {
        firstQuestionObject(in: payload).flatMap { question in
            stringValue(in: question, keys: ["header", "title"])
        }
    }

    private static func firstQuestionOptions(in payload: [String: Any]) -> [Any]? {
        guard let question = firstQuestionObject(in: payload) else { return nil }
        return arrayValue(in: question, keys: ["options", "choices"])
    }

    private static func firstQuestionObject(in payload: [String: Any]) -> [String: Any]? {
        let questions = nestedArray(in: payload, containerKeys: ["tool_input", "toolInput", "input"], keys: ["questions"])
            ?? arrayValue(in: payload, keys: ["questions"])
        return questions?.first as? [String: Any]
    }

    private static func toolName(in payload: [String: Any]) -> String {
        stringValue(in: payload, keys: ["tool_name", "toolName", "tool"])
            ?? "tool"
    }

    private static func toolInputPreview(in payload: [String: Any]) -> String? {
        if let command = nestedStringValue(in: payload, containerKeys: ["tool_input", "toolInput", "input"], keys: ["command", "cmd"]) {
            return summarize(command, fallback: "Tool input")
        }
        if let description = nestedStringValue(in: payload, containerKeys: ["tool_input", "toolInput", "input"], keys: ["description"]) {
            return summarize(description, fallback: "Tool input")
        }
        guard let value = payload["tool_input"] ?? payload["toolInput"] ?? payload["input"] else { return nil }
        return summarize(render(value), fallback: "Tool input")
    }

    private static func toolResponsePreview(in payload: [String: Any]) -> String? {
        guard let value = payload["tool_response"] ?? payload["toolResponse"] else { return nil }
        return summarize(render(value), fallback: "Tool response")
    }

    private static func summarize(_ value: String?, fallback: String) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return fallback
        }
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        if collapsed.count <= 110 { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: 107)
        return "\(collapsed[..<end])..."
    }

    private static func render(_ value: Any) -> String {
        if let string = value as? String { return string }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "\(value)"
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func stringValue(in payload: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = payload[key] as? String, !value.isEmpty { return value }
            if let value = payload[key] as? CustomStringConvertible { return value.description }
        }
        return nil
    }

    private static func boolValue(in payload: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = payload[key] as? Bool { return value }
        }
        return nil
    }

    private static func arrayValue(in payload: [String: Any], keys: [String]) -> [Any]? {
        for key in keys {
            if let value = payload[key] as? [Any] { return value }
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

    private static func nestedArray(in payload: [String: Any], containerKeys: [String], keys: [String]) -> [Any]? {
        for containerKey in containerKeys {
            if let nested = payload[containerKey] as? [String: Any],
               let value = arrayValue(in: nested, keys: keys) {
                return value
            }
        }
        return nil
    }
}

private extension AgentBridgeEvent {
    static func claudeStartedIfNeeded(sessionID: String, cwd: String?, at: Date) -> AgentBridgeEvent {
        AgentBridgeEvent(
            type: .sessionStarted,
            sessionID: sessionID,
            tool: .claudeCode,
            title: cwd.map { "Claude - \(URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).lastPathComponent)" } ?? "Claude Code",
            cwd: cwd,
            at: at
        )
    }
}
