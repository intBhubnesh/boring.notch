//
//  BridgeServer.swift
//  boringNotch
//
//  Newline-delimited JSON bridge for local agent hook events.
//

import Darwin
import Foundation

final class BridgeServer: @unchecked Sendable {
    typealias EventHandler = @Sendable (AgentEvent) -> Void

    private struct PendingResponse {
        let clientFD: Int32
        let messageID: String
        let requestID: String?
        let questionID: String?
        let style: AgentBridgeResponseStyle
        let responseContext: String?
    }

    private let socketPath: String
    private let eventHandler: EventHandler
    private let queue = DispatchQueue(label: "boring.notch.agent.bridge")
    private var listenFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var pendingResponses: [String: PendingResponse] = [:]

    init(socketPath: String = AgentBridgeTransport.socketPath, eventHandler: @escaping EventHandler) {
        self.socketPath = socketPath
        self.eventHandler = eventHandler
    }

    deinit {
        stop()
    }

    func start() throws {
        guard listenFD < 0 else { return }

        signal(SIGPIPE, SIG_IGN)

        let socketURL = URL(fileURLWithPath: socketPath)
        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let sunPathSize = MemoryLayout.size(ofValue: address.sun_path)
        try socketPath.withCString { pathPointer in
            guard strlen(pathPointer) < sunPathSize else {
                throw POSIXError(.ENAMETOOLONG)
            }
            withUnsafeMutablePointer(to: &address.sun_path) { destination in
                destination.withMemoryRebound(to: CChar.self, capacity: sunPathSize) {
                    strcpy($0, pathPointer)
                }
            }
        }

        let addressLength = socklen_t(MemoryLayout<sa_family_t>.size + strlen(socketPath) + 1)
        let didBind = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, addressLength)
            }
        }
        guard didBind == 0 else {
            close(fd)
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        chmod(socketPath, 0o666)

        guard listen(fd, 16) == 0 else {
            close(fd)
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        setNonBlocking(fd)
        listenFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptAvailableConnections()
        }
        source.setCancelHandler { close(fd) }
        readSource = source
        source.resume()
    }

    func stop() {
        readSource?.cancel()
        readSource = nil
        listenFD = -1
        for pending in pendingResponses.values {
            close(pending.clientFD)
        }
        pendingResponses.removeAll()
        unlink(socketPath)
    }

    func resolvePermission(sessionID: String, requestID: String, resolution: PermissionResolution) {
        queue.async { [weak self] in
            guard let self,
                  let pending = self.pendingResponses.removeValue(forKey: sessionID),
                  pending.requestID == requestID else {
                return
            }

            let response = AgentBridgeResponse(stdout: Self.stdout(for: resolution, style: pending.style))
            self.send(response, to: pending.clientFD)
            close(pending.clientFD)
        }
    }

    func answerQuestion(sessionID: String, questionID: String, response: QuestionPromptResponse) {
        queue.async { [weak self] in
            guard let self,
                  let pending = self.pendingResponses.removeValue(forKey: sessionID),
                  pending.questionID == questionID else {
                return
            }

            let response = AgentBridgeResponse(stdout: Self.stdout(
                for: response,
                style: pending.style,
                responseContext: pending.responseContext
            ))
            self.send(response, to: pending.clientFD)
            close(pending.clientFD)
        }
    }

    private func acceptAvailableConnections() {
        while true {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 {
                if errno == EWOULDBLOCK || errno == EAGAIN { return }
                return
            }

            disableSigPipe(clientFD)
            queue.async { [weak self] in
                self?.handleClient(clientFD)
            }
        }
    }

    private func handleClient(_ clientFD: Int32) {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let count = Darwin.read(clientFD, &buffer, buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
                if data.contains(0x0A) {
                    break
                }
            } else {
                break
            }
        }

        guard !data.isEmpty else {
            close(clientFD)
            return
        }

        let chunks = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        var shouldKeepOpen = false
        for chunk in chunks {
            do {
                let message = try AgentBridgeTransport.decoder.decode(AgentBridgeMessage.self, from: Data(chunk))
                let event = try message.event.toAgentEvent()
                eventHandler(event)

                if message.expectsResponse,
                   let style = message.responseStyle,
                   let pending = pendingResponse(for: message, style: style, clientFD: clientFD) {
                    pendingResponses[message.event.sessionID] = pending
                    shouldKeepOpen = true
                }
            } catch {
                // Hooks must fail open. Bad payloads are ignored rather than blocking agent execution.
                continue
            }
        }

        if !shouldKeepOpen {
            close(clientFD)
        }
    }

    private func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }

    private func disableSigPipe(_ fd: Int32) {
        var value: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &value, socklen_t(MemoryLayout<Int32>.size))
    }

    private func pendingResponse(
        for message: AgentBridgeMessage,
        style: AgentBridgeResponseStyle,
        clientFD: Int32
    ) -> PendingResponse? {
        switch message.event.type {
        case .permissionRequested:
            guard let requestID = message.event.permissionRequest?.id else { return nil }
            return PendingResponse(
                clientFD: clientFD,
                messageID: message.id,
                requestID: requestID,
                questionID: nil,
                style: style,
                responseContext: message.responseContext
            )
        case .questionAsked:
            guard let questionID = message.event.questionPrompt?.id else { return nil }
            return PendingResponse(
                clientFD: clientFD,
                messageID: message.id,
                requestID: nil,
                questionID: questionID,
                style: style,
                responseContext: message.responseContext
            )
        default:
            return nil
        }
    }

    private func send(_ response: AgentBridgeResponse, to clientFD: Int32) {
        guard let data = try? AgentBridgeTransport.encoder.encode(response) + Data([0x0A]) else { return }
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let count = Darwin.send(clientFD, baseAddress.advanced(by: sent), data.count - sent, 0)
                guard count > 0 else { return }
                sent += count
            }
        }
    }

    private static func stdout(for resolution: PermissionResolution, style: AgentBridgeResponseStyle) -> String? {
        switch style {
        case .codexPermissionRequest:
            return codexPermissionStdout(resolution: resolution)
        case .claudePermissionRequest, .claudeQuestion, .claudePreToolUseQuestion, .claudePreToolUsePlan:
            return claudePermissionStdout(resolution: resolution)
        }
    }

    private static func stdout(
        for response: QuestionPromptResponse,
        style: AgentBridgeResponseStyle,
        responseContext: String?
    ) -> String? {
        switch style {
        case .claudeQuestion:
            return claudeQuestionStdout(response: response)
        case .claudePreToolUseQuestion:
            return claudePreToolUseQuestionStdout(response: response, responseContext: responseContext)
        case .claudePreToolUsePlan:
            return claudePreToolUsePlanStdout(response: response, responseContext: responseContext)
        case .codexPermissionRequest, .claudePermissionRequest:
            return nil
        }
    }

    private static func codexPermissionStdout(resolution: PermissionResolution) -> String {
        let behavior = resolution == .allow ? "allow" : "deny"
        var decision: [String: Any] = ["behavior": behavior]
        if resolution == .deny {
            decision["message"] = "Denied in Boring Notch."
        }
        return jsonLine([
            "continue": true,
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decision,
            ],
        ])
    }

    private static func claudePermissionStdout(resolution: PermissionResolution) -> String {
        let behavior = resolution == .allow ? "allow" : "deny"
        var decision: [String: Any] = ["behavior": behavior]
        if resolution == .deny {
            decision["message"] = "Denied in Boring Notch."
            decision["interrupt"] = true
        }
        return jsonLine([
            "continue": true,
            "suppressOutput": true,
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decision,
            ],
        ])
    }

    private static func claudeQuestionStdout(response: QuestionPromptResponse) -> String {
        let answerParts = response.selectedOptionIDs + [response.freeformText].compactMap { $0 }
        let answer = answerParts.joined(separator: ", ")
        return jsonLine([
            "continue": true,
            "suppressOutput": true,
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": [
                    "behavior": "allow",
                    "updatedInput": [
                        "answer": answer,
                        "answers": answerParts,
                    ],
                ],
            ],
        ])
    }

    private static func claudePreToolUseQuestionStdout(response: QuestionPromptResponse, responseContext: String?) -> String {
        let toolInput = responseContext.flatMap(Self.toolInput(from:)) ?? [:]
        let answerParts = response.selectedOptionIDs + [response.freeformText].compactMap { $0 }
        let answer = answerParts.joined(separator: ", ")
        var updatedInput = toolInput
        updatedInput["answers"] = answersObject(for: toolInput, fallbackAnswer: answer)

        return preToolUseStdout(permissionDecision: "allow", updatedInput: updatedInput)
    }

    private static func claudePreToolUsePlanStdout(response: QuestionPromptResponse, responseContext: String?) -> String {
        let selected = Set(response.selectedOptionIDs.map { $0.lowercased() })
        if selected.contains("reject") || selected.contains("deny") {
            return preToolUseStdout(
                permissionDecision: "deny",
                permissionDecisionReason: response.freeformText ?? "Plan rejected in Boring Notch.",
                updatedInput: nil
            )
        }

        return preToolUseStdout(
            permissionDecision: "allow",
            updatedInput: responseContext.flatMap(Self.toolInput(from:)) ?? [:]
        )
    }

    private static func preToolUseStdout(
        permissionDecision: String,
        permissionDecisionReason: String? = nil,
        updatedInput: [String: Any]?
    ) -> String {
        var output: [String: Any] = [
            "hookEventName": "PreToolUse",
            "permissionDecision": permissionDecision,
        ]
        if let permissionDecisionReason {
            output["permissionDecisionReason"] = permissionDecisionReason
        }
        if let updatedInput {
            output["updatedInput"] = updatedInput
        }
        return jsonLine([
            "continue": true,
            "suppressOutput": true,
            "hookSpecificOutput": output,
        ])
    }

    private static func toolInput(from responseContext: String) -> [String: Any]? {
        guard let data = responseContext.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let context = object as? [String: Any] else {
            return nil
        }
        return context["toolInput"] as? [String: Any]
    }

    private static func answersObject(for toolInput: [String: Any], fallbackAnswer: String) -> [String: Any] {
        guard let questions = toolInput["questions"] as? [[String: Any]], !questions.isEmpty else {
            return ["answer": fallbackAnswer]
        }

        var answers: [String: Any] = [:]
        for question in questions {
            guard let questionText = question["question"] as? String, !questionText.isEmpty else { continue }
            answers[questionText] = fallbackAnswer
        }
        return answers
    }

    private static func jsonLine(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}\n"
        }
        return "\(string)\n"
    }
}
