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
    var hostApplication: String?
    var pid: Int?
    var tty: String?
    var activeFilePath: String?
    var phase: SessionPhase
    var summary: String
    var pendingPermission: PermissionRequest?
    var pendingQuestion: QuestionPrompt?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case tool
        case title
        case cwd
        case hostApplication
        case pid
        case tty
        case activeFilePath
        case phase
        case summary
        case pendingPermission
        case pendingQuestion
        case createdAt
        case updatedAt
    }

    init(
        id: String,
        tool: AgentTool,
        title: String,
        cwd: String?,
        hostApplication: String? = nil,
        pid: Int? = nil,
        tty: String? = nil,
        activeFilePath: String? = nil,
        phase: SessionPhase,
        summary: String,
        pendingPermission: PermissionRequest?,
        pendingQuestion: QuestionPrompt?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.tool = tool
        self.title = title
        self.cwd = cwd
        self.hostApplication = hostApplication
        self.pid = pid
        self.tty = tty
        self.activeFilePath = activeFilePath
        self.phase = phase
        self.summary = summary
        self.pendingPermission = pendingPermission
        self.pendingQuestion = pendingQuestion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        tool = try container.decode(AgentTool.self, forKey: .tool)
        title = try container.decode(String.self, forKey: .title)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        hostApplication = try container.decodeIfPresent(String.self, forKey: .hostApplication)
        pid = try container.decodeIfPresent(Int.self, forKey: .pid)
        tty = try container.decodeIfPresent(String.self, forKey: .tty)
        activeFilePath = try container.decodeIfPresent(String.self, forKey: .activeFilePath)
        phase = try container.decode(SessionPhase.self, forKey: .phase)
        summary = try container.decode(String.self, forKey: .summary)
        pendingPermission = try container.decodeIfPresent(PermissionRequest.self, forKey: .pendingPermission)
        pendingQuestion = try container.decodeIfPresent(QuestionPrompt.self, forKey: .pendingQuestion)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
