//
//  SessionPhase.swift
//  boringNotch
//
//  Agent Activity Integration — model design adapted from
//  Octane0411/open-vibe-island (GPL v3).
//

import Foundation

enum SessionPhase: String, Codable, Sendable, Hashable {
    case starting
    case running
    case waitingForApproval
    case waitingForAnswer
    case completed
    case failed

    var isActionable: Bool {
        self == .waitingForApproval || self == .waitingForAnswer
    }

    var isRunning: Bool {
        isActionable || self == .starting || self == .running
    }

    var displayLabel: String {
        switch self {
        case .starting: "Starting"
        case .running: "Running"
        case .waitingForApproval: "Needs approval"
        case .waitingForAnswer: "Needs answer"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }
}
