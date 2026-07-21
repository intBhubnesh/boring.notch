//
//  AgentJumpService.swift
//  boringNotch
//
//  Click-to-jump: activates the host application for a clicked agent
//  session and, where available, routes to the closest useful workspace/
//  terminal context.
//

import AppKit
import ApplicationServices
import Foundation

enum AgentJumpService {
    static func jump(to session: AgentSession) {
        Task.detached(priority: .userInitiated) {
            _ = await jumpAndReport(to: session)
        }
    }

    @discardableResult
    static func jumpAndReport(to session: AgentSession) async -> Bool {
        guard let hostApplication = session.hostApplication, !hostApplication.isEmpty else { return false }
        let tty = session.tty

        do {
            switch hostApplication {
            case "VS Code":
                await openWorkspace(cwd: session.cwd, appName: "Visual Studio Code", bundleIdentifiers: ["com.microsoft.VSCode"])
                try await AppleScriptHelper.executeVoid(editorTerminalFocusScript(appName: "Visual Studio Code", processName: "Code"))
            case "Cursor":
                await openWorkspace(cwd: session.cwd, appName: "Cursor", bundleIdentifiers: ["com.todesktop.230313mzl4w4u92"])
                try await AppleScriptHelper.executeVoid(editorTerminalFocusScript(appName: "Cursor", processName: "Cursor"))
            case "Terminal":
                try await AppleScriptHelper.executeVoid(terminalScript(tty: tty))
            case "iTerm":
                try await AppleScriptHelper.executeVoid(iTermScript(tty: tty))
            default:
                try await AppleScriptHelper.executeVoid(activateScript(appName: appleScriptName(for: hostApplication)))
            }
            return true
        } catch {
            NSLog("Boring Notch agent jump failed for \(hostApplication): \(error.localizedDescription)")
            postPermissionRequiredIfNeeded(session: session, error: error)
            return false
        }
    }

    static func requiresJumpPermission(for session: AgentSession) -> Bool {
        switch session.hostApplication {
        case "VS Code", "Cursor":
            true
        default:
            false
        }
    }

    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccessibilityPermission(promptIfNeeded: Bool = true) -> Bool {
        if AXIsProcessTrusted() { return true }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptIfNeeded] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            openAccessibilitySettings()
        }
        return trusted
    }

    static func openAccessibilitySettings() {
        openPrivacySettings("Privacy_Accessibility")
    }

    static func openAutomationSettings() {
        openPrivacySettings("Privacy_Automation")
    }

    private static func appleScriptName(for hostApplication: String) -> String {
        switch hostApplication {
        case "VS Code": "Visual Studio Code"
        default: hostApplication
        }
    }

    private static func activateScript(appName: String) -> String {
        "tell application \(quoted(appName)) to activate"
    }

    private static func openWorkspace(cwd: String?, appName: String, bundleIdentifiers: [String]) async {
        await MainActor.run {
            let workspace = NSWorkspace.shared
            let applicationURL = applicationURL(appName: appName, bundleIdentifiers: bundleIdentifiers)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.createsNewApplicationInstance = false

            if let cwd, let folderURL = folderURL(from: cwd), let applicationURL {
                workspace.open([folderURL], withApplicationAt: applicationURL, configuration: configuration)
                return
            }

            if let applicationURL {
                workspace.openApplication(at: applicationURL, configuration: configuration, completionHandler: nil)
            }
        }
    }

    private static func postPermissionRequiredIfNeeded(session: AgentSession, error: Error) {
        let message = error.localizedDescription
        let normalized = message.lowercased()
        let looksLikePermissionFailure = [
            "not authorized",
            "not permitted",
            "not allowed",
            "permission",
            "privacy",
            "accessibility",
            "automation",
            "system events",
        ].contains { normalized.contains($0) }

        guard looksLikePermissionFailure else { return }

        NotificationCenter.default.post(
            name: .agentJumpPermissionRequired,
            object: nil,
            userInfo: [
                "sessionID": session.id,
                "message": message,
            ]
        )
    }

    private static func openPrivacySettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static func applicationURL(appName: String, bundleIdentifiers: [String]) -> URL? {
        for bundleIdentifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return url
            }
        }

        let candidates = [
            "/Applications/\(appName).app",
            "\(NSHomeDirectory())/Applications/\(appName).app",
        ]
        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func folderURL(from cwd: String) -> URL? {
        let expandedPath = (cwd as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: expandedPath).standardizedFileURL
    }

    private static func editorTerminalFocusScript(appName: String, processName: String) -> String {
        """
        tell application \(quoted(appName)) to activate
        delay 0.25
        tell application "System Events"
            if exists process \(quoted(processName)) then
                tell process \(quoted(processName))
                    set frontmost to true
                    keystroke "p" using {command down, shift down}
                    delay 0.15
                    keystroke ">Terminal: Focus Terminal"
                    delay 0.05
                    key code 36
                end tell
            end if
        end tell
        """
    }

    private static func terminalScript(tty: String?) -> String {
        guard let tty = safeTTY(tty) else { return activateScript(appName: "Terminal") }
        return """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if (tty of t) is \(quoted(tty)) then
                            set selected tab of w to t
                            set index of w to 1
                            activate
                            return
                        end if
                    end try
                end repeat
            end repeat
            activate
        end tell
        """
    }

    private static func iTermScript(tty: String?) -> String {
        guard let tty = safeTTY(tty) else { return activateScript(appName: "iTerm2") }
        return """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        try
                            if (tty of s) is \(quoted(tty)) then
                                tell w to select
                                tell t to select
                                tell s to select
                                activate
                                return
                            end if
                        end try
                    end repeat
                end repeat
            end repeat
            activate
        end tell
        """
    }

    /// Only ever built from `ps -o tty=` output normalized in the XPC helper, but this is
    /// interpolated into an AppleScript source string, so validate defensively rather than
    /// trust the pipeline.
    private static func safeTTY(_ tty: String?) -> String? {
        guard let tty, tty.hasPrefix("/dev/tty") else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/_-")
        guard tty.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return tty
    }

    private static func quoted(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}

extension Notification.Name {
    static let agentJumpPermissionRequired = Notification.Name("agentJumpPermissionRequired")
}
