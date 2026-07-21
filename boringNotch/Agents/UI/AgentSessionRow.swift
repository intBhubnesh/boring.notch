//
//  AgentSessionRow.swift
//  boringNotch
//

import SwiftUI

struct AgentSessionRow: View {
    let session: AgentSession

    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var manager = AgentActivityManager.shared
    @State private var isHoveringJumpTarget = false
    @State private var jumpPermissionRequired = false
    @State private var jumpPermissionMessage: String?

    private var canJump: Bool {
        session.hostApplication?.isEmpty == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            jumpTarget

            if jumpPermissionRequired {
                jumpPermissionButton
            }

            if let permission = session.pendingPermission {
                AgentPermissionCard(sessionID: session.id, request: permission)
            }

            if let question = session.pendingQuestion {
                AgentQuestionCard(sessionID: session.id, prompt: question)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackground)
        )
        .task(id: session.hostApplication) {
            refreshJumpPermissionState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentJumpPermissionRequired)) { notification in
            guard notification.userInfo?["sessionID"] as? String == session.id else { return }
            jumpPermissionMessage = notification.userInfo?["message"] as? String
            jumpPermissionRequired = true
        }
    }

    @ViewBuilder
    private var jumpTarget: some View {
        let info = HStack(alignment: .top, spacing: 10) {
            agentIcon

            VStack(alignment: .leading, spacing: 4) {
                header
                contentLine
                contextLine
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        HStack(alignment: .top, spacing: 6) {
            if canJump {
                info
                    .onHover { isHoveringJumpTarget = $0 }
                    .onTapGesture {
                        jumpToSession()
                    }
            } else {
                info
            }

            if canJump {
                iconButton("arrow.up.right", help: "Jump to agent") {
                    jumpToSession()
                }
            }

            iconButton("xmark.circle.fill", help: closeHelpText, role: .destructive) {
                manager.closeSession(sessionID: session.id)
            }
        }
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHoveringJumpTarget ? Color.white.opacity(0.05) : .clear)
        )
    }

    private func iconButton(
        _ systemName: String,
        help: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(role == .destructive ? .red.opacity(0.8) : .gray.opacity(0.75))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .padding(.top, 1)
    }

    private func jumpToSession() {
        if AgentJumpService.requiresJumpPermission(for: session),
           !AgentJumpService.isAccessibilityTrusted() {
            requestJumpPermission()
            return
        }

        Task {
            let didJump = await AgentJumpService.jumpAndReport(to: session)
            await MainActor.run {
                if didJump {
                    jumpPermissionRequired = false
                    jumpPermissionMessage = nil
                    vm.close()
                } else if AgentJumpService.requiresJumpPermission(for: session) {
                    jumpPermissionRequired = true
                }
            }
        }
    }

    private var jumpPermissionButton: some View {
        HStack(spacing: 8) {
            Button {
                requestJumpPermission()
            } label: {
                Label("Grant Permission", systemImage: "lock.open.fill")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(session.tool.accentColor)
            .help(jumpPermissionHelp)

            if jumpPermissionMessage != nil {
                Button {
                    AgentJumpService.openAutomationSettings()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.gray.opacity(0.8))
                .help("Open Automation settings")
            }
        }
        .padding(.leading, 34)
    }

    private var jumpPermissionHelp: String {
        jumpPermissionMessage == nil
            ? "Grant Accessibility access for editor terminal focus"
            : "Grant Automation access for editor terminal focus"
    }

    private func requestJumpPermission() {
        if !AgentJumpService.isAccessibilityTrusted() {
            let trusted = AgentJumpService.requestAccessibilityPermission(promptIfNeeded: true)
            jumpPermissionRequired = !trusted

            if trusted {
                jumpPermissionMessage = nil
                jumpToSession()
            }
            return
        }

        if jumpPermissionMessage != nil {
            AgentJumpService.openAutomationSettings()
            AgentJumpService.jump(to: session)
            return
        }

        jumpPermissionRequired = false
        jumpToSession()
    }

    private func refreshJumpPermissionState() {
        guard AgentJumpService.requiresJumpPermission(for: session) else {
            jumpPermissionRequired = false
            jumpPermissionMessage = nil
            return
        }

        jumpPermissionRequired = !AgentJumpService.isAccessibilityTrusted()
        if !jumpPermissionRequired {
            jumpPermissionMessage = nil
        }
    }

    private var closeHelpText: String {
        session.pid == nil ? "Dismiss session" : "Stop agent session"
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(session.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            metadataPill(session.tool.displayName)
            metadataPill(session.hostApplication ?? "Other app")
            ageText
        }
    }

    private var agentIcon: some View {
        ZStack {
            Circle()
                .fill(session.tool.accentColor.opacity(0.18))
            Image(systemName: session.tool.sfSymbol)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(session.tool.accentColor)
        }
        .frame(width: 24, height: 24)
    }

    private var contentLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(primaryStatusText)
                .font(.system(size: 12, weight: idle ? .regular : .medium, design: .monospaced))
                .foregroundStyle(idle ? .gray : .white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var contextLine: some View {
        HStack(spacing: 6) {
            Image(systemName: idle ? "moon.zzz.fill" : "doc.text")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(idle ? .gray.opacity(0.85) : session.tool.accentColor)

            Text(secondaryStatusText)
                .font(.caption2)
                .foregroundStyle(.gray.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func metadataPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.gray)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
    }

    private var ageText: some View {
        Text(relativeAge)
            .font(.caption2)
            .foregroundStyle(.gray.opacity(0.7))
            .lineLimit(1)
    }

    private var rowBackground: Color {
        if session.phase.isActionable {
            return session.tool.accentColor.opacity(0.11)
        }
        return Color.white.opacity(0.035)
    }

    private var primaryStatusText: String {
        if let question = session.pendingQuestion {
            return question.question
        }
        if let permission = session.pendingPermission {
            return "Permission request: \(permission.toolName)"
        }
        if idle {
            if let folderName {
                return "\(folderName) in \(session.hostApplication ?? "Other app")"
            }
            return "Idle in \(session.hostApplication ?? "Other app")"
        }
        return session.summary
    }

    private var secondaryStatusText: String {
        if idle {
            return folderName == nil ? "Folder unavailable from process scan" : "Idle"
        }
        if let editingPath {
            return editingPath
        }
        if let cwd = session.cwd {
            return cwd
        }
        return session.phase.displayLabel
    }

    private var editingPath: String? {
        session.pendingPermission?.pathSummary
            ?? session.activeFilePath
            ?? Self.pathCandidate(from: session.summary)
    }

    private var folderName: String? {
        guard let cwd = session.cwd else { return nil }
        let expandedPath = (cwd as NSString).expandingTildeInPath
        let lastComponent = URL(fileURLWithPath: expandedPath).lastPathComponent
        return lastComponent.isEmpty ? cwd : lastComponent
    }

    private var idle: Bool {
        !session.phase.isActionable
            && session.id.hasPrefix("process:")
            && editingPath == nil
            && session.summary.localizedCaseInsensitiveContains("idle")
    }

    private var relativeAge: String {
        let seconds = max(0, Int(Date().timeIntervalSince(session.updatedAt)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }

    private var statusColor: Color {
        switch session.phase {
        case .starting, .running: idle ? .gray : session.tool.accentColor
        case .waitingForApproval, .waitingForAnswer: .orange
        case .completed: .green
        case .failed: .red
        }
    }

    private static func pathCandidate(from summary: String) -> String? {
        let prefixes = ["Writing ", "Write(", "Edit(", "Read(", "Open(", "Edit "]
        for prefix in prefixes {
            guard let range = summary.range(of: prefix, options: [.caseInsensitive]) else { continue }
            let suffix = summary[range.upperBound...]
            let stopCharacters = CharacterSet(charactersIn: ") ,:")
            let rawCandidate = suffix.prefix { character in
                String(character).rangeOfCharacter(from: stopCharacters) == nil
            }
            let candidate = String(rawCandidate).trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty, candidate.contains(".") || candidate.contains("/") {
                return candidate
            }
        }
        return nil
    }
}
