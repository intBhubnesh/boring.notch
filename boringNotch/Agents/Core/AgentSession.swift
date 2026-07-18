//
//  AgentSession.swift
//  boringNotch
//
//  Agent Activity Integration — model design adapted from
//  Octane0411/open-vibe-island (GPL v3).
//

import Foundation

struct AgentSession: Codable, Sendable, Hashable, Identifiable {
    let id: String
    var tool: AgentTool
    var title: String
    var cwd: String?
    var phase: SessionPhase
    var summary: String
    var pendingPermission: PermissionRequest?
    var pendingQuestion: QuestionPrompt?
    var createdAt: Date
    var updatedAt: Date
}
