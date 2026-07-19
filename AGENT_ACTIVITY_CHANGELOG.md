# Agent Activity Changelog and Roadmap

Source reviewed: https://vibeisland.app/changelog/

## Comparison: Vibe Island Features We Do Not Have Yet

### Agent integrations

Vibe Island supports or mentions live integrations for a much wider agent list: Grok Build CLI, Orca, herdr, Craft Agent, Supacode, Otty, Oh My Pi, ZCode, Trae, MiMoCode, Mistral Vibe, Antigravity CLI, Tencent WorkBuddy, DeepSeek CLI, Kiro, Amp, Hermes, Qoder, Cursor Agent, OpenCode, Gemini CLI, Copilot CLI, CodePilot, and remote Codex App sessions.

Current Boring Notch state: the model has enum cases for Codex, Claude Code, Cursor, Gemini, OpenCode, and Kimi, but real hook install / bridge parsing is implemented only for Codex and Claude Code. Running-process detection currently targets Codex and Claude Code.

### Precise jump-back

Vibe Island has precise jump support for many hosts: VS Code, Cursor, Warp, Ghostty, WezTerm, tmux, Zellij, Kitty, Otty, Superset, herdr, Orca, Codex Desktop threads, VS Code native Claude extension panes, remote Codex App sessions, and SSH remote sessions.

Current Boring Notch state: no jump-back implementation yet. Sessions can show in the notch, but clicking does not route to the exact terminal tab, IDE pane, workspace, or remote thread.

### SSH and remote agents

Vibe Island has SSH Remote support with tunnels, remote hook deployment, reconnect handling, passphrase keys, `ProxyJump` / `ProxyCommand` support, isolated ports per host, trust status, manual connection mode for enterprise SSO, and Docker/container setup guidance.

Current Boring Notch state: no remote agent model, no SSH tunnel manager, no remote hook installer, and no remote session bridge.

### Usage and quota tracking

Vibe Island tracks Claude, Codex, Kimi, z.ai, and other provider quota/rate-limit states, including partial rate-limit windows, reset times, API errors, and inline warnings.

Current Boring Notch state: no usage/quota panel and no provider-specific usage parsers.

### Approval and question depth

Vibe Island supports plan review, Auto Mode / Bypass modes, Claude permission mode preservation, parallel approval queues, multi-question AskUserQuestion pagination, keyboard shortcuts, "Always allow" style decisions, trust authorization for Codex hooks, and routing approval cards correctly across parallel subagents.

Current Boring Notch state: basic permission allow/deny and basic question answer UI exist for Codex/Claude hook events. There is no plan-review mode, multi-question pagination, parallel approval queue management, trust authorization UI, or permission-mode synchronization.

### Subagents and team display

Vibe Island has nested subagent sessions, subagent lifecycle tracking, Agent Team filtering, child-session muting, subagent display controls, and duplicate/ghost subagent cleanup.

Current Boring Notch state: Claude subagent hook names are parsed into status updates, but there is no parent/child session model or subagent UI.

### Silence / quiet controls

Vibe Island has Quiet scenes, Quiet Hours, Focus-mode silence, screen-lock silence, screen-recording/share silence, custom silence rules by prompt/app/title/tool, quick mute, and first-prompt filters.

Current Boring Notch state: no agent-specific silence engine. We only have basic notch behavior toggles for passive closed-notch display and auto-open on attention.

### Session persistence and cleanup

Vibe Island persists session cards across restarts, cleans ghost sessions when host IDEs close, self-heals stuck pending states, repairs overwritten hooks, detects config drift, supports custom config paths, handles JSONC settings, and avoids false hook-removed prompts.

Current Boring Notch state: session state is in memory. Process sessions are recreated by polling running processes, but hook-backed sessions do not persist across app restart. Hook install writes managed config entries but does not yet have full drift repair / JSONC / custom-path coverage.

### Notifications, sounds, and reminders

Vibe Island has completion alerts, idle reminders, custom sounds per event, Apple system sounds, sound muting controls, and notification routing that avoids duplicates when the user is already viewing a session.

Current Boring Notch state: no agent-specific sounds, reminders, completion notifications, or duplicate-notification suppression.

### Settings, diagnostics, and production operations

Vibe Island has a mature integrations/settings area, update controls, license/device management, diagnostics export with privacy redaction, crash monitoring, localization in multiple languages, and extension auto-install for IDEs.

Current Boring Notch state: Agent Activity settings are early: enable toggle, behavior toggles, Codex/Claude hook install rows, and preview/demo buttons.

## Boring Notch Agent Activity Changelog

### Unreleased

#### Added

- Added an Agent Activity model layer for agent sessions, phases, permissions, and questions.
- Added an Agents tab in the notch.
- Added passive running-agent detection for Codex and Claude Code processes, including VS Code and terminal-launched instances.
- Added a local Unix-socket bridge for agent hook events.
- Added a bundled `BoringNotchAgentHooks` helper CLI for Codex and Claude Code.
- Added Codex hook parsing for session start, prompt submission, tool status, permission requests, and stop events.
- Added Claude Code hook parsing for session start, prompt submission, tool status, permission requests, AskUserQuestion-style prompts, subagent start/stop status, notifications, compacting, and stop/failure events.
- Added basic permission approval UI with allow/deny actions.
- Added basic question UI with option and freeform answer support.
- Added hook install/uninstall/status UI for Codex and Claude Code.
- Added an unsandboxed XPC helper path for writing Codex and Claude hook config.
- Added closed-notch passive agent indicators and auto-open behavior for actionable sessions.

#### Fixed

- Fixed app restart to relaunch the currently running Debug bundle instead of an older `/Applications` copy.
- Fixed the agent bridge socket path for sandboxed app launches.
- Fixed app exit on hook events caused by `SIGPIPE`.
- Fixed process scanning deadlock when `ps` output is large.
- Fixed hook-install UI staying disabled after a stuck helper operation by adding real UI-side timeout recovery.
- Fixed stale helper/media adapter confusion during local debug restarts.

#### Verified

- Build succeeds with `xcodebuild build -project boringNotch.xcodeproj -scheme boringNotch -destination 'platform=macOS'`.
- Tests succeed with `xcodebuild test -project boringNotch.xcodeproj -scheme boringNotchTests -destination 'platform=macOS'`.
- Local synthetic Codex and Claude hook events reach the app without crashing it.
- Process scanner detects multiple running Codex and Claude Code instances.

## TODO

### P0: Make Current Codex/Claude Support Production-Ready

- Add visible bridge/installer health diagnostics in Settings instead of relying on logs.
- Add hook trust guidance and a Codex `/hooks` trust-review flow.
- Add JSONC-safe config editing for Claude settings.
- Add custom Codex and Claude config path support.
- Add hook drift detection and one-click repair.
- Add reliable completion detection and completion notifications.
- Persist hook-backed sessions across app restart.
- Add cleanup rules for stale hook sessions and closed host IDEs.
- Add tests for bridge event decoding and XPC envelope parsing.

### P1: Jump-Back

- Add a session host model: terminal app, IDE, workspace, tab, pane, process ID, cwd.
- Implement click-to-jump for VS Code integrated terminals.
- Implement click-to-jump for Cursor integrated terminals.
- Implement terminal focus fallback for Terminal.app, iTerm, Warp, and Ghostty.
- Add exact-pane routing where host APIs make it possible.
- Add session card actions: reveal, copy cwd, copy command, dismiss.

### P2: Better Approval and Question Handling

- Add a parallel approval queue per session.
- Add multi-question AskUserQuestion pagination.
- Add keyboard shortcuts for approval/question cards.
- Add plan-review style UI.
- Add Claude Auto Mode / permission mode awareness.
- Add "always allow" / scoped allow decisions where the upstream agent supports it.

### P3: More Agents

- Implement real integrations for OpenCode, Gemini CLI, Cursor Agent, Kimi Code, DeepSeek CLI, and Copilot CLI.
- Keep unsupported enum cases hidden until they have real hooks/process detection.
- Add per-agent install status, health checks, and uninstall.

### P4: Subagents and Session Organization

- Add parent/child session IDs.
- Nest subagents under parent sessions.
- Add subagent display controls.
- Suppress duplicate completion notifications from child agents.
- Add worktree and branch indicators.
- Add optional model name display.

### P5: Remote and Container Support

- Add SSH Remote session model.
- Add remote hook deployment.
- Add tunnel lifecycle management.
- Add manual remote connection mode for browser/SSO hosts.
- Add Docker/container setup guidance.

### P6: Quiet Modes and Notifications

- Add Quiet Hours.
- Add Focus-mode silence.
- Add screen-lock and screen-recording/share silence.
- Add custom silence rules by app, prompt text, cwd, title, and agent.
- Add completion sounds and per-event sound settings.
- Add duplicate notification suppression when the related IDE pane is already focused.

### P7: Diagnostics and Polish

- Add one-click diagnostics export with privacy redaction.
- Add a Settings health page for bridge socket, helper binary, hook config, and last hook event.
- Add large-session-list virtualization.
- Add localization strings for all Agent Activity UI.
- Add production crash breadcrumbs around bridge, XPC, hook install, and process scanning.
