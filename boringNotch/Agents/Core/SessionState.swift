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

struct SessionState: Codable, Sendable {
    private(set) var sessions: [String: AgentSession] = [:]

    init(sessions: [String: AgentSession] = [:]) {
        self.sessions = sessions
    }

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
                hostApplication: nil,
                activeFilePath: nil,
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
                session.activeFilePath = Self.activeFilePath(from: summary) ?? session.activeFilePath
            }

        case let .statusUpdated(sessionID, summary, at):
            update(sessionID, at: at) { session in
                if session.phase == .starting { session.phase = .running }
                session.summary = summary
                session.activeFilePath = Self.activeFilePath(from: summary) ?? session.activeFilePath
            }

        case let .permissionRequested(sessionID, request):
            update(sessionID, at: request.requestedAt) { session in
                session.phase = .waitingForApproval
                session.pendingPermission = request
                session.activeFilePath = request.pathSummary ?? session.activeFilePath
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
                session.hostApplication = snapshot.hostApplication
                session.summary = snapshot.summary
                session.activeFilePath = nil
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
                    hostApplication: snapshot.hostApplication,
                    activeFilePath: nil,
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

    func persistenceSnapshot(now: Date = Date()) -> SessionState {
        SessionState(sessions: sessions.filter { sessionID, session in
            guard !sessionID.hasPrefix("process:") else { return false }
            return !session.isExpiredForPersistence(now: now)
        })
    }

    mutating func pruneStaleHookSessions(now: Date = Date()) {
        sessions = sessions.filter { sessionID, session in
            guard !sessionID.hasPrefix("process:") else { return true }
            return !session.isExpiredForPersistence(now: now)
        }
    }

    private mutating func update(_ sessionID: String, at: Date, _ mutate: (inout AgentSession) -> Void) {
        guard var session = sessions[sessionID] else { return }
        mutate(&session)
        session.updatedAt = at
        sessions[sessionID] = session
    }

    private static func activeFilePath(from summary: String) -> String? {
        let prefixes = ["Writing ", "Write(", "Edit(", "Read(", "Open("]
        for prefix in prefixes {
            guard let range = summary.range(of: prefix, options: [.caseInsensitive]) else { continue }
            let suffix = summary[range.upperBound...]
            let endCharacters = CharacterSet(charactersIn: ") ,:")
            let rawCandidate = suffix
                .prefix { character in
                    String(character).rangeOfCharacter(from: endCharacters) == nil
                }
            let candidate = String(rawCandidate).trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty, candidate.contains(".") || candidate.contains("/") {
                return candidate
            }
        }
        return nil
    }
}

private extension AgentSession {
    func isExpiredForPersistence(now: Date) -> Bool {
        let age = now.timeIntervalSince(updatedAt)
        switch phase {
        case .completed, .failed:
            return age > 60 * 60
        case .starting, .running:
            return age > 12 * 60 * 60
        case .waitingForApproval, .waitingForAnswer:
            return age > 24 * 60 * 60
        }
    }
}
