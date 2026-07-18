//
//  AgentProcessSnapshot.swift
//  boringNotch
//

import Foundation

struct AgentProcessSnapshot: Sendable, Hashable {
    var pid: Int
    var parentPID: Int
    var tool: AgentTool
    var executablePath: String
    var commandLine: String
    var parentExecutablePath: String?
    var cwd: String?
    var observedAt: Date

    var sessionID: String {
        "process:\(tool.rawValue):\(pid)"
    }

    var title: String {
        "\(tool.displayName) #\(pid)"
    }

    var summary: String {
        let host: String
        let haystack = "\(executablePath) \(commandLine) \(parentExecutablePath ?? "")".lowercased()
        if haystack.contains(".vscode/extensions") || haystack.contains("visual studio code") {
            host = "VS Code"
        } else if haystack.contains("/terminal.app/") || haystack.contains("/iterm.app/") || haystack.contains("/warp.app/") {
            host = "terminal"
        } else {
            host = "process list"
        }
        return "Detected from \(host)"
    }
}

extension AgentProcessSnapshot {
    init?(xpcDictionary: [String: Any], observedAt: Date = Date()) {
        guard let pid = xpcDictionary["pid"] as? Int,
              let parentPID = xpcDictionary["parentPID"] as? Int,
              let toolValue = xpcDictionary["tool"] as? String,
              let tool = AgentTool(rawValue: toolValue),
              let executablePath = xpcDictionary["executablePath"] as? String,
              let commandLine = xpcDictionary["commandLine"] as? String else {
            return nil
        }

        self.init(
            pid: pid,
            parentPID: parentPID,
            tool: tool,
            executablePath: executablePath,
            commandLine: commandLine,
            parentExecutablePath: xpcDictionary["parentExecutablePath"] as? String,
            cwd: xpcDictionary["cwd"] as? String,
            observedAt: observedAt
        )
    }
}
