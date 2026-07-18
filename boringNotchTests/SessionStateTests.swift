//
//  SessionStateTests.swift
//  boringNotchTests
//

import XCTest

final class SessionStateTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func date(_ offset: TimeInterval) -> Date {
        baseDate.addingTimeInterval(offset)
    }

    func testSessionStartCreatesRunningSession() {
        var state = SessionState()
        state.apply(.sessionStarted(sessionID: "a", tool: .codex, title: "Codex", cwd: "/tmp", at: date(0)))

        XCTAssertEqual(state.sessions["a"]?.phase, .starting)
        XCTAssertEqual(state.runningCount, 1)

        state.apply(.promptSubmitted(sessionID: "a", summary: "Doing work", at: date(1)))
        XCTAssertEqual(state.sessions["a"]?.phase, .running)
        XCTAssertEqual(state.sessions["a"]?.summary, "Doing work")
    }

    func testQuestionLifecycleResolvesBackToRunning() {
        var state = SessionState()
        state.apply(.sessionStarted(sessionID: "a", tool: .codex, title: "Codex", cwd: nil, at: date(0)))
        state.apply(.promptSubmitted(sessionID: "a", summary: "Running", at: date(1)))

        let prompt = QuestionPrompt(
            id: "q1", title: "Pick one", question: "A or B?",
            options: [QuestionOption(id: "A", label: "A"), QuestionOption(id: "B", label: "B")],
            multiSelect: false, allowsFreeform: false, askedAt: date(2)
        )
        state.apply(.questionAsked(sessionID: "a", prompt: prompt))

        XCTAssertEqual(state.sessions["a"]?.phase, .waitingForAnswer)
        XCTAssertEqual(state.activeActionableSession?.id, "a")

        state.apply(.questionAnswered(
            sessionID: "a", questionID: "q1",
            response: QuestionPromptResponse(selectedOptionIDs: ["A"], freeformText: nil),
            at: date(3)
        ))

        XCTAssertNil(state.sessions["a"]?.pendingQuestion)
        XCTAssertEqual(state.sessions["a"]?.phase, .running)
        XCTAssertNil(state.activeActionableSession)
    }

    func testPermissionLifecycleResolvesBackToRunning() {
        var state = SessionState()
        state.apply(.sessionStarted(sessionID: "a", tool: .claudeCode, title: "Claude Code", cwd: nil, at: date(0)))
        state.apply(.promptSubmitted(sessionID: "a", summary: "Running", at: date(1)))

        let request = PermissionRequest(
            id: "p1", toolName: "shell", commandSummary: "rm -rf build",
            pathSummary: "/tmp/build", requestedAt: date(2)
        )
        state.apply(.permissionRequested(sessionID: "a", request: request))

        XCTAssertEqual(state.sessions["a"]?.phase, .waitingForApproval)
        XCTAssertEqual(state.activeActionableSession?.id, "a")

        state.apply(.permissionResolved(sessionID: "a", requestID: "p1", resolution: .allow, at: date(3)))

        XCTAssertNil(state.sessions["a"]?.pendingPermission)
        XCTAssertEqual(state.sessions["a"]?.phase, .running)
        XCTAssertNil(state.activeActionableSession)
    }

    func testStaleResolutionIsIgnored() {
        var state = SessionState()
        state.apply(.sessionStarted(sessionID: "a", tool: .codex, title: "Codex", cwd: nil, at: date(0)))
        let request = PermissionRequest(
            id: "p1", toolName: "shell", commandSummary: nil, pathSummary: nil, requestedAt: date(1)
        )
        state.apply(.permissionRequested(sessionID: "a", request: request))

        // A resolution for a request ID that no longer matches the pending one is a no-op.
        state.apply(.permissionResolved(sessionID: "a", requestID: "stale-id", resolution: .deny, at: date(2)))

        XCTAssertEqual(state.sessions["a"]?.phase, .waitingForApproval)
        XCTAssertNotNil(state.sessions["a"]?.pendingPermission)
    }

    func testEventForUnknownSessionIsIgnored() {
        var state = SessionState()
        state.apply(.promptSubmitted(sessionID: "does-not-exist", summary: "Running", at: date(0)))

        XCTAssertTrue(state.sessions.isEmpty)
        XCTAssertEqual(state.runningCount, 0)
    }

    func testStopAndFailTerminatePhaseAndClearPending() {
        var state = SessionState()
        state.apply(.sessionStarted(sessionID: "a", tool: .codex, title: "Codex", cwd: nil, at: date(0)))
        state.apply(.sessionStopped(sessionID: "a", at: date(1)))
        XCTAssertEqual(state.sessions["a"]?.phase, .completed)
        XCTAssertEqual(state.runningCount, 0)

        state.apply(.sessionStarted(sessionID: "b", tool: .codex, title: "Codex", cwd: nil, at: date(0)))
        state.apply(.sessionFailed(sessionID: "b", reason: "crashed", at: date(1)))
        XCTAssertEqual(state.sessions["b"]?.phase, .failed)
        XCTAssertEqual(state.sessions["b"]?.summary, "crashed")
        XCTAssertEqual(state.runningCount, 0)
    }

    func testMultipleConcurrentSessionsSortAndCountIndependently() {
        var state = SessionState()
        state.apply(.sessionStarted(sessionID: "a", tool: .codex, title: "Codex", cwd: nil, at: date(0)))
        state.apply(.sessionStarted(sessionID: "b", tool: .cursor, title: "Cursor", cwd: nil, at: date(1)))
        state.apply(.sessionStarted(sessionID: "c", tool: .gemini, title: "Gemini", cwd: nil, at: date(2)))

        XCTAssertEqual(state.runningCount, 3)
        XCTAssertEqual(state.sortedSessions.map(\.id), ["c", "b", "a"])

        state.apply(.sessionStopped(sessionID: "b", at: date(3)))
        XCTAssertEqual(state.runningCount, 2)

        let request = PermissionRequest(
            id: "p1", toolName: "shell", commandSummary: nil, pathSummary: nil, requestedAt: date(4)
        )
        state.apply(.permissionRequested(sessionID: "a", request: request))
        XCTAssertEqual(state.activeActionableSession?.id, "a")
    }
}
