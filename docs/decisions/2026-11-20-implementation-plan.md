# Approve the implementation plan, and how should it run?

Decided: 2026-11-20 · Case: c_5c1a6606-1124-444d-973d-fb33989822e1

## Question and choice
Does the plan `docs/superpowers/plans/2026-11-20-spectrum-and-agents.md` capture what the owner wants, and how should it run?

- Plan: "Approve the plan as written."
- Method: "Subagent-driven". A fresh agent builds each task, and a fresh reviewer checks it before the next one starts. A whole-branch review runs at the end.

## Why
- The plan covers every part of the approved design. The risky parts are four spikes that run first.
- Agent's reason for subagent-driven: there are 24 tasks with fixed interfaces between them. The hook and the settings patch touch the owner's Claude setup, so a review after each task is worth the cost.

## Constraints
- Run with superpowers:subagent-driven-development, one task at a time, in plan order.
- Task 1 asks the owner in chat before it reads the Claude Code token.
- Task 2 never edits `~/.claude/settings.json`; it uses a project-level settings file in a throwaway folder.
- Task 17 asks the owner before it downloads the Inter font.
- A NO-GO spike stops the run at the task that depends on it, and the owner is told.
- Every task keeps the plan's Global Constraints.

## Ruled out
- Native execution (all tasks in one session, one review at the end): no independent review until the end.
- Changing the plan before building: the owner approved it as written.

## Comments
none

## Open questions
none

## Sources
- Case c_5c1a6606-1124-444d-973d-fb33989822e1
- `docs/superpowers/plans/2026-11-20-spectrum-and-agents.md`
- `docs/decisions/2026-11-20-spectrum-agents-design.md`
- `docs/decisions/2026-11-20-notch-look.md`
