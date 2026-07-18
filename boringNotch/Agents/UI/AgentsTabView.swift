//
//  AgentsTabView.swift
//  boringNotch
//

import SwiftUI

struct AgentsTabView: View {
    @ObservedObject private var manager = AgentActivityManager.shared

    var body: some View {
        Group {
            if manager.sessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(manager.sessions) { session in
                            AgentSessionRow(session: session)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.never)
            }
        }
        .padding(.horizontal, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white, .gray)
                .imageScale(.large)
            Text("No agents running")
                .foregroundStyle(.gray)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
