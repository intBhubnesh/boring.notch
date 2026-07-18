//
//  AgentLiveActivityView.swift
//  boringNotch
//
//  Passive closed-notch state shown while an agent session is running and
//  none of it needs the user's attention. Mirrors the layout MusicLiveActivity
//  uses (icon in the left ear, black camera-housing gap, status in the right
//  ear) — see ContentView.MusicLiveActivity().
//

import SwiftUI

struct AgentLiveActivityView: View {
    static let statusWidth: CGFloat = 120

    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var manager = AgentActivityManager.shared

    private var session: AgentSession? {
        manager.sessions.first { $0.phase.isRunning }
    }

    var body: some View {
        HStack {
            Image(systemName: session?.tool.sfSymbol ?? "sparkles")
                .foregroundStyle(.white)
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 12),
                    height: max(0, vm.effectiveClosedNotchHeight - 12)
                )

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - 20)

            HStack {
                if let session {
                    Text(session.summary)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .frame(width: Self.statusWidth, alignment: .leading)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}
