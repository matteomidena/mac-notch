# OpenNotch — Music spectrum + AI agents monitor — Design

**Date:** 2026-11-20
**Status:** Draft. Look approved (see `docs/decisions/2026-11-20-notch-look.md`). Builder check done; the owner's answers are folded in.
**Baseline:** branch `feature/open-notch-m1` after M3 (plugin platform). The rules of `2026-07-07-open-notch-v2-design.md` still apply: pure logic in `OpenNotchKit`, test-first with swift-testing; AppKit/OS code in `OpenNotch` with a manual DoD; plugins import only SwiftUI and get OS access through `PluginHost`; first-party plugins get no privileges; event-driven, no polling loops.
**Approved look:** `docs/superpowers/mockups/notch-look/index.html`. It is the visual spec. Where this text and the mockup disagree, the mockup wins on look and this text wins on behaviour.

## Intent

The owner runs many Claude Code and Codex sessions in parallel, on subscriptions (Claude plan, ChatGPT/Codex plan). They want three things from the notch:

1. **See plan usage at a glance**: how much of each plan window is used, when it resets, whether Codex credits are left.
2. **Catch a runaway session early**: when one session burns far more than it should, the notch says *which* session it is. For a Claude Code session it lets them **stop** it or **redirect** it with a new instruction, without hunting for the window.
3. **A better music presence**: a real, live spectrum of what Spotify plays, NotchNook-style.

## Goals

1. **Closed notch (270 wide):** artwork + 3 smooth spectrum bars left of the camera; the tightest plan-limit % right of it.
2. **Hover panel (440 wide) with tabs** in a floating pill under the panel: **Agents** and **Music** (and **Launcher**, see below). Opens on Agents while any session is live.
3. **Agents tab:** Claude 5-hour and weekly limits, Codex limits, Codex credits; live sessions with burn rate, multiple of normal, 30-minute burn graph, and a Stop button on a runaway Claude Code session.
4. **Runaway warning (360 wide):** drops down on its own; agent, project, first prompt, rate, total, duration. For Claude Code: **Stop** and **Redirect** (text field). Codex runs are flagged without buttons.
5. **Music tab:** NotchNook-like player (artwork, title, artist, 3-bar visualizer, progress, shuffle / prev / play / next / output).

## Non-goals

- Providers other than Claude Code and Codex (Cursor, OpenRouter, Gemini, API accounts). Later, if asked.
- Stopping or redirecting Codex runs. They are `codex exec` jobs started by the owner's Claude sessions; the notch only flags them (owner's choice).
- Spotify Web API or a Spotify login.
- Approving permission prompts from the notch (NotchNook's agent feature). Not asked for.
- Showing money ($). Subscriptions, not API billing.
- Cloud or remote sessions (claude.ai web, Codex cloud). Local sessions only.

## Anti-goals (a failure even if it works)

- The closed notch covering more menu bar than today (about 285).
- False alarms that teach the owner to ignore the warning.
- Slowing agents down: the hook adds well under 20 ms per tool call and **fails open** (notch not running, file missing, error → the agent runs normally).
- Disturbing the Claude Code login: the app only reads the token. It never refreshes, writes or copies it elsewhere.

## Approaches

### Look — decided in Waggle
Pixel/CRT cyberpunk, split (700 wide) and stacked layouts were tried and ruled out. Chosen: Hex-style black-and-white agents side, NotchNook music and tab pill, tabs, narrow widths. Full record: `docs/decisions/2026-11-20-notch-look.md`.

### Spectrum source
- **Core Audio process tap on the playing app (chosen).** macOS 14.2+ `AudioHardwareCreateProcessTap` on the process of the now-playing source (bundle id from MediaRemote → PID), into a private aggregate device, FFT with Accelerate, 3 bands. Real audio, any player, no account. Cost: one "system audio recording" permission prompt.
- Fake animation (today's `EqualizerBars`): rejected, the owner wants the real thing. Kept only as the fallback when permission is denied.
- Spotify Web API audio analysis: closed to new apps.

### Usage source
- **Sessions: local logs, no keys, no network (chosen).**
  - Claude Code: `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`, `message.usage` on assistant lines (`input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`).
  - Codex: `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`. `event_msg` / `token_count` carries `info.total_token_usage`, `info.last_token_usage` and `rate_limits` (`primary` / `secondary` with `used_percent`, `window_minutes`, `resets_at`; `credits.has_credits`, `balance`). Codex plan limits come from here.
- **Claude plan limits: the usage endpoint (owner's choice).** `GET https://api.anthropic.com/api/oauth/usage`, the numbers Claude Code's `/usage` shows. It uses the access token in the Keychain item `Claude Code-credentials`, read-only, after the owner allows Keychain access.
  - Fetch when a Claude transcript changes (at most once a minute) and when the panel opens. No timer.
  - Once a window's `resets_at` has passed, show 0% for it until the next fetch.
  - Expired token: do **not** refresh it, because a refresh rotates the token under Claude Code. Show the last values with their age until Claude Code refreshes the token itself.
- Rejected:
  - A status-line wrapper that copies the JSON Claude Code pipes to its status line. In the last 7 days, 58 of the owner's 59 Claude sessions ran in the Claude desktop app (`"entrypoint":"claude-desktop"`), which does not run the status line, so the limits would almost never update.
  - Estimating the % from token totals: the plan's size is unknown.

### Stop / Redirect
- **Claude Code: a `PreToolUse` command hook (chosen).** The app adds one hook entry to `~/.claude/settings.json`. On each tool call it reads `session_id` from stdin and checks for a directive file for that session. None → exit 0 at once. **Stop** → output that ends the turn (`continue: false` with a stop reason). **Redirect** → deny this tool call with the reason "The user redirected you: <text>", so Claude continues from the new instruction. The directive file is deleted once used. Takes effect at the next tool call; runaway sessions are tool loops, so that is seconds.
- **Codex: monitor only (owner's choice).** All 189 Codex rollouts of the last 7 days are `codex exec` runs (`originator: codex_exec`) started by Claude sessions, and a running exec takes no new message. Runaway Codex runs are flagged, with no Stop or Redirect.
- Rejected: signals to the agent process (can't redirect; desktop-app sessions share processes); typing into terminals via AppleScript (fragile).

## Design

### What "too much" means
- **Weighted tokens**, so the number tracks what eats the plan, not raw volume. Claude: `input×1 + cache_write×1.25 + cache_read×0.1 + output×5`. Codex: `uncached_input×1 + cached_input×0.1 + output×(its price ratio)`. One constant table in the kit per provider; the builder takes the ratios from current list prices.
- **Rate** = weighted tokens in the trailing 10 minutes ÷ 10, per session.
- **Normal** = median of per-session average rates over the last 30 days of the owner's own sessions, per agent, from the same logs. Recomputed at launch and daily. Until 10 past sessions exist, use a fixed default.
- **Runaway** when rate ≥ 3× normal for 2 consecutive minutes **and** the session has used ≥ 200k weighted tokens. Clears below 2×. After Stop, Redirect or dismiss, the same session is not re-flagged for 15 minutes unless its rate climbs 1.5× above the rate at dismissal.
- Threshold (3×) and window (10 min) are settings. Displayed "tok/min" is weighted.

### Session identity
- Agent (`CC` / `CX`), project = last path component of the session's cwd (Claude: `cwd` field on transcript lines; Codex: `session_meta`), first user prompt (truncated), start time, totals.
- "Live" = file written in the last 5 minutes.
- **My call:** sub-agent work rolls up into its parent: Claude `<session>/subagents/*.jsonl` into that session, Codex threads with a `parent_thread_id` into the parent thread. Rate and baseline count the parent with its children, so a fan-out of sub-agents that each look normal can still be flagged.

### Runaway strip behaviour (my call)
- The strip stays 30 s, then folds into the closed notch. The right side then shows the inverted multiple ("4.3×") in place of the plan %, for as long as the session stays runaway.
- While the cursor is on the strip, the strip stays and the hover panel does not open: the strip owns hover. Hovering a closed notch that shows the badge opens the Agents tab with that session on top and its Stop button.
- A small × on the strip is "dismiss": it starts the 15-minute cooldown and removes the badge. Folding after 30 s is not a dismiss: no cooldown, the badge stays.
- Stop and Redirect also close the strip. For a Codex run the strip has only the ×.
- Build it as a sticky event in the M3 event queue (no fixed duration) or as a new state-machine phase; builder's choice.

### Components
**OpenNotchKit (pure, test-first):**
- Line parsers for Claude transcript lines and Codex rollout lines, and a decoder for the Claude usage response → usage events and limit snapshots.
- `BurnRate` (trailing window), `Baseline` (median), `RunawayDetector` (threshold, hold time, floor, hysteresis, cooldown).
- `PlanLimits` + "tightest limit" pick for the closed notch.
- `SpectrumBands`: FFT magnitudes → 3 band levels (suggested 20–250 Hz, 250 Hz–2 kHz, 2–12 kHz) with attack/release smoothing.
- Directive file codec (session id, action, text, created at).

**OpenNotch (host, manual DoD):**
- `AgentWatcher`: FSEvents on the two log roots; tails only new bytes per file (stored offsets); feeds the kit.
- `ClaudeUsageClient`: reads the Keychain token (read-only), calls the usage endpoint on the triggers above, keeps the last good snapshot and its time.
- `HookInstaller`: installs/removes the Claude hook entry **only after the owner says yes in Settings**, idempotent, keeps other hooks untouched, backs up the file first. Writes directive files.
- `AudioTapService`: process tap for the now-playing app; follows source changes; stops when nothing plays.
- Shell: new widths; tabs + tab pill; the runaway strip (see its behaviour above) with buttons and a text field. The panel must become key while the Redirect field is open, then give focus back.
- Fonts: bundle Inter Variable (SIL OFL) and register it at launch; monospace = system monospaced.

**Plugin API additions:**
- `PluginHost.agents: AgentUsageService` (limits, sessions, runaway events, `stop(session:)`, `redirect(session:text:)` for Claude Code sessions).
- `PluginHost.spectrum: SpectrumService` (3 band levels, availability).
- A plugin can contribute a **tab** (id, title, SF Symbol, view). The pill lists tabs in plugin order.
- New first-party **AgentsPlugin** (Agents tab, closed-notch right side, runaway strip content). **MediaPlugin** moves to 3 bars from `spectrum` and gets the Music tab.
- **My call:** the app launcher becomes a third tab, **Launcher**, in the same pill (today's quick-actions column has no room at 440). It lists the quick actions of every plugin.
- **My call:** the API change is additive. `tabs()` defaults to none and the API version gets a minor bump (1.x), so existing `.notchplugin` bundles still load. Widgets from plugins that bring no tab go into a **Widgets** tab that holds today's M3 grid; the tab shows only when such widgets exist.

### Settings additions
Alert threshold (default 3×) and window (default 10 min); alerts on/off; **Integrations**: Claude plan usage (**my call:** a "Connect" button triggers the Keychain prompt, so it never appears by surprise), install/remove the Claude hook, each with its state; audio permission state with a "Grant" button.

### Degraded states
- Claude usage not connected, Keychain access denied, token expired or endpoint error → Claude limit rows show the last values with their age, or "—" with "Connect in Settings".
- Audio permission denied or tap fails → bars fall back to the decorative animation; Settings explains.
- Hook not installed → Stop/Redirect buttons hidden; the warning still shows, with "Install the hook in Settings to stop sessions from here".

## Risks — spike these first

1. **Process tap + ad-hoc signing.** The audio permission may reset on each rebuild (new code signature). Check it, and check the prompt appears for an `.accessory` app.
2. **Claude Code hook semantics.** Confirm against current docs: the stop output, the deny-with-reason output, and that sessions in the Claude desktop app run user hooks (this session's SessionStart hooks suggest yes).
3. **Claude usage endpoint.** It is unofficial. Confirm the URL, the headers it needs and the response shape (`five_hour`, `seven_day`, utilization, `resets_at`) with one live call. Confirm the Keychain item's JSON (access token, expiry). Keychain "Always allow" is tied to the code signature, so ad-hoc rebuilds may prompt again.
4. **Typing in the notch panel.** Today's panel is non-activating; the Redirect field needs key focus.

## Testing
- Kit, test-first: both log parsers and the usage-response decoder (fixtures from real lines, with paths and prompts anonymised), weighted-token math, baseline, detector (threshold, hold, floor, hysteresis, cooldown), sub-agent roll-up, tightest-limit pick, spectrum bands (synthetic sine input), directive codec.
- Hook script: a test that feeds stdin with and without a directive and checks output and run time.
- Manual DoD (README checklist): closed width on a 14-inch MacBook; bars follow the music; limits match Claude Code's `/usage` and Codex's `/status`; a forced runaway (low threshold) shows the strip and folds into the badge; Stop ends the turn; Redirect changes course; a Codex runaway shows no Stop or Redirect; hook removal restores settings; no Spotify → bars idle.

## Left to the builder
Exact price ratios; file-tail implementation; FFT size and band edges; spring constants; icons; how the 30-minute graph buckets data; the default "normal" before 10 sessions exist.
