//
//  AgentActivityManager.swift
//  boringNotch
//
//  Agent Activity Integration — manager design adapted from
//  Octane0411/open-vibe-island (GPL v3).
//
//  AgentActivityManager is the single app-facing owner of agent session
//  state. This phase drives it with synthetic ("demo") events only; a later
//  phase will feed it real events from a local IPC bridge without changing
//  this surface — resolvePermission(_:_:) and answerQuestion(_:_:) are
//  already the exact seam that bridge will call into.

import Combine
import Foundation

@MainActor
final class AgentActivityManager: ObservableObject {
    static let shared = AgentActivityManager()

    @Published private(set) var state = SessionState() {
        didSet {
            BoringViewCoordinator.shared.agentAttentionSessionID = state.activeActionableSession?.id
        }
    }

    private var demoSessionID: String?

    private init() {}

    var sessions: [AgentSession] { state.sortedSessions }
    var runningCount: Int { state.runningCount }
    var activeActionableSession: AgentSession? { state.activeActionableSession }

    func apply(_ event: AgentEvent) {
        state.apply(event)
    }

    func resolvePermission(sessionID: String, resolution: PermissionResolution) {
        guard let requestID = state.sessions[sessionID]?.pendingPermission?.id else { return }
        apply(.permissionResolved(sessionID: sessionID, requestID: requestID, resolution: resolution, at: Date()))
    }

    func answerQuestion(sessionID: String, response: QuestionPromptResponse) {
        guard let questionID = state.sessions[sessionID]?.pendingQuestion?.id else { return }
        apply(.questionAnswered(sessionID: sessionID, questionID: questionID, response: response, at: Date()))
    }

    // MARK: - Demo / preview support

    // Stands in for the not-yet-built IPC bridge so the UI can be exercised
    // end to end before real agent hooks exist. Surfaced as buttons under
    // Settings > Agent Activity > Preview.

    func startDemoSession(tool: AgentTool = .codex) {
        let id = UUID().uuidString
        demoSessionID = id
        apply(.sessionStarted(
            sessionID: id, tool: tool, title: "\(tool.displayName) — boring.notch",
            cwd: "~/Code/boring.notch", at: Date()
        ))
        apply(.promptSubmitted(sessionID: id, summary: "Refactoring the notch priority chain…", at: Date()))
    }

    func demoRequestPermission() {
        let id = activeDemoSessionID()
        let request = PermissionRequest(
            id: UUID().uuidString,
            toolName: "shell",
            commandSummary: "rm -rf build/DerivedData",
            pathSummary: "boring.notch/build",
            requestedAt: Date()
        )
        apply(.permissionRequested(sessionID: id, request: request))
    }

    func demoAskQuestion() {
        let id = activeDemoSessionID()
        let prompt = QuestionPrompt(
            id: UUID().uuidString,
            title: "Choose an approach",
            question: "How should the passive agent state rank against music?",
            options: [
                QuestionOption(id: "below-music", label: "Below music"),
                QuestionOption(id: "above-music", label: "Above music"),
            ],
            multiSelect: false,
            allowsFreeform: true,
            askedAt: Date()
        )
        apply(.questionAsked(sessionID: id, prompt: prompt))
    }

    func completeDemoSession() {
        guard let id = demoSessionID else { return }
        apply(.sessionStopped(sessionID: id, at: Date()))
        demoSessionID = nil
    }

    private func activeDemoSessionID() -> String {
        if let id = demoSessionID, state.sessions[id] != nil {
            return id
        }
        let id = UUID().uuidString
        demoSessionID = id
        apply(.sessionStarted(
            sessionID: id, tool: .codex, title: "Codex — boring.notch",
            cwd: "~/Code/boring.notch", at: Date()
        ))
        return id
    }
}
