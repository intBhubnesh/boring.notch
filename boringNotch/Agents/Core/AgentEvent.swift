//
//  AgentEvent.swift
//  boringNotch
//
//  Agent Activity Integration — model design adapted from
//  Octane0411/open-vibe-island (GPL v3).
//
//  AgentEvent is the single input type SessionState.apply(_:) consumes.
//  Later phases will produce these from the local IPC bridge; this phase
//  produces them from AgentActivityManager's synthetic demo sessions.

import Foundation

enum AgentEvent: Codable, Sendable, Hashable {
    case sessionStarted(sessionID: String, tool: AgentTool, title: String, cwd: String?, at: Date)
    case promptSubmitted(sessionID: String, summary: String, at: Date)
    case statusUpdated(sessionID: String, summary: String, at: Date)
    case permissionRequested(sessionID: String, request: PermissionRequest)
    case permissionResolved(sessionID: String, requestID: String, resolution: PermissionResolution, at: Date)
    case questionAsked(sessionID: String, prompt: QuestionPrompt)
    case questionAnswered(sessionID: String, questionID: String, response: QuestionPromptResponse, at: Date)
    case sessionStopped(sessionID: String, at: Date)
    case sessionFailed(sessionID: String, reason: String?, at: Date)
}
