//
//  AgentTool.swift
//  boringNotch
//
//  Agent Activity Integration — model design adapted from
//  Octane0411/open-vibe-island (GPL v3).
//

import Foundation

enum AgentTool: String, Codable, Sendable, Hashable, CaseIterable {
    case codex
    case claudeCode
    case cursor
    case gemini
    case openCode
    case kimi
    case other

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        case .cursor: "Cursor"
        case .gemini: "Gemini CLI"
        case .openCode: "OpenCode"
        case .kimi: "Kimi CLI"
        case .other: "Agent"
        }
    }

    var sfSymbol: String {
        switch self {
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .claudeCode: "sparkles"
        case .cursor: "cursorarrow.rays"
        case .gemini: "diamond"
        case .openCode: "terminal"
        case .kimi: "moon.stars"
        case .other: "terminal"
        }
    }
}
