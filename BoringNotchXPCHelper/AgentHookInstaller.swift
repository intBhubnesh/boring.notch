//
//  AgentHookInstaller.swift
//  BoringNotchXPCHelper
//

import Foundation

struct AgentHookStatus {
    var state: String
    var detail: String
    var configPath: String
    var hookBinaryPath: String?

    var xpcDictionary: [String: Any] {
        var dictionary: [String: Any] = [
            "state": state,
            "detail": detail,
            "configPath": configPath,
        ]
        if let hookBinaryPath {
            dictionary["hookBinaryPath"] = hookBinaryPath
        }
        return dictionary
    }
}

enum AgentHookInstallerError: Error, LocalizedError {
    case hookSourceMissing
    case invalidJSON(URL)
    case unsupportedTool

    var errorDescription: String? {
        switch self {
        case .hookSourceMissing:
            "Could not find the bundled Boring Notch agent hook helper."
        case let .invalidJSON(url):
            "Could not read existing JSON config at \(url.path)."
        case .unsupportedTool:
            "Hook installation is only implemented for Codex and Claude Code."
        }
    }
}

struct AgentHookInstaller {
    private let fileManager = FileManager.default

    func status(for tool: String, configRootPath: String) throws -> AgentHookStatus {
        switch normalizedTool(tool) {
        case "codex":
            return try codexStatus(configRootPath: configRootPath)
        case "claude":
            return try claudeStatus(configRootPath: configRootPath)
        default:
            throw AgentHookInstallerError.unsupportedTool
        }
    }

    func install(tool: String, hookBinarySourcePath: String, configRootPath: String) throws -> AgentHookStatus {
        switch normalizedTool(tool) {
        case "codex":
            return try installCodex(hookBinarySourcePath: hookBinarySourcePath, configRootPath: configRootPath)
        case "claude":
            return try installClaude(hookBinarySourcePath: hookBinarySourcePath, configRootPath: configRootPath)
        default:
            throw AgentHookInstallerError.unsupportedTool
        }
    }

    func uninstall(tool: String, configRootPath: String) throws -> AgentHookStatus {
        switch normalizedTool(tool) {
        case "codex":
            return try uninstallCodex(configRootPath: configRootPath)
        case "claude":
            return try uninstallClaude(configRootPath: configRootPath)
        default:
            throw AgentHookInstallerError.unsupportedTool
        }
    }

    private func codexStatus(configRootPath: String) throws -> AgentHookStatus {
        let directory = codexDirectory(configRootPath: configRootPath)
        let configURL = directory.appendingPathComponent("config.toml")
        let hooksURL = directory.appendingPathComponent("hooks.json")
        let manifest = loadManifest(directory.appendingPathComponent("boring-notch-hooks-install.json"))
        let command = manifest?.hookCommand
        let installed = containsManagedHook(in: try? Data(contentsOf: hooksURL), managedCommand: command)
        let featureEnabled = isCodexFeatureEnabled((try? String(contentsOf: configURL, encoding: .utf8)) ?? "")
        let binaryURL = manifest.map { URL(fileURLWithPath: $0.hookBinaryPath) }
        let binaryOK = binaryURL.map { fileManager.isExecutableFile(atPath: $0.path) } ?? false

        if installed && featureEnabled && binaryOK {
            return AgentHookStatus(state: "installed", detail: "Installed. Run /hooks in Codex if it asks for trust review.", configPath: directory.path, hookBinaryPath: binaryURL?.path)
        }
        if installed || featureEnabled || manifest != nil {
            let missing = missingParts([
                ("hook config", installed),
                ("hooks feature flag", featureEnabled),
                ("helper binary", binaryOK),
            ])
            return AgentHookStatus(state: "needsAttention", detail: "Needs repair: \(missing).", configPath: directory.path, hookBinaryPath: binaryURL?.path)
        }
        return AgentHookStatus(state: "notInstalled", detail: "Not installed", configPath: directory.path, hookBinaryPath: nil)
    }

    private func claudeStatus(configRootPath: String) throws -> AgentHookStatus {
        let settingsURL = claudeSettingsURL(configRootPath: configRootPath)
        let directory = settingsURL.deletingLastPathComponent()
        let manifest = loadManifest(directory.appendingPathComponent("boring-notch-claude-hooks-install.json"))
        let command = manifest?.hookCommand
        let installed = containsManagedHook(in: try? Data(contentsOf: settingsURL), managedCommand: command)
        let binaryURL = manifest.map { URL(fileURLWithPath: $0.hookBinaryPath) }
        let binaryOK = binaryURL.map { fileManager.isExecutableFile(atPath: $0.path) } ?? false

        if installed && binaryOK {
            return AgentHookStatus(state: "installed", detail: "Installed", configPath: settingsURL.path, hookBinaryPath: binaryURL?.path)
        }
        if installed || manifest != nil {
            let missing = missingParts([
                ("hook config", installed),
                ("helper binary", binaryOK),
            ])
            return AgentHookStatus(state: "needsAttention", detail: "Needs repair: \(missing).", configPath: settingsURL.path, hookBinaryPath: binaryURL?.path)
        }
        return AgentHookStatus(state: "notInstalled", detail: "Not installed", configPath: settingsURL.path, hookBinaryPath: nil)
    }

    private func installCodex(hookBinarySourcePath: String, configRootPath: String) throws -> AgentHookStatus {
        let binaryURL = try installHookBinary(from: hookBinarySourcePath)
        let directory = codexDirectory(configRootPath: configRootPath)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let configURL = directory.appendingPathComponent("config.toml")
        let hooksURL = directory.appendingPathComponent("hooks.json")
        let command = shellQuote(binaryURL.path)

        let oldConfig = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let newConfig = enableCodexFeature(oldConfig)
        if newConfig != oldConfig {
            try backupIfNeeded(configURL)
            try newConfig.write(to: configURL, atomically: true, encoding: .utf8)
        }

        let newHooks = try installJSONHooks(
            existingData: try? Data(contentsOf: hooksURL),
            specs: [
                HookSpec(name: "SessionStart", matcher: "startup|resume", timeout: 45),
                HookSpec(name: "UserPromptSubmit", matcher: nil, timeout: 45),
                HookSpec(name: "PreToolUse", matcher: nil, timeout: 45),
                HookSpec(name: "PostToolUse", matcher: nil, timeout: 45),
                HookSpec(name: "PermissionRequest", matcher: nil, timeout: 86_400),
                HookSpec(name: "Stop", matcher: nil, timeout: 45),
            ],
            command: command
        )
        try backupIfNeeded(hooksURL)
        try newHooks.write(to: hooksURL, options: .atomic)
        try saveManifest(AgentHookManifest(hookCommand: command, hookBinaryPath: binaryURL.path), to: directory.appendingPathComponent("boring-notch-hooks-install.json"))
        return try codexStatus(configRootPath: configRootPath)
    }

    private func uninstallCodex(configRootPath: String) throws -> AgentHookStatus {
        let directory = codexDirectory(configRootPath: configRootPath)
        let hooksURL = directory.appendingPathComponent("hooks.json")
        let manifestURL = directory.appendingPathComponent("boring-notch-hooks-install.json")
        let manifest = loadManifest(manifestURL)
        let mutation = try uninstallJSONHooks(
            existingData: try? Data(contentsOf: hooksURL),
            eventNames: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop"],
            managedCommand: manifest?.hookCommand
        )
        try backupIfNeeded(hooksURL)
        if let data = mutation {
            try data.write(to: hooksURL, options: .atomic)
        } else if fileManager.fileExists(atPath: hooksURL.path) {
            try fileManager.removeItem(at: hooksURL)
        }
        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }
        return try codexStatus(configRootPath: configRootPath)
    }

    private func installClaude(hookBinarySourcePath: String, configRootPath: String) throws -> AgentHookStatus {
        let binaryURL = try installHookBinary(from: hookBinarySourcePath)
        let settingsURL = claudeSettingsURL(configRootPath: configRootPath)
        let directory = settingsURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let command = "\(shellQuote(binaryURL.path)) --source claude"
        let specs = [
            HookSpec(name: "UserPromptSubmit", matcher: nil, timeout: nil),
            HookSpec(name: "SessionStart", matcher: nil, timeout: nil),
            HookSpec(name: "SessionEnd", matcher: nil, timeout: nil),
            HookSpec(name: "Stop", matcher: nil, timeout: nil),
            HookSpec(name: "StopFailure", matcher: nil, timeout: nil),
            HookSpec(name: "SubagentStart", matcher: nil, timeout: nil),
            HookSpec(name: "SubagentStop", matcher: nil, timeout: nil),
            HookSpec(name: "Notification", matcher: "*", timeout: nil),
            HookSpec(name: "PreToolUse", matcher: "*", timeout: 86_400),
            HookSpec(name: "PermissionRequest", matcher: "*", timeout: 86_400),
            HookSpec(name: "PostToolUse", matcher: "*", timeout: nil),
            HookSpec(name: "PostToolUseFailure", matcher: "*", timeout: nil),
            HookSpec(name: "PermissionDenied", matcher: "*", timeout: nil),
            HookSpec(name: "PreCompact", matcher: nil, timeout: nil),
        ]
        let newSettings = try installJSONHooks(existingData: try? Data(contentsOf: settingsURL), specs: specs, command: command)
        try backupIfNeeded(settingsURL)
        try newSettings.write(to: settingsURL, options: .atomic)
        try saveManifest(AgentHookManifest(hookCommand: command, hookBinaryPath: binaryURL.path), to: directory.appendingPathComponent("boring-notch-claude-hooks-install.json"))
        return try claudeStatus(configRootPath: configRootPath)
    }

    private func uninstallClaude(configRootPath: String) throws -> AgentHookStatus {
        let settingsURL = claudeSettingsURL(configRootPath: configRootPath)
        let directory = settingsURL.deletingLastPathComponent()
        let manifestURL = directory.appendingPathComponent("boring-notch-claude-hooks-install.json")
        let manifest = loadManifest(manifestURL)
        let mutation = try uninstallJSONHooks(
            existingData: try? Data(contentsOf: settingsURL),
            eventNames: [
                "UserPromptSubmit", "SessionStart", "SessionEnd", "Stop", "StopFailure",
                "SubagentStart", "SubagentStop", "Notification", "PreToolUse", "PermissionRequest",
                "PostToolUse", "PostToolUseFailure", "PermissionDenied", "PreCompact",
            ],
            managedCommand: manifest?.hookCommand
        )
        try backupIfNeeded(settingsURL)
        if let data = mutation {
            try data.write(to: settingsURL, options: .atomic)
        } else if fileManager.fileExists(atPath: settingsURL.path) {
            try fileManager.removeItem(at: settingsURL)
        }
        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }
        return try claudeStatus(configRootPath: configRootPath)
    }

    private func installHookBinary(from sourcePath: String) throws -> URL {
        let destination = home("Library/Application Support/boringNotch/AgentHooks/BoringNotchAgentHooks")
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let sourceURL = URL(fileURLWithPath: sourcePath)
        guard fileManager.isExecutableFile(atPath: sourceURL.path) else {
            throw AgentHookInstallerError.hookSourceMissing
        }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        return destination
    }

    private func installJSONHooks(existingData: Data?, specs: [HookSpec], command: String) throws -> Data {
        var root = (try? jsonRoot(existingData)) ?? [:]
        let existingHooks = root["hooks"] as? [String: Any] ?? [:]
        var hooks: [String: Any] = [:]

        for (eventName, value) in existingHooks {
            let groups = value as? [Any] ?? []
            let cleaned = sanitize(groups: groups, managedCommand: command)
            if !cleaned.isEmpty {
                hooks[eventName] = cleaned
            }
        }

        for spec in specs {
            let existing = hooks[spec.name] as? [Any] ?? []
            hooks[spec.name] = existing + [managedGroup(spec: spec, command: command)]
        }

        root["hooks"] = hooks
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    private func uninstallJSONHooks(existingData: Data?, eventNames: [String], managedCommand: String?) throws -> Data? {
        guard existingData != nil else { return nil }
        var root = (try? jsonRoot(existingData)) ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for eventName in eventNames {
            let groups = hooks[eventName] as? [Any] ?? []
            let cleaned = sanitize(groups: groups, managedCommand: managedCommand)
            if cleaned.isEmpty {
                hooks.removeValue(forKey: eventName)
            } else {
                hooks[eventName] = cleaned
            }
        }

        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        guard !root.isEmpty else { return nil }
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    private func jsonRoot(_ data: Data?) throws -> [String: Any] {
        guard let data else { return [:] }
        let parseData: Data
        if let contents = String(data: data, encoding: .utf8) {
            parseData = Data(stripJSONComments(contents).utf8)
        } else {
            parseData = data
        }
        let object = try JSONSerialization.jsonObject(with: parseData)
        guard let root = object as? [String: Any] else {
            throw AgentHookInstallerError.invalidJSON(URL(fileURLWithPath: "config"))
        }
        return root
    }

    private func containsManagedHook(in data: Data?, managedCommand: String?) -> Bool {
        guard let root = try? jsonRoot(data),
              let hooks = root["hooks"] as? [String: Any] else {
            return false
        }
        return hooks.values.contains { value in
            let groups = value as? [Any] ?? []
            return groups.contains { item in
                guard let group = item as? [String: Any],
                      let hookItems = group["hooks"] as? [Any] else { return false }
                return hookItems.contains { hook in
                    guard let hook = hook as? [String: Any] else { return false }
                    return isManagedHook(hook, managedCommand: managedCommand)
                }
            }
        }
    }

    private func sanitize(groups: [Any], managedCommand: String?) -> [[String: Any]] {
        groups.compactMap { item in
            guard var group = item as? [String: Any] else { return nil }
            let hooks = group["hooks"] as? [Any] ?? []
            let filtered = hooks.compactMap { hook -> [String: Any]? in
                guard let hook = hook as? [String: Any] else { return nil }
                return isManagedHook(hook, managedCommand: managedCommand) ? nil : hook
            }
            guard !filtered.isEmpty else { return nil }
            group["hooks"] = filtered
            return group
        }
    }

    private func managedGroup(spec: HookSpec, command: String) -> [String: Any] {
        var hook: [String: Any] = ["type": "command", "command": command]
        if let timeout = spec.timeout {
            hook["timeout"] = timeout
        }
        var group: [String: Any] = ["hooks": [hook]]
        if let matcher = spec.matcher {
            group["matcher"] = matcher
        }
        return group
    }

    private func isManagedHook(_ hook: [String: Any], managedCommand: String?) -> Bool {
        guard let command = hook["command"] as? String else { return false }
        if let managedCommand, command == managedCommand { return true }
        let normalized = command.lowercased()
        return normalized.contains("boringnotchagenthooks")
            || normalized.contains("openislandhooks")
            || normalized.contains("vibeislandhooks")
    }

    private func enableCodexFeature(_ contents: String) -> String {
        var lines = contents.components(separatedBy: "\n")
        if let features = sectionRange(named: "features", lines: lines) {
            if let index = lineIndex(ofKey: "hooks", in: features, lines: lines) {
                lines[index] = "hooks = true"
                return lines.joined(separator: "\n")
            }
            if let legacy = lineIndex(ofKey: "codex_hooks", in: features, lines: lines) {
                lines[legacy] = "hooks = true"
                return lines.joined(separator: "\n")
            }
            lines.insert("hooks = true", at: features.upperBound)
            return lines.joined(separator: "\n")
        }
        if !lines.isEmpty, lines.last?.isEmpty == false {
            lines.append("")
        }
        lines.append("[features]")
        lines.append("hooks = true")
        return lines.joined(separator: "\n")
    }

    private func isCodexFeatureEnabled(_ contents: String) -> Bool {
        let lines = contents.components(separatedBy: "\n")
        guard let features = sectionRange(named: "features", lines: lines) else { return false }
        return ["hooks", "codex_hooks"].contains { key in
            guard let index = lineIndex(ofKey: key, in: features, lines: lines),
                  let value = lines[index].split(separator: "=", maxSplits: 1).last else { return false }
            return value.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("true")
        }
    }

    private func sectionRange(named section: String, lines: [String]) -> Range<Int>? {
        guard let header = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[\(section)]" }) else { return nil }
        let end = lines[(header + 1)...].firstIndex { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
        } ?? lines.count
        return header..<end
    }

    private func lineIndex(ofKey key: String, in range: Range<Int>, lines: [String]) -> Int? {
        for index in (range.lowerBound + 1)..<range.upperBound {
            let uncommented = lines[index].split(separator: "#", maxSplits: 1).first.map(String.init) ?? lines[index]
            let parts = uncommented.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if parts.first == key {
                return index
            }
        }
        return nil
    }

    private func backupIfNeeded(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try fileManager.copyItem(at: url, to: url.appendingPathExtension("backup.\(timestamp)"))
    }

    private func saveManifest(_ manifest: AgentHookManifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: url, options: .atomic)
    }

    private func loadManifest(_ url: URL) -> AgentHookManifest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AgentHookManifest.self, from: data)
    }

    private func codexDirectory(configRootPath: String) -> URL {
        configuredURL(configRootPath, fallback: ".codex")
    }

    private func claudeSettingsURL(configRootPath: String) -> URL {
        let configured = configRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configured.isEmpty else {
            return home(".claude/settings.json")
        }
        let url = expandedURL(configured)
        if ["json", "jsonc"].contains(url.pathExtension.lowercased()) {
            return url
        }
        return url.appendingPathComponent("settings.json")
    }

    private func configuredURL(_ path: String, fallback: String) -> URL {
        let configured = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return configured.isEmpty ? home(fallback) : expandedURL(configured)
    }

    private func expandedURL(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        return home(expanded)
    }

    private func home(_ path: String) -> URL {
        let homePath = NSHomeDirectoryForUser(NSUserName()) ?? fileManager.homeDirectoryForCurrentUser.path
        return URL(fileURLWithPath: homePath).appendingPathComponent(path)
    }

    private func missingParts(_ checks: [(String, Bool)]) -> String {
        let missing = checks.compactMap { name, isPresent in isPresent ? nil : name }
        return missing.isEmpty ? "unknown drift" : missing.joined(separator: ", ")
    }

    private func stripJSONComments(_ input: String) -> String {
        var output = ""
        var index = input.startIndex
        var isInString = false
        var isEscaped = false

        while index < input.endIndex {
            let character = input[index]

            if isInString {
                output.append(character)
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInString = false
                }
                index = input.index(after: index)
                continue
            }

            if character == "\"" {
                isInString = true
                output.append(character)
                index = input.index(after: index)
                continue
            }

            if character == "/" {
                let nextIndex = input.index(after: index)
                if nextIndex < input.endIndex {
                    let next = input[nextIndex]
                    if next == "/" {
                        index = input.index(after: nextIndex)
                        while index < input.endIndex, input[index] != "\n" {
                            index = input.index(after: index)
                        }
                        continue
                    }
                    if next == "*" {
                        index = input.index(after: nextIndex)
                        while index < input.endIndex {
                            let current = input[index]
                            let afterCurrent = input.index(after: index)
                            if current == "*", afterCurrent < input.endIndex, input[afterCurrent] == "/" {
                                index = input.index(after: afterCurrent)
                                break
                            }
                            index = afterCurrent
                        }
                        continue
                    }
                }
            }

            output.append(character)
            index = input.index(after: index)
        }

        return output
    }

    private func shellQuote(_ string: String) -> String {
        guard !string.isEmpty else { return "''" }
        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func normalizedTool(_ tool: String) -> String {
        let normalized = tool.lowercased().replacingOccurrences(of: "-", with: "")
        return normalized == "claude" || normalized == "claudecode" ? "claude" : normalized
    }
}

private struct HookSpec {
    var name: String
    var matcher: String?
    var timeout: Int?
}

private struct AgentHookManifest: Codable {
    var hookCommand: String
    var hookBinaryPath: String
    var installedAt = Date()
}
