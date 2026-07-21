# Agent Activity — Progress Tracker

Living status log for the Agent Activity integration (see
`docs/agent-activity-integration-prd.md` for the original PRD and
`AGENT_ACTIVITY_CHANGELOG.md` for the shipped changelog and the full P0–P7
backlog). This file tracks what's actually done vs. in flight across work
sessions, including uncommitted state, so a new session can pick up context
fast without re-deriving it from git history.

## Current state (as of 2026-07-21)

- Shipped (on `main`): core session models/reducer, Agents tab UI, process
  detection for Codex/Claude Code, local bridge + hook CLI, permission/question
  UI, hook install/uninstall UI. See `AGENT_ACTIVITY_CHANGELOG.md` → Unreleased.
- Uncommitted on disk, *not* part of this patch: `BridgeServer` /
  `BridgeTransport` / `BoringNotchAgentHooks` changes adding `PreToolUse`-driven
  handling for Claude's `AskUserQuestion` and `ExitPlanMode` (plan review),
  plus a `PreToolUse` hook timeout bump. Pre-existing work in progress from
  before this session — left untouched. Note: the backend wiring here has no
  UI counterpart yet — a plan review currently renders as a generic question
  card ("Accept plan"/"Reject plan") with no plan-text rendering. Worth a
  dedicated pass before this is user-facing (P2 backlog: "Add plan-review
  style UI").
- Active patch: **P1 Jump-Back, click-to-jump** — ready to commit, see
  `PATCH.md`. Verified this session with real GUI/interactive access (build,
  full test suite, and a live two-session collision test); found and fixed a
  genuine session-unification bug in the process. True click-to-jump (row
  click → app/tab raised) still needs a human to grant two macOS permissions
  and click a row once — see `PATCH.md` → Testing for exactly what's left and
  why it couldn't be automated here.

## Backlog snapshot

Priorities P0–P7 live in `AGENT_ACTIVITY_CHANGELOG.md` → `## TODO`. This file
only calls out what's actively being worked on or just finished; check the
changelog for the full backlog and to mark items done there once a patch
lands.

## Session log

### 2026-07-19

- Set up `PROGRESS.md` / `PATCH.md` for tracking.
- Shipped the first slice of P1 jump-back: `pid`/`tty` added to the session
  host model, a new `AgentJumpService` (AppleScript activation, exact-tab
  routing for Terminal.app/iTerm2 via `tty`), and a tap target + hover
  affordance on `AgentSessionRow` that jumps then closes the notch. Build and
  `boringNotchTests` both green. `AGENT_ACTIVITY_CHANGELOG.md` P1 section
  updated to mark what's done vs. still open (VS Code/Cursor exact-pane,
  tmux/Zellij, session card actions, hook/process session unification).
  Full design rationale and remaining checklist in `PATCH.md`.
- Not yet done: manual in-app verification (clicking a real session row in a
  running build against live Terminal/iTerm2 sessions) — needs an interactive
  macOS session, not available in this work loop.

### 2026-07-21

- This session *did* have real interactive GUI access (contrary to the note
  above) — rebuilt fresh, relaunched the Debug app, and drove a real second
  Claude Code session in Terminal.app alongside this conversation's own
  hook-backed session, both in `~/Code/boring.notch`.
- Found and fixed a real bug this surfaced: two sessions sharing `(tool, cwd)`
  collided into a single, flapping session card because
  `SessionState.matchingHookSessionID` had no per-pass uniqueness guard.
  Fixed with a claimed-ID set in `reconcileProcessSnapshots`; added
  `testMultipleProcessSnapshotsMatchingSameHookSessionDoNotCollide` to
  `SessionStateTests`. Rebuilt and reran the full suite (19/19 green) after
  the fix.
- Confirmed two environment-specific (not code) blockers that stopped the
  click-to-jump step itself from being driven end-to-end here: no
  Accessibility permission for automated UI clicking in this shell, and the
  process scanner's own permission ("Grant Permission" banner in the notch,
  likely Full Disk Access for the XPC helper) not yet granted on this
  machine. Left both for the user — see `PATCH.md` → Testing.
- Committed the P1 patch (fix + regression test + doc updates).
