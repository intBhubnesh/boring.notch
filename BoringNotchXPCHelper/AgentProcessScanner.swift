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
            let ancestors = ancestry(for: row, in: parentsByPID)
            let parent = ancestors.first
            var dictionary: [String: Any] = [
                "pid": row.pid,
                "parentPID": row.parentPID,
                "tool": tool,
                "executablePath": row.executablePath,
                "commandLine": row.commandLine,
                "hostApplication": hostApplication(for: row, ancestors: ancestors),
            ]
            if let parent {
                dictionary["parentExecutablePath"] = parent.executablePath
                dictionary["parentCommandLine"] = parent.commandLine
            }
            if let cwd = cwd(for: row.pid), cwd != "/" {
                dictionary["cwd"] = cwd
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
        if executableName == "gemini" || haystack.contains("/gemini ") || haystack.hasSuffix("/gemini") {
            return "gemini"
        }
        if executableName == "opencode" || haystack.contains("/opencode ") || haystack.hasSuffix("/opencode") {
            return "openCode"
        }
        if executableName == "kimi" || executableName == "kimi-code" || haystack.contains("/kimi ") || haystack.contains("/kimi-code ") {
            return "kimi"
        }
        if executableName == "cursor-agent" || haystack.contains("/cursor-agent ") {
            return "cursor"
        }
        return nil
    }

    private func ancestry(for row: ProcessRow, in parentsByPID: [Int: ProcessRow]) -> [ProcessRow] {
        var ancestors: [ProcessRow] = []
        var visited = Set<Int>()
        var parentPID = row.parentPID

        while let parent = parentsByPID[parentPID], !visited.contains(parent.pid) {
            ancestors.append(parent)
            visited.insert(parent.pid)
            parentPID = parent.parentPID
        }

        return ancestors
    }

    private func hostApplication(for row: ProcessRow, ancestors: [ProcessRow]) -> String {
        let haystack = ([row] + ancestors)
            .map { "\($0.executablePath) \($0.commandLine)" }
            .joined(separator: " ")
            .lowercased()

        if haystack.contains(".vscode/extensions") || haystack.contains("visual studio code.app") {
            return "VS Code"
        }
        if haystack.contains(".cursor/extensions") || haystack.contains("/cursor.app/") {
            return "Cursor"
        }
        if haystack.contains("/kitty.app/") || haystack.contains("/kitten ") {
            return "Kitty"
        }
        if haystack.contains("/ghostty.app/") || haystack.contains("/ghostty ") {
            return "Ghostty"
        }
        if haystack.contains("/iterm.app/") || haystack.contains("/iterm2.app/") {
            return "iTerm"
        }
        if haystack.contains("/warp.app/") {
            return "Warp"
        }
        if haystack.contains("/wezterm.app/") || haystack.contains("/wezterm ") {
            return "WezTerm"
        }
        if haystack.contains("/terminal.app/") {
            return "Terminal"
        }

        return ancestors
            .lazy
            .compactMap { appName(in: $0.commandLine) ?? appName(in: $0.executablePath) }
            .first ?? "Other app"
    }

    private func appName(in value: String) -> String? {
        guard let appRange = value.range(of: ".app") else { return nil }
        let beforeApp = value[..<appRange.lowerBound]
        guard let slash = beforeApp.lastIndex(of: "/") else { return nil }
        let name = beforeApp[beforeApp.index(after: slash)...]
        return name.isEmpty ? nil : String(name)
    }

    private func cwd(for pid: Int) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else {
            return nil
        }

        return output
            .split(separator: "\n")
            .first { $0.hasPrefix("n") }
            .map { String($0.dropFirst()) }
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
