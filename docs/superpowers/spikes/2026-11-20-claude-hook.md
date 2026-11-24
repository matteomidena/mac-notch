# Spike: Claude Code PreToolUse hook outputs

Date: 2026-11-20 · Plan Task 2

## Verdict

- **Desktop app: GO.** A desktop Code session opened on a throwaway folder ran the folder's project-level `PreToolUse` hook on every tool call. Both outputs behaved as the plan needs.
- **CLI (`claude -p`): untested.** The CLI login on this Mac has ended ("this login reached its time limit and cannot be renewed"), so no CLI session could run. The desktop app runs the same `claude` binary (`CLAUDE_CODE_EXECPATH`), and 58 of the 59 sessions in the last 7 days were desktop sessions.
- Task 21 may install the hook. Ask the owner first, as the plan says.

## Setup

- Throwaway folder `<scratchpad>/hook-spike` with `.claude/settings.json`:
  `{"hooks":{"PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"sh \"$CLAUDE_PROJECT_DIR/hook.sh\""}]}]}}`
- `hook.sh` logged its stdin to `log/<mode>-<n>.json` and answered according to a `mode` file (`none`, `deny` or `stop`).
- `~/.claude/settings.json` was not touched.
- The session was a fresh desktop session (`entrypoint: claude-desktop`, permission mode `auto`). The test messages went in as ordinary user turns.

## Results

### Deny

Output:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"The user redirected you: say hello and stop"}}
```

The message was "Run `ls` in this folder…". The `Bash` call was blocked, and the model followed the reason text. Its reply, in full: "Hello! `ls` never ran: a PreToolUse hook blocked the Bash call and said 'say hello and stop', so I have no output to report." It made no further tool calls. **Redirect works.**

### Stop

Output:

```json
{"continue":false,"stopReason":"Stopped from OpenNotch"}
```

The message was "Please run `ls` … again".

- The transcript records a `hook_stopped_continuation` attachment, rendered to the model as "PreToolUse:Bash hook stopped continuation: Stopped from OpenNotch".
- The turn ended there, with no further assistant message. **Stop works.**
- The `Bash` call got a placeholder result, "(Bash completed with no output)", with empty stdout. The folder holds three visible entries (`hook.sh`, `log`, `mode`), so the command most likely never ran. In its next turn the session claimed the command "did run"; the empty stdout contradicts that.
- **Consequence for Task 21:** Stop ends the turn but must not be relied on to let an in-flight call finish. Treat the call as dropped.

### Sub-agent tool calls

Mode `none`, message "Use a subagent (the Agent tool) to run `ls`…". Three calls were logged:

| Call | `session_id` | `agent_id` / `agent_type` |
|---|---|---|
| `Agent` (parent) | parent session | absent |
| `Bash` inside the sub-agent | **parent session** | `<agent id>` / `general-purpose` |
| `SubagentHandback` inside the sub-agent | **parent session** | `<agent id>` / `general-purpose` |

- **A sub-agent's tool calls carry the parent `session_id`**, as well as the parent's `transcript_path`.
- So a directive keyed by the parent session also reaches its sub-agents, which matches the rule "sub-agent work rolls up into its parent".
- Not tested: a deny or stop answered *inside* a sub-agent. Whether it ends only the sub-agent's turn or the parent's is unknown, so the Task 24 manual DoD should cover it.

## Stdin fields

PreToolUse stdin is one JSON object. In the order received:

| Field | Example / type |
|---|---|
| `session_id` | UUID string. Always the **first** key. |
| `transcript_path` | absolute path of the session `.jsonl` |
| `cwd` | session folder |
| `scratchpad_dir` | path |
| `prompt_id` | UUID string |
| `agent_id`, `agent_type` | only on calls made inside a sub-agent |
| `permission_mode` | `"auto"` |
| `effort` | `{"level":"xhigh"}` |
| `hook_event_name` | `"PreToolUse"` |
| `tool_name` | `"Bash"`, `"Agent"`, `"SubagentHandback"`, … |
| `tool_input` | the tool's arguments (object) |
| `tool_use_id` | `toolu_…` |

`session_id` comes first and `tool_input` comes later. So Ruling R1 (take the **first** `"session_id"` match) reads the right value even when a tool's input contains its own `session_id` key.

## Run time

- `sh hook.sh < sample.json` with no directive file, using the Task 11 script that follows R1 (first match plus `case` check): median **7.0 ms** and **8.8 ms** over 20 runs each (two batches), max 30 ms on a cold first run. Budget: < 20 ms.
- In the app, the spike hook (which also lists `log/` and writes a file) reported `durationMs: 21` for the stop call. That includes spawning `sh`.
- The hook fails open: with an empty or missing `mode` file it prints nothing and exits 0, and the call goes ahead (all three `none` calls).
