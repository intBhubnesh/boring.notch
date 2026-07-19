//
//  AgentAttentionView.swift
//  boringNotch
//
//  Highest-priority closed-notch state: an agent is waiting on the user for
//  a question or a permission decision. Same left-ear/right-ear layout as
//  AgentLiveActivityView, styled to stand out from the passive state.
//

import SwiftUI

struct AgentAttentionView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var manager = AgentActivityManager.shared

    private var session: AgentSession? {
        manager.activeActionableSession
    }

    private var statusText: String {
        switch session?.phase {
        case .waitingForApproval: "Needs approval"
        case .waitingForAnswer: "Needs your input"
        default: "Needs your input"
        }
    }

    var body: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(.orange.opacity(0.18))
                Image(systemName: session?.tool.sfSymbol ?? "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(
                width: max(0, vm.effectiveClosedNotchHeight - 12),
                height: max(0, vm.effectiveClosedNotchHeight - 12)
            )

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - 20)

            HStack {
                Text(statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(width: AgentLiveActivityView.statusWidth, alignment: .leading)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}
