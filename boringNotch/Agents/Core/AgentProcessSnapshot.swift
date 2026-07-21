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
    var hostApplication: String? = nil
    var tty: String? = nil
    var observedAt: Date

    var sessionID: String {
        "process:\(tool.rawValue):\(pid)"
    }

    var title: String {
        let folder = cwd.flatMap(Self.folderName)
        if let folder, !folder.isEmpty {
            return folder
        }
        if let resumeID = Self.resumeID(in: commandLine) {
            return "\(tool.displayName) \(resumeID)"
        }
        return "\(tool.displayName) #\(pid)"
    }

    var summary: String {
        if let folder = cwd.flatMap(Self.folderName), !folder.isEmpty {
            return "Idle in \(folder)"
        }
        return "Idle"
    }

    private static func folderName(_ path: String) -> String? {
        let expandedPath = (path as NSString).expandingTildeInPath
        let lastComponent = URL(fileURLWithPath: expandedPath).lastPathComponent
        return lastComponent.isEmpty ? nil : lastComponent
    }

    private static func resumeID(in commandLine: String) -> String? {
        guard let range = commandLine.range(of: "--resume=") else { return nil }
        let suffix = commandLine[range.upperBound...]
        let id = suffix.prefix { !$0.isWhitespace }
        guard id.count >= 8 else { return nil }
        return String(id.prefix(8))
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
            hostApplication: xpcDictionary["hostApplication"] as? String,
            tty: xpcDictionary["tty"] as? String,
            observedAt: observedAt
        )
    }
}
