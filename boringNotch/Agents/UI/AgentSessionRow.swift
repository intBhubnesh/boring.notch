//
//  AgentSessionRow.swift
//  boringNotch
//

import SwiftUI

struct AgentSessionRow: View {
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                agentIcon

                VStack(alignment: .leading, spacing: 4) {
                    header
                    contentLine
                    contextLine
                }
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
