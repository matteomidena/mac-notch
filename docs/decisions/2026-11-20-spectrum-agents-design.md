# Approve the design doc for the spectrum and agents monitor?

Decided: 2026-11-20 · Case: c_e291a044-c99b-4bab-9d75-3af07602cbb6

## Question and choice
Is the design doc `docs/superpowers/specs/2026-11-20-spectrum-and-agents-design.md` ready to plan from?

Chosen: "Approve the design doc as written, with my calls. I commit the docs and write the implementation plan."

Two answers given before the approval (in the terminal) are part of the doc:
- Claude 5-hour and weekly %: "Usage endpoint". The app reads the numbers `/usage` shows, with the Claude Code login token in the Keychain.
- Codex Stop and Redirect: "Monitor only". Codex runs are flagged, with no Stop or Redirect buttons.

## Why
- The owner chose the usage endpoint because the status line almost never runs. In the last 7 days, 58 of 59 Claude sessions ran in the desktop app, which does not run the status line.
- The owner chose monitor only for Codex. All 189 Codex runs of the last 7 days were `codex exec` jobs started by Claude sessions. A running exec job takes no new message.
- Agent's reason: the builder check found four gaps. The owner's answers close two. The agent's calls close the other two.

## Constraints
- The app only reads the Claude Code token. It never refreshes, writes or copies it.
- The Keychain prompt appears only after the owner clicks "Connect" in Settings.
- Claude usage is fetched when a transcript changes (at most once a minute) and when the panel opens. No timer.
- Stop and Redirect exist for Claude Code sessions only, through a `PreToolUse` hook that fails open.
- Sub-agent work counts with its parent session for rate and baseline.
- The runaway strip stays 30 s, then folds into a "4.3×" badge. The × dismisses it and starts the 15-minute cooldown.
- The plugin API change is additive (minor bump). Existing `.notchplugin` bundles still load.
- The look constraints in `docs/decisions/2026-11-20-notch-look.md` still apply.

## Ruled out
- Status-line wrapper for Claude limits: desktop-app sessions do not run the status line.
- Status line only, with last value and age: the numbers would almost always be stale.
- No Claude %, tokens only: the owner wants plan usage at a glance.
- Codex Stop by quitting the process: the owner chose monitor only.
- Codex Redirect through `codex queue`: it only takes effect if the run resumes.
- Codex blocking hook: not needed with monitor only.

## Comments
none

## Open questions
none. Four spikes come first in the plan: audio tap with ad-hoc signing, Claude hook output, the usage endpoint, key focus in the notch panel.

## Sources
- Case c_e291a044-c99b-4bab-9d75-3af07602cbb6
- `docs/superpowers/specs/2026-11-20-spectrum-and-agents-design.md` (approved design)
- `docs/decisions/2026-11-20-notch-look.md` (approved look)
- Local check: `entrypoint` of Claude transcripts from the last 7 days (58 `claude-desktop`, 1 `cli`)
- Local check: `originator` of Codex rollouts from the last 7 days (189 `codex_exec`)
