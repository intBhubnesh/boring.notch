//
//  AgentHookInstallationManager.swift
//  boringNotch
//
//  Agent hook installation adapted from Octane0411/open-vibe-island (GPL v3).
//

import Foundation

enum AgentHookInstallState: String, Codable, Sendable, Hashable {
    case notInstalled
    case installed
    case needsAttention
}

struct AgentHookStatus: Codable, Sendable, Hashable {
    var state: AgentHookInstallState
    var detail: String
    var configPath: String
    var hookBinaryPath: String?
}

@MainActor
final class AgentHookInstallationManager: ObservableObject {
    static let shared = AgentHookInstallationManager()

    @Published private(set) var codexStatus = AgentHookStatus(
        state: .notInstalled,
        detail: "Not checked",
        configPath: "~/.codex"
    )
    @Published private(set) var claudeStatus = AgentHookStatus(
        state: .notInstalled,
        detail: "Not checked",
        configPath: "~/.claude"
    )
    @Published private(set) var isWorking = false
    @Published var lastError: String?

    private var activeOperationID: UUID?

    private init() {}

    func refresh() {
        Task { @MainActor in
            do {
                try await refreshStatuses()
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func install(_ tool: AgentTool) {
        run {
            switch tool {
            case .codex:
                self.codexStatus = try await XPCHelperClient.shared.installAgentHooks(for: "codex")
            case .claudeCode:
                self.claudeStatus = try await XPCHelperClient.shared.installAgentHooks(for: "claude")
            case .cursor, .gemini, .openCode, .kimi, .other:
                throw AgentHookInstallerError.unsupportedTool
            }
        }
    }

    func uninstall(_ tool: AgentTool) {
        run {
            switch tool {
            case .codex:
                self.codexStatus = try await XPCHelperClient.shared.uninstallAgentHooks(for: "codex")
            case .claudeCode:
                self.claudeStatus = try await XPCHelperClient.shared.uninstallAgentHooks(for: "claude")
            case .cursor, .gemini, .openCode, .kimi, .other:
                throw AgentHookInstallerError.unsupportedTool
            }
        }
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        let operationID = UUID()
        activeOperationID = operationID
        isWorking = true
        lastError = nil

        let operationTask = Task { @MainActor in
            do {
                try await operation()
                guard activeOperationID == operationID else { return }
                lastError = nil
            } catch {
                guard activeOperationID == operationID else { return }
                lastError = error.localizedDescription
            }
            guard activeOperationID == operationID else { return }
            activeOperationID = nil
            isWorking = false
        }

        Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(12))
            } catch {
                return
            }
            guard activeOperationID == operationID, isWorking else { return }
            operationTask.cancel()
            XPCHelperClient.shared.resetConnection()
            activeOperationID = nil
            lastError = AgentHookInstallerError.operationTimedOut.localizedDescription
            isWorking = false
        }
    }

    private func refreshStatuses() async throws {
        async let codex = XPCHelperClient.shared.agentHookStatus(for: "codex")
        async let claude = XPCHelperClient.shared.agentHookStatus(for: "claude")
        codexStatus = try await codex
        claudeStatus = try await claude
    }
}

extension AgentHookStatus {
    init?(xpcDictionary: [String: Any]) {
        guard let stateValue = xpcDictionary["state"] as? String,
              let state = AgentHookInstallState(rawValue: stateValue),
              let detail = xpcDictionary["detail"] as? String,
              let configPath = xpcDictionary["configPath"] as? String else {
            return nil
        }
        self.init(
            state: state,
            detail: detail,
            configPath: configPath,
            hookBinaryPath: xpcDictionary["hookBinaryPath"] as? String
        )
    }
}

enum AgentHookInstallerError: Error, LocalizedError {
    case hookSourceMissing
    case hookCompileFailed(String)
    case invalidJSON(URL)
    case unsupportedTool
    case operationTimedOut

    var errorDescription: String? {
        switch self {
        case .hookSourceMissing:
            "Could not find or build the Boring Notch agent hook helper."
        case let .hookCompileFailed(output):
            "Failed to build the hook helper. \(output)"
        case let .invalidJSON(url):
            "Could not read existing JSON config at \(url.path)."
        case .unsupportedTool:
            "Hook installation is only implemented for Codex and Claude Code."
        case .operationTimedOut:
            "The hook installer did not respond. Restart Boring Notch and try again."
        }
    }
}

struct AgentHookInstaller {
    private let fileManager = FileManager.default

    func codexStatus() throws -> AgentHookStatus {
        let directory = home(".codex")
        let configURL = directory.appendingPathComponent("config.toml")
        let hooksURL = directory.appendingPathComponent("hooks.json")
        let manifest = loadManifest(directory.appendingPathComponent("boring-notch-hooks-install.json"))
        let command = manifest?.hookCommand
        let hooksData = try? Data(contentsOf: hooksURL)
        let installed = containsManagedHook(in: hooksData, managedCommand: command)
        let featureEnabled = isCodexFeatureEnabled((try? String(contentsOf: configURL, encoding: .utf8)) ?? "")
        let binaryURL = manifest.map { URL(fileURLWithPath: $0.hookBinaryPath) }
        let binaryOK = binaryURL.map { fileManager.isExecutableFile(atPath: $0.path) } ?? false

        if installed && featureEnabled && binaryOK {
            return AgentHookStatus(state: .installed, detail: "Installed. Run /hooks in Codex if it asks for trust review.", configPath: directory.path, hookBinaryPath: binaryURL?.path)
        }
        if installed || featureEnabled || manifest != nil {
            return AgentHookStatus(state: .needsAttention, detail: "Partial install. Reinstall hooks to repair the binary/config.", configPath: directory.path, hookBinaryPath: binaryURL?.path)
        }
        return AgentHookStatus(state: .notInstalled, detail: "Not installed", configPath: directory.path, hookBinaryPath: nil)
    }

    func claudeStatus() throws -> AgentHookStatus {
        let directory = home(".claude")
        let settingsURL = directory.appendingPathComponent("settings.json")
        let manifest = loadManifest(directory.appendingPathComponent("boring-notch-claude-hooks-install.json"))
        let command = manifest?.hookCommand
        let settingsData = try? Data(contentsOf: settingsURL)
        let installed = containsManagedHook(in: settingsData, managedCommand: command)
        let binaryURL = manifest.map { URL(fileURLWithPath: $0.hookBinaryPath) }
        let binaryOK = binaryURL.map { fileManager.isExecutableFile(atPath: $0.path) } ?? false

        if installed && binaryOK {
            return AgentHookStatus(state: .installed, detail: "Installed", configPath: settingsURL.path, hookBinaryPath: binaryURL?.path)
        }
        if installed || manifest != nil {
            return AgentHookStatus(state: .needsAttention, detail: "Partial install. Reinstall hooks to repair the binary/config.", configPath: settingsURL.path, hookBinaryPath: binaryURL?.path)
        }
        return AgentHookStatus(state: .notInstalled, detail: "Not installed", configPath: settingsURL.path, hookBinaryPath: nil)
    }

    @discardableResult
    func installCodex() throws -> AgentHookStatus {
        let binaryURL = try installHookBinary()
        let directory = home(".codex")
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
        return try codexStatus()
    }

    @discardableResult
    func uninstallCodex() throws -> AgentHookStatus {
        let directory = home(".codex")
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
        return try codexStatus()
    }

    @discardableResult
    func installClaude() throws -> AgentHookStatus {
        let binaryURL = try installHookBinary()
        let directory = home(".claude")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let settingsURL = directory.appendingPathComponent("settings.json")
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
            HookSpec(name: "PreToolUse", matcher: "*", timeout: nil),
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
        return try claudeStatus()
    }

    @discardableResult
    func uninstallClaude() throws -> AgentHookStatus {
        let directory = home(".claude")
        let settingsURL = directory.appendingPathComponent("settings.json")
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
        return try claudeStatus()
    }

    private func installHookBinary() throws -> URL {
        let destination = home("Library/Application Support/boringNotch/AgentHooks/BoringNotchAgentHooks")
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        if let explicit = ProcessInfo.processInfo.environment["BORING_NOTCH_HOOKS_BINARY"],
           fileManager.isExecutableFile(atPath: explicit) {
            try copyExecutable(from: URL(fileURLWithPath: explicit), to: destination)
            return destination
        }

        let bundleCandidate = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/BoringNotchAgentHooks")
        if fileManager.isExecutableFile(atPath: bundleCandidate.path) {
            try copyExecutable(from: bundleCandidate, to: destination)
            return destination
        }

        if fileManager.isExecutableFile(atPath: "/tmp/BoringNotchAgentHooks-test") {
            try copyExecutable(from: URL(fileURLWithPath: "/tmp/BoringNotchAgentHooks-test"), to: destination)
            return destination
        }

        let sourceCandidates = [
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("BoringNotchAgentHooks/main.swift"),
            home("Code/boring.notch/BoringNotchAgentHooks/main.swift"),
        ]
        guard let source = sourceCandidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            throw AgentHookInstallerError.hookSourceMissing
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
        process.arguments = [source.path, "-o", destination.path]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw AgentHookInstallerError.hookCompileFailed(output)
        }
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        return destination
    }

    private func copyExecutable(from source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
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
        let object = try JSONSerialization.jsonObject(with: data)
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
        var hook: [String: Any] = [
            "type": "command",
            "command": command,
        ]
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

    private func home(_ path: String) -> URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(path)
    }

    private func shellQuote(_ string: String) -> String {
        guard !string.isEmpty else { return "''" }
        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
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
