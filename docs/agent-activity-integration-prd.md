# PRD: Agent Activity Integration for Boring Notch

## Summary

Integrate the core agent-monitoring functionality from
`Octane0411/open-vibe-island` into Boring Notch so the notch can show active AI
agent work, surface agent questions, and let the user respond without returning
to the terminal.

The integration should reuse Boring Notch's existing notch window, hover/open
behavior, tab model, and settings system. We should port the event, bridge,
session, hook, and response logic from Open Island rather than importing its
separate overlay window implementation.

## Goals

- Show current agent status in the closed notch when an agent is running.
- Show an attention state in the closed notch when an agent asks a question or
  requests approval.
- Add an open-notch Agent tab with active sessions, status, summary, questions,
  and response controls.
- Support two-way responses for agent questions and approvals through local IPC.
- Start with Codex support, then expand to Claude Code, Cursor, Gemini CLI,
  OpenCode, Kimi, and Claude-compatible forks.
- Keep the feature local-first: no cloud service, account, telemetry, or remote
  dependency.
- Preserve existing Boring Notch behavior for music, shelf, calendar, HUD,
  downloads, and battery.

## Non-Goals

- Do not replace Boring Notch's overlay/window system with Open Island's
  `OverlayPanelController`.
- Do not copy Open Island's full visual design. The agent UI should feel native
  to Boring Notch.
- Do not make agent hooks mandatory. Agent integration must be opt-in and
  reversible.
- Do not block agent execution if Boring Notch is not running.
- Do not ship every Open Island feature in the first milestone, especially usage
  dashboards, Watch relay, remote sessions, or all terminal jump-back adapters.

## Source Repo Analysis

Open Island is a Swift 6.2 package with these relevant targets:

- `OpenIslandCore`: reusable models, bridge transport, hook payload parsing,
  session reducer, hook installers, transcript/session registries, terminal
  jump-target logic.
- `OpenIslandHooks`: lightweight CLI invoked by agent hooks. It reads JSON from
  stdin, forwards it to the app over a Unix domain socket, and prints a response
  only when the agent needs one.
- `OpenIslandSetup`: CLI for installing hook config entries.
- `OpenIslandApp`: SwiftUI/AppKit shell, overlay, settings, discovery, and
  app-level state.

The pieces we should port first:

- `Sources/OpenIslandCore/AgentEvent.swift`
- `Sources/OpenIslandCore/AgentSession.swift`
- `Sources/OpenIslandCore/SessionState.swift`
- `Sources/OpenIslandCore/BridgeTransport.swift`
- `Sources/OpenIslandCore/BridgeServer.swift`
- `Sources/OpenIslandCore/BridgeCommandClient.swift`
- `Sources/OpenIslandCore/CodexHooks.swift`
- `Sources/OpenIslandCore/CodexHookInstaller.swift`
- `Sources/OpenIslandCore/CodexHookInstallationManager.swift`
- `Sources/OpenIslandHooks/OpenIslandHooksCLI.swift`

The pieces we should not port directly:

- `OverlayPanelController`, `OverlayUICoordinator`, and Open Island's notch
  surface chrome. Boring Notch already owns this.
- Sparkle/update code. Boring Notch already uses Sparkle.
- Launch-at-login service unless needed later. Boring Notch already has its own
  app lifecycle choices.
- Watch relay and mobile/watch targets.

## Current Boring Notch Fit

Boring Notch already has the right host architecture:

- `boringNotch/ContentView.swift` selects the closed-notch live activity,
  sneak peek, battery notification, face animation, and open-notch body.
- `boringNotch/BoringViewCoordinator.swift` owns shared UI state such as current
  tab, transient sneak peek, expanding HUD, and app-level toggles.
- `boringNotch/components/Tabs/TabSelectionView.swift` currently supports
  `Home` and `Shelf` tabs.
- `boringNotch/models/Constants.swift` defines `Defaults.Keys` for feature
  toggles.
- `boringNotch/boringNotch.entitlements` already includes network server/client
  entitlements, which is compatible with local socket/listener needs.

The integration should add agent activity as another first-class live activity,
not as a separate app.

## User Experience

### Closed Notch

When at least one agent is running:

- Show a compact agent live activity with agent name, workspace/session title,
  and a concise progress/status label.
- If music is playing, preserve music priority unless an agent needs attention.
- If an agent asks a question or needs approval, override passive closed-notch
  content with an attention state.

Recommended priority:

1. Agent approval/question attention
2. Battery/power notification
3. System HUD/sneak peek
4. Music live activity
5. Passive agent running state
6. Face/empty state

### Open Notch

Add an `Agents` tab next to `Home` and `Shelf`.

The Agents tab should show:

- Active sessions sorted by latest update.
- Agent tool label: Codex, Claude Code, Cursor, Gemini, etc.
- Status: Running, Needs approval, Needs answer, Completed.
- Current summary: command/tool/action or last assistant summary.
- Workspace/cwd where available.
- For questions: prompt title, question text, selectable options, freeform input
  when supported, Submit and Dismiss/Deny actions.
- For approvals: tool name, command/path summary, Allow and Deny actions.
- Click/jump action to return to the related terminal or Codex app when a jump
  target is available.

### Settings

Add an Agent Activity settings section:

- Master toggle: Enable Agent Activity.
- Agent toggles: Codex first, then Claude/Cursor/Gemini/OpenCode in later
  milestones.
- Install/Uninstall hooks per agent.
- Health status per agent: Not installed, Installed, Needs Codex trust review,
  Hook binary missing, Config unreadable.
- Passive display option: Show running agents in closed notch.
- Attention display option: Always open notch for questions/approvals.
- Optional sound/haptic toggle for attention events.

## Functional Requirements

### FR1: Agent Session State

Create Boring Notch equivalents of Open Island's core types:

- `AgentTool`
- `SessionPhase`
- `AgentSession`
- `AgentEvent`
- `PermissionRequest`
- `QuestionPrompt`
- `QuestionPromptResponse`
- `PermissionResolution`
- `SessionState`

`SessionState.apply(_:)` should remain the single reducer for all agent event
mutations.

### FR2: Local Bridge

Run a local Unix domain socket bridge inside Boring Notch:

- Start when Agent Activity is enabled.
- Stop when disabled or app terminates.
- Use newline-delimited JSON envelopes.
- Fail open if hooks cannot connect.
- Keep pending approval/question client connections alive until the user
  responds or timeout occurs.

Suggested Boring Notch files:

- `boringNotch/Agents/Core/BridgeTransport.swift`
- `boringNotch/Agents/Core/BridgeServer.swift`
- `boringNotch/Agents/Core/BridgeCommandClient.swift`
- `boringNotch/managers/AgentActivityManager.swift`

### FR3: Hook CLI

Add a small CLI target similar to `OpenIslandHooks`.

Responsibilities:

- Read agent hook JSON from stdin.
- Detect `OPEN_ISLAND_SKIP_HOOKS=1` and `BORING_NOTCH_SKIP_AGENT_HOOKS=1`.
- Forward payloads to the Boring Notch bridge.
- Print directive JSON only for blocking/approval/question responses.
- Exit silently if Boring Notch is not running.

Naming options:

- Product: `BoringNotchAgentHooks`
- Target: `BoringNotchAgentHooks`
- Install path: inside the app bundle under `Contents/Helpers/` or copied to
  `~/Library/Application Support/boringNotch/AgentHooks/`.

### FR4: Codex Integration First

Codex is the first milestone because the user explicitly wants Codex-style agent
questions and progress in the notch.

Port and adapt:

- `CodexHookPayload`
- Codex event parsing for `SessionStart`, `UserPromptSubmit`,
  `PermissionRequest`, `Stop`
- Optional parsing for `PreToolUse` and `PostToolUse`, but do not install these
  by default initially
- `CodexHookInstaller` behavior for `~/.codex/config.toml`
- Feature flag compatibility: `[features].hooks = true` and legacy
  `[features].codex_hooks = true`

Codex hook install default:

- `SessionStart`
- `UserPromptSubmit`
- `PermissionRequest`
- `Stop`

Codex trust review:

- After hook installation, Codex may require the user to approve hooks through
  `/hooks` in the CLI. The UI must explain this as a required external Codex
  step, not as a Boring Notch error.

### FR5: Question Rendering

Render `QuestionPrompt` in the open notch:

- Single-question and multi-question layouts.
- Radio-style choice for mutually exclusive options.
- Checkbox support for `multiSelect`.
- Text field for freeform options.
- Submit response through bridge command:
  `answerQuestion(sessionID:response:)`.

For the first milestone, support the common case:

- One question.
- One selected option or one freeform answer.

### FR6: Approval Rendering

Render `PermissionRequest` in the open notch:

- Tool/command/path summary.
- Primary action: Allow.
- Secondary action: Deny.
- Send `resolvePermission(sessionID:resolution:)` through the bridge.
- Update local UI immediately after user action.

### FR7: Closed-Notch Attention Behavior

When an agent enters `waitingForApproval` or `waitingForAnswer`:

- Show the agent attention live activity in the closed notch.
- Optionally open the notch automatically if the setting is enabled.
- Keep the notch open while the question/approval UI is active.
- Do not auto-close until the state is resolved or the user explicitly closes.

### FR8: Session Persistence and Discovery

Milestone 1 can be runtime-only.

Milestone 2 should add:

- Persist recent sessions in Application Support.
- Restore unfinished sessions on launch.
- Reconcile stale sessions when no matching process/hook is seen.

Open Island's `SessionState`, registries, and transcript discovery code can be
ported incrementally after the live bridge is stable.

## Proposed Architecture

```text
Agent hook
  -> BoringNotchAgentHooks CLI
  -> Unix socket JSON bridge
  -> AgentActivityManager
  -> SessionState reducer
  -> BoringViewCoordinator / ContentView
  -> Notch closed live activity or Agents tab
  -> user response
  -> BridgeServer pending response
  -> CLI stdout directive
  -> Agent continues
```

### New Modules

`boringNotch/Agents/Core`

- Ported data models and bridge protocol.
- Pure Swift/Foundation where possible.

`boringNotch/Agents/Integrations/Codex`

- Codex hook payload parser.
- Codex directive output models.
- Codex config installer.

`boringNotch/Agents/UI`

- `AgentLiveActivityView`
- `AgentAttentionView`
- `AgentsTabView`
- `AgentSessionRow`
- `AgentQuestionCard`
- `AgentPermissionCard`

`boringNotch/managers/AgentActivityManager.swift`

- Main app-facing state owner.
- Starts/stops bridge.
- Applies events.
- Exposes `activeActionableSession`, `runningCount`, and `sessions`.
- Sends answers/approvals.

### Coordinator Changes

Add to `BoringViewCoordinator`:

- `@Published var agentAttentionSessionID: String?`
- `@AppStorage("agentActivityEnabled") var agentActivityEnabled`
- `@AppStorage("agentActivityShowPassiveClosed") var agentActivityShowPassiveClosed`
- `@AppStorage("agentActivityOpenForAttention") var agentActivityOpenForAttention`

Add `NotchViews.agents` and a new tab in `TabSelectionView.swift`.

### ContentView Changes

Insert the closed-notch priority branch before music live activity:

- If `AgentActivityManager.shared.activeActionableSession != nil`, show
  `AgentAttentionLiveActivity`.
- Else if passive agent display enabled and running sessions exist, show
  `AgentRunningLiveActivity`.
- Existing music/HUD/battery branches remain intact.

In open notch switch:

- Add `.agents: AgentsTabView()`.

## Data Model Mapping

| Open Island | Boring Notch Target |
|---|---|
| `AppModel.state` | `AgentActivityManager.state` |
| `SessionState.activeActionableSession` | closed-notch attention source |
| `IslandSurface.notificationSurface` | coordinator attention/session selection |
| `BridgeServer.emit(_:)` | manager event callback |
| `approvePermission(...)` | manager action + bridge command |
| `answerQuestion(...)` | manager action + bridge command |
| `HookInstallationCoordinator` | settings-facing hook install manager |
| `TerminalJumpService` | later optional `AgentJumpService` |

## Milestones

### Milestone 0: Spike and Legal Hygiene

- Copy/port a minimal subset into a feature branch.
- Preserve GPL v3 headers/attribution where code is copied.
- Add Open Island to third-party acknowledgements.
- Confirm build still succeeds with Xcode project target layout.

Exit criteria:

- No UI yet.
- Codex model parser tests pass.

### Milestone 1: Codex Live Status

- Add `AgentActivityManager`.
- Add bridge server.
- Add hook CLI target.
- Add Codex hook parsing for start/prompt/stop.
- Add closed-notch passive running state.
- Add `Agents` tab with read-only session list.

Exit criteria:

- Starting a Codex session creates a visible session in the notch.
- Submitting a prompt updates the summary.
- Stop marks the session completed.
- Existing music/shelf/HUD flows still work.

### Milestone 2: Codex Questions and Approvals

- Add pending response handling in bridge server.
- Render `PermissionRequest`.
- Render basic `QuestionPrompt`.
- Allow/deny/answer from the notch.
- Add auto-open-on-attention option.

Exit criteria:

- A Codex permission request can be allowed or denied from Boring Notch.
- A Codex question can be answered from Boring Notch.
- Hook process times out/fails open if Boring Notch is unavailable.

### Milestone 3: Hook Installation UI

- Add settings controls for Codex hook install/uninstall/status.
- Detect Codex hook feature flag style.
- Show Codex trust-review guidance after install.
- Add health checks for missing binary and unreadable config.

Exit criteria:

- User can install and uninstall Codex hooks from Settings.
- Hook status updates without restarting the app.

### Milestone 4: Multi-Agent Expansion

Port additional integrations in order:

1. Claude Code and Claude-compatible forks.
2. Cursor.
3. Gemini CLI.
4. OpenCode.
5. Kimi CLI.

Exit criteria:

- Each agent can produce session lifecycle events.
- Approval/question flows work for agents that support them.
- Unsupported agents remain hidden without errors.

### Milestone 5: Jump-Back and Session Recovery

- Add jump-back for Codex app and common terminals.
- Persist sessions.
- Reconcile stale/running sessions across app launches.
- Optionally add transcript discovery.

Exit criteria:

- Clicking a session opens the correct app/terminal where supported.
- Relaunching Boring Notch keeps recent actionable sessions understandable.

## Testing Strategy

### Unit Tests

Add tests for:

- `SessionState.apply(_:)` transitions.
- Codex hook payload parsing.
- Bridge JSON envelope encode/decode.
- Permission resolution directive output.
- Question response directive output.
- Hook installer TOML/config mutations.

### Integration Tests

- Start app bridge.
- Send synthetic hook payload through CLI.
- Assert session appears in manager state.
- Send permission request and resolve it.
- Confirm CLI receives correct directive JSON.

### Manual Tests

- Build and install local app over `/Applications/boringNotch.app`.
- Install Codex hooks from Settings.
- Run `/hooks` in Codex and approve expected hooks.
- Start Codex in this repo.
- Verify closed-notch running state.
- Trigger a permission request.
- Approve from notch.
- Trigger a question.
- Answer from notch.
- Confirm existing music live activity still appears when no agent needs
  attention.

## Risks and Mitigations

### Risk: Hook Config Corruption

Mitigation:

- Use structured TOML/JSON parsing when possible.
- Backup config files before modification.
- Make uninstall reversible and scoped only to managed entries.

### Risk: UI Priority Conflicts

Mitigation:

- Make attention events highest priority, passive running agents lower priority
  than music.
- Keep feature disabled by default until stable.

### Risk: Long-Lived Hook Blocking

Mitigation:

- Use explicit timeouts.
- Fail open when bridge is unavailable.
- Show pending state in UI but do not deadlock the agent.

### Risk: Xcode Project Complexity

Mitigation:

- Start by adding source files directly to the existing Xcode project.
- Add a separate helper executable target only when the bridge protocol is
  proven.
- Avoid introducing a full SPM package restructuring in the first pass.

### Risk: Swift 6 Concurrency Warnings

Mitigation:

- Keep bridge server on a private serial queue.
- Keep UI mutations on `@MainActor`.
- Preserve `Sendable` model boundaries from Open Island.

## Open Questions

- Should Agent Activity be enabled by default after first install, or only after
  the user installs at least one hook?
- Should passive running-agent state replace the face animation, or only appear
  when explicitly enabled?
- Should the first release support Codex CLI only, or Codex CLI plus Codex app
  deep links?
- Should Boring Notch keep Open Island's `OPEN_ISLAND_SKIP_HOOKS` compatibility
  name, or only support a Boring Notch-specific skip variable?

## Recommended First Implementation Plan

1. Add the `Agents/Core` model and reducer subset.
2. Add tests for reducer and Codex payload parsing.
3. Add `AgentActivityManager` with synthetic event injection for local testing.
4. Add `Agents` tab and passive closed-notch UI.
5. Add bridge server and CLI target.
6. Wire Codex lifecycle hooks.
7. Add question/approval response flow.
8. Add Settings install/uninstall UI.

This order gives visible progress early while keeping the risky hook and IPC
work isolated until the Boring Notch UI integration is proven.
