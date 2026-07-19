//
//  AgentActivityManager.swift
//  boringNotch
//
//  Agent Activity Integration — manager design adapted from
//  Octane0411/open-vibe-island (GPL v3).
//
//  AgentActivityManager is the single app-facing owner of agent session
//  state. Demo events and real local bridge events both flow through the same
//  reducer, and user actions are routed back to pending hook clients when
//  applicable.

import Combine
import Foundation

@MainActor
final class AgentActivityManager: ObservableObject {
    static let shared = AgentActivityManager()

    @Published private(set) var state: SessionState {
        didSet {
            BoringViewCoordinator.shared.agentAttentionSessionID = state.activeActionableSession?.id
            savePersistedState()
        }
    }

    private static let persistenceKey = "agentActivityPersistedSessions"

    private var demoSessionID: String?
    private var bridgeServer: BridgeServer?
    private var processScannerTask: Task<Void, Never>?

    private init() {
        var restoredState = Self.loadPersistedState()
        restoredState.pruneStaleHookSessions()
        state = restoredState
    }

    var sessions: [AgentSession] { state.sortedSessions }
    var runningCount: Int { state.runningCount }
    var activeActionableSession: AgentSession? { state.activeActionableSession }

    func apply(_ event: AgentEvent) {
        state.apply(event)
    }

    func setBridgeEnabled(_ isEnabled: Bool) {
        if isEnabled {
            startBridge()
        } else {
            stopBridge()
        }
    }

    func startBridge() {
        startProcessScanner()
        guard bridgeServer == nil else { return }

        let server = BridgeServer { event in
            DispatchQueue.main.async {
                AgentActivityManager.shared.apply(event)
            }
        }

        do {
            try server.start()
            bridgeServer = server
            NSLog("Boring Notch agent bridge started at \(AgentBridgeTransport.socketPath)")
        } catch {
            bridgeServer = nil
            NSLog("Boring Notch agent bridge failed to start: \(error.localizedDescription)")
        }
    }

    func stopBridge() {
        bridgeServer?.stop()
        bridgeServer = nil
        stopProcessScanner()
    }

    func resolvePermission(sessionID: String, resolution: PermissionResolution) {
        guard let requestID = state.sessions[sessionID]?.pendingPermission?.id else { return }
        apply(.permissionResolved(sessionID: sessionID, requestID: requestID, resolution: resolution, at: Date()))
        bridgeServer?.resolvePermission(sessionID: sessionID, requestID: requestID, resolution: resolution)
    }

    func answerQuestion(sessionID: String, response: QuestionPromptResponse) {
        guard let questionID = state.sessions[sessionID]?.pendingQuestion?.id else { return }
        apply(.questionAnswered(sessionID: sessionID, questionID: questionID, response: response, at: Date()))
        bridgeServer?.answerQuestion(sessionID: sessionID, questionID: questionID, response: response)
    }

    func refreshRunningProcesses() async {
        do {
            let snapshots = try await XPCHelperClient.shared.runningAgentProcesses()
            NSLog("Boring Notch agent process scan found \(snapshots.count) process(es)")
            state.reconcileProcessSnapshots(snapshots)
        } catch {
            NSLog("Boring Notch agent process scan failed: \(error.localizedDescription)")
            // Process discovery is best-effort; hook events remain the source of truth
            // for questions and approvals.
        }
    }

    private func startProcessScanner() {
        guard processScannerTask == nil else { return }
        processScannerTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshRunningProcesses()
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    break
                }
            }
        }
    }

    private func stopProcessScanner() {
        processScannerTask?.cancel()
        processScannerTask = nil
        state.reconcileProcessSnapshots([])
    }

    private func savePersistedState() {
        let snapshot = state.persistenceSnapshot()
        if snapshot.sessions.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.persistenceKey)
            return
        }
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.persistenceKey)
        }
    }

    private static func loadPersistedState() -> SessionState {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let state = try? JSONDecoder().decode(SessionState.self, from: data) else {
            return SessionState()
        }
        return state
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
