//
//  PermissionRequest.swift
//  boringNotch
//
//  Agent Activity Integration — model design adapted from
//  Octane0411/open-vibe-island (GPL v3).
//

import Foundation

struct PermissionRequest: Codable, Sendable, Hashable, Identifiable {
    let id: String
    var toolName: String
    var commandSummary: String?
    var pathSummary: String?
    var requestedAt: Date
}

enum PermissionResolution: String, Codable, Sendable, Hashable {
    case allow
    case deny
}
