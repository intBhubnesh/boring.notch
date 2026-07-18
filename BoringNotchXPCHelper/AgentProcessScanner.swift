//
//  AgentProcessScanner.swift
//  BoringNotchXPCHelper
//

import Foundation

struct AgentProcessScanner {
    func runningAgentProcesses() throws -> [[String: Any]] {
        let rows = try processRows()
        let parentsByPID = Dictionary(uniqueKeysWithValues: rows.map { ($0.pid, $0) })

        return rows.compactMap { row in
            guard let tool = tool(for: row) else { return nil }
            let parent = parentsByPID[row.parentPID]
            var dictionary: [String: Any] = [
                "pid": row.pid,
                "parentPID": row.parentPID,
                "tool": tool,
                "executablePath": row.executablePath,
                "commandLine": row.commandLine,
            ]
            if let parent {
                dictionary["parentExecutablePath"] = parent.executablePath
            }
            return dictionary
        }
    }

    private func processRows() throws -> [ProcessRow] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,comm=,args=", "-ww"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else {
            return []
        }

        return output
            .split(separator: "\n")
            .compactMap { ProcessRow(line: String($0)) }
    }

    private func tool(for row: ProcessRow) -> String? {
        let executableName = URL(fileURLWithPath: row.executablePath).lastPathComponent.lowercased()
        let haystack = "\(row.executablePath) \(row.commandLine)".lowercased()

        if executableName == "codex" || haystack.contains("/openai.chatgpt-") && haystack.contains("/codex ") {
            return "codex"
        }
        if executableName == "claude" || haystack.contains("/anthropic.claude-code-") && haystack.contains("/claude ") {
            return "claudeCode"
        }
        return nil
    }
}

private struct ProcessRow {
    var pid: Int
    var parentPID: Int
    var executablePath: String
    var commandLine: String

    init?(line: String) {
        let parts = line.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard parts.count == 4,
              let pid = Int(parts[0]),
              let parentPID = Int(parts[1]) else {
            return nil
        }

        self.pid = pid
        self.parentPID = parentPID
        self.executablePath = String(parts[2])
        self.commandLine = String(parts[3])
    }
}
