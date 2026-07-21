# Patch: P1 Jump-Back — Click-to-Jump

Status: ready to commit
Backlog item: `AGENT_ACTIVITY_CHANGELOG.md` → `P1: Jump-Back`

## Goal

Clicking an agent session row in the Agents tab activates the host
application (and, where the host API allows it, the exact window/tab)
running that agent, then closes the notch — matching the PRD's "Click/jump
action to return to the related terminal or Codex app" requirement.

## Scope for this patch

In scope:

- Extend the session host model with `pid` and `tty` (process-scanned
  sessions only — hook-only sessions don't carry a host application yet, see
  Deferred below).
- `AgentJumpService`: AppleScript-based activation, reusing the existing
  `AppleScriptHelper` pattern already used by the media controllers.
- Exact tab/window routing for Terminal.app and iTerm2 via `tty` matching —
  both expose a scriptable `tty` property per tab/session.
- VS Code and Cursor integrated-terminal jump: open/raise the session
  workspace in the matching editor, then focus the integrated terminal via the
  command palette.
- Best-effort `activate` (app-level, no exact pane) for Warp, Ghostty,
  WezTerm, and any other detected host.
- Tap target on `AgentSessionRow` (the icon + text column, not the
  permission/question cards) with a hover affordance.
- Close the notch after a successful jump.

Explicitly deferred (still open under P1 in the changelog — not this patch):

- Exact split/pane selection inside VS Code / Cursor integrated terminals
  (needs an extension-side bridge; no such extension exists yet).
- tmux/Zellij pane routing.
- Session card actions (reveal in Finder, copy cwd, copy command, dismiss).

## Design notes

- `pid`/`tty` live on `AgentProcessSnapshot` (XPC helper scan) and are copied
  onto `AgentSession` in `SessionState.reconcileProcessSnapshots`.
  Hook-driven sessions inherit host metadata when a process-scanned session
  has the same tool and working directory.
- `tty` comes from `ps -o tty=` inside the unsandboxed XPC helper (the same
  place that already shells out to `ps`/`lsof` for process scanning) — the
  main app is sandboxed and can't spawn processes itself. Normalized to a
  `/dev/ttyXXX` path since Terminal/iTerm report full device paths.
- Activation happens from the main (sandboxed) app via `NSAppleScript`,
  matching `AppleScriptHelper`/`MusicManager`'s existing pattern — sandboxed
  apps can send Apple Events (the automation entitlement is already present)
  without an XPC round-trip.
- Terminal.app and iTerm2 both expose a `tty` property per tab/session via
  AppleScript, so those two get exact routing; every other host only
  supports "bring the app to front."
- VS Code/Cursor do not expose an app-side API for selecting an exact
  integrated terminal by `tty`, so the app opens the workspace and executes
  `Terminal: Focus Terminal` through the command palette. This may require
  macOS Accessibility permission for Boring Notch to send keystrokes.
- Jump availability is gated on `session.hostApplication != nil`, not on the
  `process:` session-ID prefix — so if hook sessions later gain a host
  application, jump works for them for free.

## Checklist

- [x] Add `tty` to `AgentProcessSnapshot` + XPC scanner (`ps -o tty=`).
- [x] Add `pid`/`tty` to `AgentSession`, threaded through
      `SessionState.reconcileProcessSnapshots`.
- [x] `AgentJumpService` with Terminal/iTerm exact-tab routing + generic
      activate fallback for other hosts.
- [x] VS Code/Cursor workspace jump + integrated-terminal focus.
- [x] Tap target + hover affordance on `AgentSessionRow`.
- [x] Close the notch after a successful jump.
- [x] Hook/process session unification for host metadata.
- [x] Manual verification in a built app (see Testing) — found and fixed a
      real collision bug in the unification logic (see below).

## Files touched

- `BoringNotchXPCHelper/AgentProcessScanner.swift`
- `boringNotch/Agents/Core/AgentProcessSnapshot.swift`
- `boringNotch/Agents/Core/AgentSession.swift`
- `boringNotch/Agents/Core/SessionState.swift`
- `boringNotch/Agents/Core/AgentJumpService.swift` (new)
- `boringNotch/Agents/UI/AgentSessionRow.swift`

## Testing

- [x] Build: `xcodebuild build -project boringNotch.xcodeproj -scheme boringNotch -destination 'platform=macOS'` — succeeds.
- [x] Tests: `xcodebuild test -project boringNotch.xcodeproj -scheme boringNotchTests -destination 'platform=macOS'` — all 19 pass, including
      `SessionStateTests.testProcessSnapshotsCreateUpdateAndRemoveProcessSessions`
      and the new `testMultipleProcessSnapshotsMatchingSameHookSessionDoNotCollide`.
- [x] `osacompile` syntax-checked the Terminal.app and iTerm2 AppleScript templates in `AgentJumpService` (compiles cleanly against each app's live scripting dictionary).
- [x] **This session had real interactive/GUI access** (unlike the assumption
      below from the prior session) — a live Debug build was running, Terminal.app
      and VS Code were available, and `claude`/`codex` CLIs were installed.
      Rebuilt fresh, killed the stale running instance, relaunched, and drove a
      real `claude` process in a new Terminal.app tab (`cd ~/Code/boring.notch
      && claude`, tty `/dev/ttys013`) plus this very conversation's own
      hook-backed Claude Code session (also cwd'd in `boring.notch`) as a second,
      independent, real session. Confirmed via `screencapture` screenshots of the
      live notch UI.
- [x] **Found and fixed a real bug via this live test**: with two genuinely
      distinct Claude Code sessions sharing the same `(tool, cwd)` — an
      everyday case (two terminal tabs open in the same repo) — the notch
      showed only **one** "Claude Code" row, and it visibly flapped between the
      two sessions' identity across scanner polls (host app tag and status
      text from different sessions bleeding into the same card). Root cause:
      `SessionState.matchingHookSessionID` had no per-reconciliation-pass
      uniqueness guard, so multiple process snapshots could all match and
      merge into the *same* hook session, each overwriting the previous
      snapshot's `pid`/`tty`/`hostApplication` — meaning a jump could silently
      route to the wrong terminal, and one of the two real sessions was
      dropped from the UI entirely. Fixed in `SessionState.swift` by tracking
      claimed hook session IDs within a single `reconcileProcessSnapshots`
      pass; a second colliding snapshot now falls through to its own
      independent `process:`-prefixed session instead of overwriting the
      first. Covered by a new regression test. Rebuilt + retested green after
      the fix (still 19/19).
- [ ] Manual, click-to-jump itself (row click → exact tab raised): **could not
      be driven end-to-end even with real GUI access**, for two independent,
      environment-specific reasons on this dev machine, neither a code defect:
      1. Automated UI clicking (`System Events`) is blocked — `osascript` in
         this shell gets `-25211 (not allowed assistive access)`. Simulating a
         real click on the session row needs Accessibility permission granted
         to whatever process runs shell commands here; that's a broad,
         security-sensitive grant not appropriate to request just for this
         one-time test.
      2. Process scanning itself is gated behind an as-yet-ungranted
         permission on this machine — the notch UI shows a persistent "Folder
         unavailable from process scan" banner with a "Grant Permission"
         button (likely Full Disk Access for the XPC helper's `ps`/`lsof`
         calls). Without it, the Terminal.app `claude` process never surfaced
         as its own row at all in this session, only via the hook path.
      **Remaining manual step for a human with the GUI in front of them**:
      open System Settings and grant the process-scan permission via the
      notch's own "Grant Permission" button, run `claude`/`codex` in
      Terminal.app, iTerm2, and a VS Code integrated terminal, and click each
      session row to confirm the exact tab/pane raises and the notch closes
      after. Given the collision bug just found and fixed, this is now more
      likely to work correctly, but the exact-tab AppleScript path itself
      (Terminal `tty` matching, VS Code command-palette focus) is still only
      verified by static/syntax checks, not a real click.
- [ ] Manual: confirm clicking a row with no known host application is a
      no-op (not a crash) — same blocker as above (needs real click
      simulation).
