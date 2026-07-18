//
//  AgentPermissionCard.swift
//  boringNotch
//

import SwiftUI

struct AgentPermissionCard: View {
    let sessionID: String
    let request: PermissionRequest

    @ObservedObject private var manager = AgentActivityManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(request.toolName, systemImage: "exclamationmark.shield.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)

            if let command = request.commandSummary {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.gray)
                    .lineLimit(2)
            }

            if let path = request.pathSummary {
                Text(path)
                    .font(.caption2)
                    .foregroundStyle(.gray.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack {
                Button("Deny", role: .destructive) {
                    manager.resolvePermission(sessionID: sessionID, resolution: .deny)
                }
                .buttonStyle(.bordered)

                Button("Allow") {
                    manager.resolvePermission(sessionID: sessionID, resolution: .allow)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange.opacity(0.1)))
    }
}
