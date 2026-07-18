//
//  main.swift
//  BoringNotchAgentHooks
//
//  Build locally with:
//  swiftc BoringNotchAgentHooks/main.swift -o BoringNotchAgentHooks/BoringNotchAgentHooks
//

import Darwin
import Foundation

private var socketPath: String {
    "\(userHomeDirectory)/Library/Containers/theboringteam.boringnotch/Data/tmp/boring-agent.sock"
}

private var userHomeDirectory: String {
    if let user = getpwuid(getuid()), let home = user.pointee.pw_dir {
        return String(cString: home)
    }
    return NSHomeDirectory()
}

BoringNotchAgentHooksMain.run()

enum BoringNotchAgentHooksMain {
    static func run() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPEN_ISLAND_SKIP_HOOKS"] != "1",
              environment["BORING_NOTCH_SKIP_AGENT_HOOKS"] != "1" else {
            return
        }

        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard !input.isEmpty else { return }

        do {
            let messages = try hookSource() == "claude"
                ? ClaudeHookAdapter.messages(from: input)
                : CodexHookAdapter.messages(from: input)
            for message in messages {
                if let stdout = BridgeClient.send(message), let data = stdout.data(using: .utf8) {
                    FileHandle.standardOutput.write(data)
                }
            }
        } catch {
            // Hooks must fail open. Never block the agent because Boring Notch is unavailable.
        }
    }

    private static func hookSource() -> String {
        let arguments = Array(CommandLine.arguments.dropFirst())
        var index = 0
        while index < arguments.count {
            if arguments[index] == "--source", index + 1 < arguments.count {
                let source = arguments[index + 1].lowercased()
                return source == "claude" || source == "claude-code" ? "claude" : "codex"
            }
            index += 1
        }
        return "codex"
    }
}

private enum BridgeClient {
    private struct Response: Decodable {
        var stdout: String?
    }

    static func send(_ message: [String: Any]) -> String? {
        guard let payload = try? JSONSerialization.data(withJSONObject: message) + Data([0x0A]) else {
            return nil
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let sunPathSize = MemoryLayout.size(ofValue: address.sun_path)
        _ = socketPath.withCString { pointer in
            withUnsafeMutablePointer(to: &address.sun_path) { destination in
                destination.withMemoryRebound(to: CChar.self, capacity: sunPathSize) {
                    strcpy($0, pointer)
                }
            }
        }

        let addressLength = socklen_t(MemoryLayout<sa_family_t>.size + strlen(socketPath) + 1)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, addressLength)
            }
        }
        guard connected == 0 else { return nil }

        payload.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var sent = 0
            while sent < payload.count {
                let count = Darwin.send(fd, baseAddress.advanced(by: sent), payload.count - sent, 0)
                guard count > 0 else { return }
                sent += count
            }
        }

        guard (message["expectsResponse"] as? Bool) == true else { return nil }
        return readResponse(from: fd)
    }

    private static func readResponse(from fd: Int32) -> String? {
        var timeoutValue = timeval(tv_sec: 24 * 60 * 60, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeoutValue, socklen_t(MemoryLayout<timeval>.size))

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
                if data.contains(0x0A) { break }
                continue
            }
            return nil
        }

        guard let line = data.split(separator: 0x0A, omittingEmptySubsequences: true).first,
              let response = try? JSONDecoder().decode(Response.self, from: Data(line)) else {
            return nil
        }
        return response.stdout
    }
}

private enum CodexHookAdapter {
    static func messages(from data: Data) throws -> [[String: Any]] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else { return [] }

        let now = ISO8601DateFormatter().string(from: Date())
        let hookName = normalize(stringValue(in: payload, keys: ["hook_event_name", "hookEventName", "event", "type", "name"]) ?? "unknown")
        let cwd = stringValue(in: payload, keys: ["cwd", "workspace", "workspace_path", "repository", "repo_path"])
            ?? ProcessInfo.processInfo.environment["PWD"]
        let sessionID = stringValue(in: payload, keys: ["session_id", "sessionID", "sessionId", "conversation_id", "conversationID"])
            ?? cwd.map { "codex:\($0)" }
            ?? "codex:default"

        let events: [[String: Any]]
        switch hookName {
        case "sessionstart", "start":
            events = [sessionStarted(sessionID: sessionID, cwd: cwd, at: now)]
        case "userpromptsubmit", "promptsubmitted", "promptsubmit":
            events = [
                sessionStarted(sessionID: sessionID, cwd: cwd, at: now),
                event(type: "promptSubmitted", sessionID: sessionID, at: now, extra: [
                    "summary": summarize(stringValue(in: payload, keys: ["prompt", "user_prompt", "userPrompt", "message"]), fallback: "Prompt submitted")
                ])
            ]
        case "pretooluse", "toolstart":
            events = [
                sessionStarted(sessionID: sessionID, cwd: cwd, at: now),
                event(type: "statusUpdated", sessionID: sessionID, at: now, extra: [
                    "summary": toolSummary(in: payload, fallback: "Using tool")
                ])
            ]
        case "posttooluse", "toolfinish":
            events = [
                sessionStarted(sessionID: sessionID, cwd: cwd, at: now),
                event(type: "statusUpdated", sessionID: sessionID, at: now, extra: [
                    "summary": toolSummary(in: payload, fallback: "Tool finished")
                ])
            ]
        case "permissionrequest", "permissionrequested", "approvalrequest", "approvalrequested":
            events = [
                sessionStarted(sessionID: sessionID, cwd: cwd, at: now),
                event(type: "permissionRequested", sessionID: sessionID, at: now, extra: [
                    "permissionRequest": compact([
                        "id": stringValue(in: payload, keys: ["request_id", "requestID", "permission_id", "permissionID"]) ?? UUID().uuidString,
                        "toolName": toolName(in: payload),
                        "commandSummary": commandSummary(in: payload),
                        "pathSummary": pathSummary(in: payload),
                        "requestedAt": now
                    ])
                ])
            ]
        case "stop", "sessionstop", "sessionend":
            events = [event(type: "sessionStopped", sessionID: sessionID, at: now)]
        default:
            events = []
        }

        return events.map { event in
            let waitsForResponse = (event["type"] as? String) == "permissionRequested"
            return compact([
                "id": UUID().uuidString,
                "event": event,
                "expectsResponse": waitsForResponse,
                "responseStyle": waitsForResponse ? "codexPermissionRequest" : nil
            ])
        }
    }

    private static func event(type: String, sessionID: String, at: String, extra: [String: Any] = [:]) -> [String: Any] {
        var payload: [String: Any] = ["type": type, "sessionID": sessionID, "at": at]
        extra.forEach { payload[$0.key] = $0.value }
        return payload
    }

    private static func sessionStarted(sessionID: String, cwd: String?, at: String) -> [String: Any] {
        event(type: "sessionStarted", sessionID: sessionID, at: at, extra: [
            "tool": "codex",
            "title": title(for: cwd),
            "cwd": cwd as Any
        ].compactNilValues())
    }

    private static func title(for cwd: String?) -> String {
        guard let cwd else { return "Codex" }
        let lastComponent = URL(fileURLWithPath: (cwd as NSString).expandingTildeInPath).lastPathComponent
        return lastComponent.isEmpty ? "Codex" : "Codex - \(lastComponent)"
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
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return fallback }
        guard value.count > 90 else { return value }
        let end = value.index(value.startIndex, offsetBy: 87)
        return "\(value[..<end])..."
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

    private static func nestedStringValue(in payload: [String: Any], containerKeys: [String], keys: [String]) -> String? {
        for containerKey in containerKeys {
            if let nested = payload[containerKey] as? [String: Any],
               let value = stringValue(in: nested, keys: keys) {
                return value
            }
        }
        return nil
    }

    private static func compact(_ dictionary: [String: Any?]) -> [String: Any] {
        dictionary.reduce(into: [String: Any]()) { result, item in
            if let value = item.value {
                result[item.key] = value
            }
        }
    }
}

private enum ClaudeHookAdapter {
    static func messages(from data: Data) throws -> [[String: Any]] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else { return [] }

        let now = ISO8601DateFormatter().string(from: Date())
        let hookName = normalize(stringValue(in: payload, keys: ["hook_event_name", "hookEventName", "event", "type", "name"]) ?? "unknown")
        let cwd = stringValue(in: payload, keys: ["cwd", "workspace", "workspace_path"])
            ?? ProcessInfo.processInfo.environment["PWD"]
        let sessionID = stringValue(in: payload, keys: ["session_id", "sessionID", "sessionId"])
            ?? cwd.map { "claude:\($0)" }
            ?? "claude:default"

        let events: [[String: Any]]
        switch hookName {
        case "sessionstart":
            events = [sessionStarted(sessionID: sessionID, cwd: cwd, at: now)]
        case "userpromptsubmit":
            events = [
                sessionStarted(sessionID: sessionID, cwd: cwd, at: now),
                event(type: "promptSubmitted", sessionID: sessionID, at: now, extra: [
                    "summary": promptSummary(in: payload)
                ])
            ]
        case "pretooluse":
            events = [
                sessionStarted(sessionID: sessionID, cwd: cwd, at: now),
                event(type: "statusUpdated", sessionID: sessionID, at: now, extra: [
                    "summary": toolSummary(in: payload, fallback: "Using Claude Code tool")
                ])
            ]
        case "posttooluse":
            events = [
                sessionStarted(sessionID: sessionID, cwd: cwd, at: now),
                event(type: "statusUpdated", sessionID: sessionID, at: now, extra: [
                    "summary": "\(toolName(in: payload)) finished"
                ])
            ]
        case "permissionrequest":
            if let prompt = questionPrompt(in: payload, at: now) {
                events = [
                    sessionStarted(sessionID: sessionID, cwd: cwd, at: now),
                    event(type: "questionAsked", sessionID: sessionID, at: now, extra: [
                        "questionPrompt": prompt
                    ])
                ]
            } else {
                events = [
                    sessionStarted(sessionID: sessionID, cwd: cwd, at: now),
                    event(type: "permissionRequested", sessionID: sessionID, at: now, extra: [
                        "permissionRequest": compact([
                            "id": stringValue(in: payload, keys: ["tool_use_id", "toolUseID", "request_id", "requestID"]) ?? UUID().uuidString,
                            "toolName": toolName(in: payload),
                            "commandSummary": commandSummary(in: payload),
                            "pathSummary": pathSummary(in: payload),
                            "requestedAt": now
                        ])
                    ])
                ]
            }
        case "notification":
            events = [
                sessionStarted(sessionID: sessionID, cwd: cwd, at: now),
                event(type: "statusUpdated", sessionID: sessionID, at: now, extra: [
                    "summary": stringValue(in: payload, keys: ["message", "title", "notification_type", "notificationType"]) ?? "Claude Code notification"
                ])
            ]
        case "stop", "sessionend":
            events = [event(type: "sessionStopped", sessionID: sessionID, at: now)]
        case "stopfailure":
            events = [event(type: "sessionFailed", sessionID: sessionID, at: now, extra: [
                "reason": stringValue(in: payload, keys: ["error", "error_details", "errorDetails", "message"]) ?? "Claude Code session failed"
            ])]
        default:
            events = []
        }

        return events.map { event in
            let eventType = event["type"] as? String
            let responseStyle: String? = {
                switch eventType {
                case "permissionRequested":
                    return "claudePermissionRequest"
                case "questionAsked":
                    return "claudeQuestion"
                default:
                    return nil
                }
            }()

            return compact([
                "id": UUID().uuidString,
                "event": event,
                "expectsResponse": responseStyle != nil,
                "responseStyle": responseStyle
            ])
        }
    }

    private static func event(type: String, sessionID: String, at: String, extra: [String: Any] = [:]) -> [String: Any] {
        var payload: [String: Any] = ["type": type, "sessionID": sessionID, "at": at]
        extra.forEach { payload[$0.key] = $0.value }
        return payload
    }

    private static func sessionStarted(sessionID: String, cwd: String?, at: String) -> [String: Any] {
        event(type: "sessionStarted", sessionID: sessionID, at: at, extra: [
            "tool": "claudeCode",
            "title": title(for: cwd),
            "cwd": cwd as Any
        ].compactNilValues())
    }

    private static func title(for cwd: String?) -> String {
        guard let cwd else { return "Claude Code" }
        let lastComponent = URL(fileURLWithPath: (cwd as NSString).expandingTildeInPath).lastPathComponent
        return lastComponent.isEmpty ? "Claude Code" : "Claude - \(lastComponent)"
    }

    private static func promptSummary(in payload: [String: Any]) -> String {
        let prompt = stringValue(in: payload, keys: ["prompt", "message"])
        return prompt.map { "Prompt: \(summarize($0, fallback: "Prompt submitted"))" } ?? "Prompt submitted"
    }

    private static func toolSummary(in payload: [String: Any], fallback: String) -> String {
        let tool = toolName(in: payload)
        if let command = commandSummary(in: payload), !command.isEmpty {
            return "\(tool): \(command)"
        }
        return tool == "tool" ? fallback : "Running \(tool)"
    }

    private static func toolName(in payload: [String: Any]) -> String {
        stringValue(in: payload, keys: ["tool_name", "toolName", "tool"]) ?? "tool"
    }

    private static func commandSummary(in payload: [String: Any]) -> String? {
        nestedStringValue(in: payload, containerKeys: ["tool_input", "toolInput", "input"], keys: ["command", "cmd", "description"])
    }

    private static func pathSummary(in payload: [String: Any]) -> String? {
        stringValue(in: payload, keys: ["cwd", "path", "file_path", "filePath"])
            ?? nestedStringValue(in: payload, containerKeys: ["tool_input", "toolInput", "input"], keys: ["path", "file_path", "filePath"])
    }

    private static func questionPrompt(in payload: [String: Any], at now: String) -> [String: Any]? {
        guard toolName(in: payload) == "AskUserQuestion" else { return nil }
        let question = nestedStringValue(
            in: payload,
            containerKeys: ["tool_input", "toolInput", "input"],
            keys: ["question", "prompt", "message"]
        ) ?? stringValue(in: payload, keys: ["prompt", "message"])
            ?? firstQuestionText(in: payload)
        guard let question, !question.isEmpty else { return nil }

        let options = questionOptions(in: payload)
        return [
            "id": stringValue(in: payload, keys: ["tool_use_id", "toolUseID", "question_id", "questionID"]) ?? UUID().uuidString,
            "title": firstQuestionHeader(in: payload) ?? "Claude Code question",
            "question": question,
            "options": options,
            "multiSelect": boolValue(in: payload, keys: ["multi_select", "multiSelect"]) ?? false,
            "allowsFreeform": options.isEmpty || (boolValue(in: payload, keys: ["allows_freeform", "allowsFreeform"]) ?? true),
            "askedAt": now
        ]
    }

    private static func questionOptions(in payload: [String: Any]) -> [[String: Any]] {
        let rawOptions = nestedArray(in: payload, containerKeys: ["tool_input", "toolInput", "input"], keys: ["options", "choices"])
            ?? arrayValue(in: payload, keys: ["options", "choices"])
            ?? firstQuestionOptions(in: payload)
            ?? []

        return rawOptions.enumerated().map { index, item in
            if let option = item as? String {
                return ["id": option, "label": option]
            }
            if let option = item as? [String: Any] {
                let label = stringValue(in: option, keys: ["label", "text", "value"])
                let id = stringValue(in: option, keys: ["id", "value", "label", "text"]) ?? label
                if let label, let id {
                    return ["id": id, "label": label]
                }
            }
            let fallback = "\(item)"
            return ["id": "option-\(index)", "label": fallback]
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

    private static func summarize(_ value: String?, fallback: String) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return fallback }
        guard value.count > 110 else { return value }
        let end = value.index(value.startIndex, offsetBy: 107)
        return "\(value[..<end])..."
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

    private static func compact(_ dictionary: [String: Any?]) -> [String: Any] {
        dictionary.reduce(into: [String: Any]()) { result, item in
            if let value = item.value {
                result[item.key] = value
            }
        }
    }
}

private extension Dictionary where Key == String, Value == Any {
    func compactNilValues() -> [String: Any] {
        reduce(into: [String: Any]()) { result, item in
            if let optional = item.value as? OptionalProtocol {
                if let value = optional.unwrapped {
                    result[item.key] = value
                }
            } else {
                result[item.key] = item.value
            }
        }
    }
}

private protocol OptionalProtocol {
    var unwrapped: Any? { get }
}

extension Optional: OptionalProtocol {
    var unwrapped: Any? {
        switch self {
        case let .some(value): value
        case .none: nil
        }
    }
}
