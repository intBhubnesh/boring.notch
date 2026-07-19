//
//  AgentTool.swift
//  boringNotch
//
//  Agent Activity Integration — model design adapted from
//  Octane0411/open-vibe-island (GPL v3).
//

import Foundation
import SwiftUI

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

    var accentColor: Color {
        switch self {
        case .codex: Color(red: 0.35, green: 0.61, blue: 1.0)
        case .claudeCode: Color(red: 1.0, green: 0.53, blue: 0.22)
        case .cursor: Color(red: 0.69, green: 0.49, blue: 1.0)
        case .gemini: Color(red: 0.31, green: 0.84, blue: 0.55)
        case .openCode: Color(red: 0.96, green: 0.78, blue: 0.28)
        case .kimi: Color(red: 0.57, green: 0.75, blue: 1.0)
        case .other: Color.gray
        }
    }
}
