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
            if var session = sessions[sessionID] {
                session.tool = tool
                session.title = title
                session.cwd = cwd ?? session.cwd
                if session.phase == .completed || session.phase == .failed {
                    session.phase = .starting
                    session.summary = "Starting…"
                    session.pendingPermission = nil
                    session.pendingQuestion = nil
                    session.activeFilePath = nil
                }
                session.updatedAt = at
                sessions[sessionID] = session
            } else {
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
            }

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
        var claimedHookSessionIDs: Set<String> = []

        for snapshot in snapshots {
            if var session = sessions[snapshot.sessionID] {
                session.merge(snapshot: snapshot, at: at, preserveActivity: false)
                sessions[snapshot.sessionID] = session
            } else if let hookSessionID = matchingHookSessionID(for: snapshot, excluding: claimedHookSessionIDs),
                      var session = sessions[hookSessionID] {
                session.merge(snapshot: snapshot, at: at, preserveActivity: true)
                sessions[hookSessionID] = session
                sessions.removeValue(forKey: snapshot.sessionID)
                claimedHookSessionIDs.insert(hookSessionID)
            } else {
                sessions[snapshot.sessionID] = AgentSession(
                    id: snapshot.sessionID,
                    tool: snapshot.tool,
                    title: snapshot.title,
                    cwd: snapshot.cwd,
                    hostApplication: snapshot.hostApplication,
                    pid: snapshot.pid,
                    tty: snapshot.tty,
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

    private func matchingHookSessionID(for snapshot: AgentProcessSnapshot, excluding claimed: Set<String>) -> String? {
        let snapshotCWD = snapshot.cwd.flatMap(Self.normalizedPath)
        return sessions.values
            .filter { session in
                guard !session.id.hasPrefix("process:"), session.tool == snapshot.tool else { return false }
                guard !claimed.contains(session.id) else { return false }
                guard let snapshotCWD else { return false }
                return session.cwd.flatMap(Self.normalizedPath) == snapshotCWD
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first?.id
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

    mutating func removeSession(_ sessionID: String) {
        sessions.removeValue(forKey: sessionID)
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

    private static func normalizedPath(_ path: String) -> String? {
        let expandedPath = (path as NSString).expandingTildeInPath
        guard !expandedPath.isEmpty else { return nil }
        return URL(fileURLWithPath: expandedPath).standardizedFileURL.path
    }
}

private extension AgentSession {
    mutating func merge(snapshot: AgentProcessSnapshot, at: Date, preserveActivity: Bool) {
        tool = snapshot.tool
        if !preserveActivity {
            title = snapshot.title
        }
        cwd = preserveActivity ? (cwd ?? snapshot.cwd) : snapshot.cwd
        hostApplication = snapshot.hostApplication
        pid = snapshot.pid
        tty = snapshot.tty
        if !preserveActivity || phase == .starting || summary.localizedCaseInsensitiveContains("idle") {
            summary = snapshot.summary
            activeFilePath = nil
        }
        if !phase.isActionable {
            phase = .running
        }
        updatedAt = at
    }

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
