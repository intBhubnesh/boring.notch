//
//  AgentSessionRow.swift
//  boringNotch
//

import SwiftUI

struct AgentSessionRow: View {
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            Text(session.summary)
                .font(.caption)
                .foregroundStyle(.gray)
                .lineLimit(2)

            if let cwd = session.cwd {
                Text(cwd)
                    .font(.caption2)
                    .foregroundStyle(.gray.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let permission = session.pendingPermission {
                AgentPermissionCard(sessionID: session.id, request: permission)
            }

            if let question = session.pendingQuestion {
                AgentQuestionCard(sessionID: session.id, prompt: question)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: session.tool.sfSymbol)
                .foregroundStyle(.white)
            Text(session.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            phaseBadge
        }
    }

    private var phaseBadge: some View {
        Text(session.phase.displayLabel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(phaseColor.opacity(0.2)))
            .foregroundStyle(phaseColor)
    }

    private var phaseColor: Color {
        switch session.phase {
        case .starting, .running: .blue
        case .waitingForApproval, .waitingForAnswer: .orange
        case .completed: .green
        case .failed: .red
        }
    }
}
