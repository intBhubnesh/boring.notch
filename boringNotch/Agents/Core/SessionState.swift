//
//  SessionState.swift
//  boringNotch
//
//  Agent Activity Integration — model design adapted from
//  Octane0411/open-vibe-island (GPL v3).
//
//  SessionState.apply(_:) is the single reducer for all agent session
//  mutations. Every session-affecting event, whether synthetic (this phase)
//  or bridge-delivered (a later phase), must go through it.

import Foundation

struct SessionState: Sendable {
    private(set) var sessions: [String: AgentSession] = [:]

    var sortedSessions: [AgentSession] {
        sessions.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    var runningCount: Int {
        sessions.values.filter(\.phase.isRunning).count
    }

    var activeActionableSession: AgentSession? {
        sortedSessions.first { $0.phase.isActionable }
    }

    mutating func apply(_ event: AgentEvent) {
        switch event {
        case let .sessionStarted(sessionID, tool, title, cwd, at):
            sessions[sessionID] = AgentSession(
                id: sessionID,
                tool: tool,
                title: title,
                cwd: cwd,
                phase: .starting,
                summary: "Starting…",
                pendingPermission: nil,
                pendingQuestion: nil,
                createdAt: at,
                updatedAt: at
            )

        case let .promptSubmitted(sessionID, summary, at):
            update(sessionID, at: at) { session in
                session.phase = .running
                session.summary = summary
            }

        case let .statusUpdated(sessionID, summary, at):
            update(sessionID, at: at) { session in
                if session.phase == .starting { session.phase = .running }
                session.summary = summary
            }

        case let .permissionRequested(sessionID, request):
            update(sessionID, at: request.requestedAt) { session in
                session.phase = .waitingForApproval
                session.pendingPermission = request
            }

        case let .permissionResolved(sessionID, requestID, _, at):
            update(sessionID, at: at) { session in
                guard session.pendingPermission?.id == requestID else { return }
                session.pendingPermission = nil
                session.phase = session.pendingQuestion != nil ? .waitingForAnswer : .running
            }

        case let .questionAsked(sessionID, prompt):
            update(sessionID, at: prompt.askedAt) { session in
                session.phase = .waitingForAnswer
                session.pendingQuestion = prompt
            }

        case let .questionAnswered(sessionID, questionID, _, at):
            update(sessionID, at: at) { session in
                guard session.pendingQuestion?.id == questionID else { return }
                session.pendingQuestion = nil
                session.phase = session.pendingPermission != nil ? .waitingForApproval : .running
            }

        case let .sessionStopped(sessionID, at):
            update(sessionID, at: at) { session in
                session.phase = .completed
                session.pendingPermission = nil
                session.pendingQuestion = nil
            }

        case let .sessionFailed(sessionID, reason, at):
            update(sessionID, at: at) { session in
                session.phase = .failed
                session.pendingPermission = nil
                session.pendingQuestion = nil
                if let reason { session.summary = reason }
            }
        }
    }

    mutating func reconcileProcessSnapshots(_ snapshots: [AgentProcessSnapshot], at: Date = Date()) {
        let snapshotIDs = Set(snapshots.map(\.sessionID))

        for snapshot in snapshots {
            if var session = sessions[snapshot.sessionID] {
                session.tool = snapshot.tool
                session.title = snapshot.title
                session.cwd = snapshot.cwd
                session.summary = snapshot.summary
                if !session.phase.isActionable {
                    session.phase = .running
                }
                session.updatedAt = at
                sessions[snapshot.sessionID] = session
            } else {
                sessions[snapshot.sessionID] = AgentSession(
                    id: snapshot.sessionID,
                    tool: snapshot.tool,
                    title: snapshot.title,
                    cwd: snapshot.cwd,
                    phase: .running,
                    summary: snapshot.summary,
                    pendingPermission: nil,
                    pendingQuestion: nil,
                    createdAt: snapshot.observedAt,
                    updatedAt: at
                )
            }
        }

        for sessionID in sessions.keys where sessionID.hasPrefix("process:") && !snapshotIDs.contains(sessionID) {
            sessions.removeValue(forKey: sessionID)
        }
    }

    private mutating func update(_ sessionID: String, at: Date, _ mutate: (inout AgentSession) -> Void) {
        guard var session = sessions[sessionID] else { return }
        mutate(&session)
        session.updatedAt = at
        sessions[sessionID] = session
    }
}
