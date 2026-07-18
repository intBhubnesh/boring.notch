//
//  QuestionPrompt.swift
//  boringNotch
//
//  Agent Activity Integration — model design adapted from
//  Octane0411/open-vibe-island (GPL v3).
//

import Foundation

struct QuestionOption: Codable, Sendable, Hashable, Identifiable {
    let id: String
    var label: String
}

struct QuestionPrompt: Codable, Sendable, Hashable, Identifiable {
    let id: String
    var title: String
    var question: String
    var options: [QuestionOption]
    var multiSelect: Bool
    var allowsFreeform: Bool
    var askedAt: Date
}

struct QuestionPromptResponse: Codable, Sendable, Hashable {
    var selectedOptionIDs: [String] = []
    var freeformText: String?
}
