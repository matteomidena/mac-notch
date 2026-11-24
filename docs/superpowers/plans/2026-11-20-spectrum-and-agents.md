# OpenNotch — Music spectrum + AI agents monitor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A narrower, tabbed notch that shows a live 3-bar spectrum of the playing app and a Claude Code + Codex monitor: plan limits, live sessions with burn rate, and a runaway warning with Stop/Redirect for Claude Code.

**Architecture:** Four spikes run first; each ends in a GO/NO-GO note, and later tasks name their fallback. Pure logic lives in `OpenNotchKit`, test-first: log parsing, token weighting, burn rate, baseline, runaway detection, usage decoding, spectrum bands, the hook script, settings patching and plugin tabs. OS work lives in `OpenNotch`, checked by the manual DoD: FSEvents tailing, Keychain + URLSession, settings.json IO, the Core Audio process tap, font registration, and the panel with its tabs and strip. The Agents and Music UIs are first-party plugins in the kit, built against two new host services (`agents`, `spectrum`).

**Tech Stack:** Swift 6 SPM, SwiftUI + AppKit, swift-testing (`@Test`/`#expect`), Accelerate (vDSP FFT), CoreAudio process taps (macOS 14.2+), CoreServices FSEvents, Security (Keychain), URLSession. No new package dependencies.

**Spec:** `docs/superpowers/specs/2026-11-20-spectrum-and-agents-design.md`. Decision records, quoted as **From:** in each task: `docs/decisions/2026-11-20-notch-look.md` (**L**) and `docs/decisions/2026-11-20-spectrum-agents-design.md` (**D**). Visual truth: `docs/superpowers/mockups/notch-look/index.html` (the mockup wins on look, the spec on behaviour).

## Global Constraints

- Platform floor macOS 14 (`.macOS(.v14)`), Swift tools 6.0. The process tap needs macOS 14.2: guard with `if #available(macOS 14.2, *)`, else use the decorative bars.
- No new package dependencies. Tests use `import Testing`, never XCTest.
- Pure logic in `Sources/OpenNotchKit`, test-first; AppKit/OS code in `Sources/OpenNotch`, manual DoD.
- Plugin-visible kit files import only SwiftUI/Foundation/Observation, never AppKit; add every new plugin-visible file to `PluginImportContractTests`.
- Event-driven. New timers allowed only for: the 30 s strip fold, the daily baseline recompute, the spectrum publish while audio plays. No polling of logs or of the usage endpoint.
- Widths: closed notch ≤ 285 (target 270); runaway strip ≤ 360; hover panel ≤ 440.
- Agents UI uses only `#070707`, `#F2F2EF`, `#9B9DA3`, `#B9BBC0` and ink at 7/10/14% for lines; no accent colours. Text is Inter; figures are the system monospaced font.
- Music visualizer: 3 bars, smooth, no jitter.
- Weighted tokens. Claude: `input×1 + cache_write×1.25 + cache_read×0.1 + output×5`. Codex: `uncached_input×1 + cached_input×0.1 + output×codexOutput`.
- Rate = weighted tokens in the trailing 10 minutes ÷ 10. Runaway when rate ≥ 3× normal for 2 consecutive minutes and session total ≥ 200k weighted. Clears below 2×. After Stop/Redirect/dismiss: no re-flag for 15 minutes unless rate ≥ 1.5× the rate at dismissal. Threshold (3×) and window (10 min) are settings.
- "Live" = file written in the last 5 minutes. Sub-agent work rolls up into its parent.
- The hook adds < 20 ms per tool call and fails open.
- The Claude Code token is only read: never refreshed, written or copied. The Keychain prompt appears only after the owner clicks "Connect". Usage is fetched when a Claude transcript changes (at most once a minute) and when the panel opens.
- Stop and Redirect exist for Claude Code only. Codex runs are flagged with no buttons.
- Plugin API change is additive: `OPENNOTCH_API_VERSION = "1.1.0"`; new `PluginHost` requirements are appended at the end of the protocol; tabs come through a separate protocol.
- Run `swift test` (baseline: 85 passing), `swift build`, `swift run OpenNotch`; package with `Scripts/make-app.sh`.
- Commits: `feat(kit):`, `feat:`, `fix:`, `docs:`, `test:`; trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Commit after every task.

## Review Focus

1. **Claude writes one transcript line per content block, all with the same `message.id` and the same usage.** Counting per line double-counts. Expected: usage counted once per message id (test in Task 9).
2. **A file event fires while a line is half written.** Expected: the fragment waits for its newline; no line is lost or parsed twice (test in Task 6, `LineSplitter`).
3. **A hostile or odd `session_id` in hook stdin (`../../x`, empty, spaces).** Expected: the hook prints nothing and exits 0 (test in Task 11).
4. **`~/.claude/settings.json` is missing, empty or not valid JSON.** Expected: missing → created; invalid → install refuses and the file is untouched; a backup is written before any change (test in Task 11; host check in Task 21).
5. **A third-party `.notchplugin` built against API 1.0.0.** Expected: it still loads and its widgets show in the Widgets tab (test in Task 13).

---

## Phase 0 — Spikes (each ends in `docs/superpowers/spikes/2026-11-20-<name>.md`, GO/NO-GO)

### Task 1: Spike — Claude usage endpoint and Keychain item

**From:** D, Open questions: "Four spikes come first in the plan: audio tap with ad-hoc signing, Claude hook output, the usage endpoint, key focus in the notch panel."

**Files:** Create `docs/superpowers/spikes/2026-11-20-usage-endpoint.md`.

**Acceptance criteria:**
- The note gives the exact URL, the headers it needs, and the response JSON shape (field names, units, one anonymised example) → feeds Task 8's fixture.
- The note gives the Keychain item's JSON key names and the unit of the expiry field. No token value appears in the note, the repo or the terminal output.
- GO/NO-GO stated. NO-GO fallback: Claude limit rows show "—"; Codex limits still work; tell the owner before Task 20.

- [ ] **Step 1:** Ask the owner in chat before reading the token: this spike reads their Claude Code login and makes one API call with it. Stop here without a clear yes.
- [ ] **Step 2:** Print key names only: `security find-generic-password -s "Claude Code-credentials" -w | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(sorted(d)); print({k: type(v).__name__ for k,v in d.get("claudeAiOauth",{}).items()})'`
- [ ] **Step 3:** One call, token held in a shell variable, never echoed: `GET https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer <token>` and `anthropic-beta: oauth-2025-04-20`. Record status and body shape. If the headers are wrong, try what the response asks for, at most 3 calls.
- [ ] **Step 4:** Write the note and commit: `docs: spike the Claude usage endpoint`.

### Task 2: Spike — Claude Code hook outputs (CLI and desktop app)

**From:** D, Constraints: "Stop and Redirect exist for Claude Code sessions only, through a `PreToolUse` hook that fails open."

**Files:** Create `docs/superpowers/spikes/2026-11-20-claude-hook.md`. Work in a throwaway folder in the scratchpad with a **project-level** `.claude/settings.json`; never edit `~/.claude/settings.json` in this spike.

**Acceptance criteria:**
- For the CLI (`claude -p`) and for a desktop-app session opened on the throwaway folder, the note records:
  - Deny: `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"The user redirected you: say hello and stop"}}` makes the model follow the new text.
  - Stop: `{"continue":false,"stopReason":"Stopped from OpenNotch"}` ends the turn.
- The note records the stdin field names, and whether a sub-agent's tool call carries the parent `session_id`.
- The note records the median run time of `sh hook.sh < sample.json` with no directive file, over 20 runs (< 20 ms).
- If desktop sessions ignore user hooks: NO-GO for desktop. Stop and tell the owner before Task 21.

- [ ] **Step 1:** Write the two outputs as fixed-output hook scripts, run each case, record results.
- [ ] **Step 2:** Write the note and commit: `docs: spike Claude Code hook outputs`.

### Task 3: Spike — process tap under ad-hoc signing

**From:** D, Open questions: "…audio tap with ad-hoc signing…"

**Files:** Create `spike/process-tap/main.swift` (throwaway), `docs/superpowers/spikes/2026-11-20-process-tap.md`.

**Acceptance criteria:**
- A tiny `LSUIElement` app with `NSAudioCaptureUsageDescription`, ad-hoc signed, taps Spotify:
  1. Translate the PID to a process object (`kAudioHardwarePropertyTranslatePIDToProcessObject`).
  2. Create the tap: `CATapDescription(stereoMixdownOfProcesses:)` + `AudioHardwareCreateProcessTap`.
  3. Build a private aggregate device with the tap and add an IOProc.
- It prints RMS > 0 while music plays.
- The note records: whether the prompt appears; the System Settings entry it creates; whether permission survives a rebuild + re-sign; IOProc CPU (< 3%); the exact calls that worked.
- NO-GO fallback: decorative 3 bars (Task 15) and Settings explains.

- [ ] **Step 1:** Build, run, record. **Step 2:** Write the note, commit: `docs: spike the process tap`.

### Task 4: Spike — typing in the notch panel

**From:** D, Open questions: "…key focus in the notch panel."

**Files:** Temporary edits to `Sources/OpenNotch/NotchWindow.swift` (reverted); create `docs/superpowers/spikes/2026-11-20-panel-focus.md`.

**Acceptance criteria:**
- Recipe recorded: `canBecomeKey` returns a flag that is true only while a text field is open; `makeKey()` on the `.nonactivatingPanel`.
- Typing works while another app stays frontmost.
- After the field closes, that app gets keystrokes without a click.
- Spike code reverted; only the note is committed (`docs: spike panel focus`).

---

## Phase 1 — Kit: agents data (test-first)

### Task 5: Agent model, token weights, tightest limit

**From:** L, Question and choice: "the tightest plan-limit percentage right of it, with a hairline fill."

**Files:** Create `Sources/OpenNotchKit/AgentModel.swift`, `Tests/OpenNotchKitTests/AgentModelTests.swift`.

**Interfaces — Produces:**
```swift
public enum AgentKind: String, Sendable, Codable, CaseIterable { case claude = "CC", codex = "CX" }
public struct TokenCounts: Equatable, Sendable {          // Codex: input = uncached, cacheRead = cached
    public var input, cacheWrite, cacheRead, output: Int
    public init(input: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0, output: Int = 0)
    public static func + (a: Self, b: Self) -> Self
}
public enum TokenWeights {
    public static let codexOutput: Double = 8  // ponytail: list price out÷in for Codex's default model; update with prices
    public static func weighted(_ t: TokenCounts, agent: AgentKind) -> Double
}
public struct LimitWindow: Equatable, Sendable {
    public let label: String; public let usedPercent: Double; public let resetsAt: Date?
    public func percent(at now: Date) -> Double            // 0 once resetsAt has passed
}
public struct PlanLimits: Equatable, Sendable {
    public let agent: AgentKind; public let windows: [LimitWindow]
    public let hasCredits: Bool?; public let fetchedAt: Date
}
public struct TightestLimit: Equatable { public let agent: AgentKind; public let window: LimitWindow }
public func tightestLimit(_ all: [PlanLimits], at now: Date) -> TightestLimit?
public func windowLabel(minutes: Int) -> String           // 300 → "5h", 10080 → "Weekly", else "\(minutes/60)h"
```

- [ ] **Step 1: Write the failing tests**
```swift
@Test func claudeWeightsMatchSpec() {
    let t = TokenCounts(input: 100, cacheWrite: 1000, cacheRead: 10_000, output: 10)
    #expect(TokenWeights.weighted(t, agent: .claude) == 100 + 1250 + 1000 + 50)
}
@Test func codexCachedInputAtOneTenth() {
    let t = TokenCounts(input: 1000, cacheRead: 10_000, output: 10)
    #expect(TokenWeights.weighted(t, agent: .codex) == 1000 + 1000 + 10 * TokenWeights.codexOutput)
}
@Test func windowPercentIsZeroAfterReset() {
    let w = LimitWindow(label: "5h", usedPercent: 62, resetsAt: Date(timeIntervalSince1970: 1000))
    #expect(w.percent(at: Date(timeIntervalSince1970: 999)) == 62)
    #expect(w.percent(at: Date(timeIntervalSince1970: 1000)) == 0)
}
@Test func tightestPicksHighestPercentAcrossAgents() {
    let now = Date(timeIntervalSince1970: 0)
    let cc = PlanLimits(agent: .claude, windows: [LimitWindow(label: "5h", usedPercent: 62, resetsAt: nil),
                                                  LimitWindow(label: "Weekly", usedPercent: 40, resetsAt: nil)],
                        hasCredits: nil, fetchedAt: now)
    let cx = PlanLimits(agent: .codex, windows: [LimitWindow(label: "Weekly", usedPercent: 7, resetsAt: nil)],
                        hasCredits: true, fetchedAt: now)
    #expect(tightestLimit([cx, cc], at: now) == TightestLimit(agent: .claude, window: cc.windows[0]))
    #expect(tightestLimit([], at: now) == nil)
}
@Test func windowLabels() {
    #expect(windowLabel(minutes: 300) == "5h"); #expect(windowLabel(minutes: 10080) == "Weekly")
}
```
- [ ] **Step 2:** `swift test --filter AgentModelTests` → FAIL (types missing).
- [ ] **Step 3:** Implement the interfaces above in `AgentModel.swift`.
- [ ] **Step 4:** `swift test --filter AgentModelTests` → PASS.
- [ ] **Step 5:** Commit `feat(kit): agent model and token weights`.

### Task 6: Line splitter and Claude transcript parser

**From:** D, Question and choice: approved design, § Usage source ("Claude Code: `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`, `message.usage` on assistant lines").

**Files:** Create `Sources/OpenNotchKit/LineSplitter.swift`, `Sources/OpenNotchKit/ClaudeLogParser.swift`, `Tests/OpenNotchKitTests/ClaudeLogParserTests.swift`, `Tests/OpenNotchKitTests/Fixtures/claude-transcript.jsonl`.

The fixture holds 6 lines copied from real transcripts with paths, prompts and ids replaced:
1. A user prompt with string content.
2. An assistant line with usage and `message.id: "msg_1"`.
3. A second assistant line with the same `msg_1` and the same usage.
4. A user line whose content is a `tool_result`.
5. A user line with `isMeta: true`.
6. A `summary` line.

**Interfaces — Produces:**
```swift
public struct LineSplitter { public init(); public mutating func feed(_ data: Data) -> [String] }  // complete lines only; keeps the fragment
public enum TokenReport: Equatable, Sendable { case delta(TokenCounts, messageId: String?), cumulative(TokenCounts) }
public struct ParsedLogLine: Equatable, Sendable {
    public var at: Date?; public var tokens: TokenReport?; public var cwd: String?; public var userPrompt: String?
    public var threadId: String?; public var parentThreadId: String?; public var limits: PlanLimits?   // Codex only
    public init(...)  // memberwise, all defaulted to nil
}
public enum ClaudeLogParser {
    public static func parse(_ line: String) -> ParsedLogLine?
    /// `…/<enc-cwd>/<uuid>.jsonl` → (uuid, nil); `…/<enc-cwd>/<uuid>/subagents/<name>.jsonl` → (name, uuid); else nil
    public static func sessionIds(path: String) -> (session: String, parent: String?)?
}
```

- [ ] **Step 1: Write the failing tests**
  - `splitterKeepsPartialLine`: `feed("a\nb")` → `["a"]`, then `feed("c\n")` → `["bc"]`.
  - `parsesAssistantUsage`: fixture line 2 → `tokens == .delta(TokenCounts(input: 2, cacheWrite: 1073, cacheRead: 202787, output: 24), messageId: "msg_1")`; `cwd` set; `at` equals the ISO-8601 `timestamp` (fractional seconds).
  - `userPromptOnlyFromRealPrompts`: line 1 → prompt text; lines 4 and 5 → `userPrompt == nil`; a content array `[{type:"text",text:"hi"}]` → `"hi"`.
  - `malformedLineIsNil`: `parse("{not json")` → nil.
  - `sessionIdsFromPath`: both path shapes above; `"/x/notes.txt"` → nil.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement (`JSONSerialization`, `ISO8601DateFormatter` with `.withFractionalSeconds`). **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(kit): Claude transcript parser`.

### Task 7: Codex rollout parser

**From:** D, Question and choice: "Codex Stop and Redirect: "Monitor only". Codex runs are flagged…"

**Files:** Create `Sources/OpenNotchKit/CodexLogParser.swift`, `Tests/OpenNotchKitTests/CodexLogParserTests.swift`, `Tests/OpenNotchKitTests/Fixtures/codex-rollout.jsonl`.

The fixture holds lines copied from real rollouts and anonymised:
1. `session_meta` for a top-level run.
2. `session_meta` for a sub-agent, with `parent_thread_id`.
3. `token_count` with `info` and `rate_limits`.
4. `token_count` with `info: null`.
5. The first user prompt line as Codex writes it. Find it with `grep -m1 '"user_message"'`; if exec runs have none, use the first `response_item` with `role: "user"` that is not an instructions block.

**Interfaces — Produces:** `public enum CodexLogParser { public static func parse(_ line: String) -> ParsedLogLine? }`

- [ ] **Step 1: Write the failing tests**
  - `sessionMetaIds`: line 1 → `threadId == payload.id`, `parentThreadId == nil`, `cwd` set; line 2 → `parentThreadId` set.
  - `tokenCountIsCumulativeAndUncached`: `total_token_usage {input_tokens: 32161, cached_input_tokens: 19584, output_tokens: 203}` → `.cumulative(TokenCounts(input: 12577, cacheRead: 19584, output: 203))`.
  - `rateLimitsBecomePlanLimits`: `primary {used_percent: 7.0, window_minutes: 10080, resets_at: 1795628010}`, `secondary: null`, `credits.has_credits: true` → `PlanLimits(agent: .codex, windows: [LimitWindow(label: "Weekly", usedPercent: 7, resetsAt: Date(timeIntervalSince1970: 1795628010))], hasCredits: true, fetchedAt: <line timestamp>)`.
  - `nullInfoStillGivesLimits`: line 4 → `tokens == nil`, `limits != nil`.
  - `firstUserPrompt`: line 5 → its text.
- [ ] **Step 2:** FAIL. **Step 3:** Implement. **Step 4:** PASS. **Step 5:** Commit `feat(kit): Codex rollout parser`.

### Task 8: Claude usage decoder and credential reader

**From:** D, Question and choice: "Claude 5-hour and weekly %: "Usage endpoint". The app reads the numbers `/usage` shows, with the Claude Code login token in the Keychain."

**Files:** Create `Sources/OpenNotchKit/ClaudeUsage.swift`, `Tests/OpenNotchKitTests/ClaudeUsageTests.swift`, `Tests/OpenNotchKitTests/Fixtures/claude-usage.json` (shape from Task 1's note, numbers kept, ids removed).

**Interfaces — Produces:**
```swift
public enum ClaudeUsageDecoder { public static func decode(_ data: Data, at now: Date) -> PlanLimits? }
public struct ClaudeCredential: Equatable, Sendable {
    public let accessToken: String; public let expiresAt: Date
    public static func parse(keychainJSON: Data) -> ClaudeCredential?     // claudeAiOauth.accessToken / expiresAt (unit per Task 1)
    public func isExpired(at now: Date) -> Bool
}
```

- [ ] **Step 1: Write the failing tests**
  - `decodesFiveHourAndWeekly`: fixture → windows labelled `"5h"` and `"Weekly"`, with the fixture's percent and reset dates; `agent == .claude`.
  - `nullWindowsSkipped`: a `null` window (e.g. `seven_day_opus`) is not in `windows`.
  - `garbageIsNil`: `decode(Data("x".utf8), at:)` → nil.
  - `credentialParsesAndExpires`: a JSON with a fake token and an expiry 1 h after `t0` → `isExpired(at: t0) == false`, `isExpired(at: t0 + 3601) == true`.
- [ ] **Step 2–4:** FAIL → implement → PASS. **Step 5:** Commit `feat(kit): Claude usage decoder`.

### Task 9: Session store — ingest, dedupe, roll-up, burn rate

**From:** D, Constraints: "Sub-agent work counts with its parent session for rate and baseline."

**Files:** Create `Sources/OpenNotchKit/AgentSessions.swift`, `Tests/OpenNotchKitTests/AgentSessionsTests.swift`.

**Interfaces — Consumes:** Tasks 5–7. **Produces:**
```swift
public struct BurnRate: Equatable, Sendable {
    public init(window: TimeInterval = 600, keep: TimeInterval = 1800)
    public mutating func add(_ weighted: Double, at: Date)
    public func perMinute(at now: Date) -> Double                      // sum in (now − window, now] ÷ (window / 60)
    public func history(at now: Date, minutes: Int = 30) -> [Double]   // per-minute sums, oldest first
}
public struct AgentSession: Identifiable, Equatable, Sendable {
    public let id: String                 // roll-up key: parent id, else own id
    public let agent: AgentKind
    public var project: String            // last path component of cwd
    public var firstPrompt: String?       // first one seen, max 120 characters
    public var startedAt: Date; public var lastActivity: Date
    public var totals: TokenCounts; public var weightedTotal: Double
    public var burn: BurnRate
    public var activeMinutes: Int         // distinct minutes with usage
    public func isLive(at now: Date) -> Bool                           // lastActivity within 300 s
}
@MainActor public final class AgentSessions {
    public init()
    public func ingest(_ line: ParsedLogLine, agent: AgentKind, fileKey: String,
                       pathIds: (session: String, parent: String?)?)  // Claude: from the path; Codex: nil (uses session_meta)
    public private(set) var sessions: [String: AgentSession]
    public private(set) var latestLimits: [AgentKind: PlanLimits]      // newest fetchedAt wins
    public func live(at now: Date) -> [AgentSession]                   // sorted by perMinute, highest first
}
```
Rules:
- Claude deltas are deduped by `messageId` per `fileKey`.
- Codex cumulative totals are differenced per `fileKey`: `delta = max(0, new − previous)` per field. A drop (restart) counts 0.
- Codex lines before that file's `session_meta` are ignored.

- [ ] **Step 1: Write the failing tests**
  - `repeatedMessageIdCountsOnce`: two `.delta(t, messageId: "m1")` lines → `totals == t`.
  - `claudeSubagentRollsUpIntoParent`: a line with `pathIds: ("agent-a", "P")` → added to `sessions["P"]`.
  - `codexSubagentRollsUpIntoParent`: a `session_meta` with `parentThreadId: "P"`, then a cumulative line → added to `sessions["P"]`.
  - `codexCumulativeIsDifferenced`: cumulative input 100, then 250, then 50 → totals input 250.
  - `burnRateTrailingWindow`: add 6000 at `t0` and 6000 at `t0+300` → `perMinute(at: t0+300) == 1200`; `perMinute(at: t0+700) == 600`.
  - `historyHasThirtyBuckets`: `history(at:).count == 30`.
  - `liveWithinFiveMinutes`: `isLive(at: last+299) == true`, `isLive(at: last+301) == false`.
  - `projectAndFirstPrompt`: cwd `/a/b/mac-notch` → `"mac-notch"`; a second prompt does not replace the first; a 200-character prompt is cut to 120.
  - `newestLimitsWin`: older `fetchedAt` does not replace newer.
- [ ] **Step 2–4:** FAIL → implement → PASS. **Step 5:** Commit `feat(kit): agent session store and burn rate`.

### Task 10: Baseline and runaway detector

**From:** D, Constraints: "The runaway strip stays 30 s, then folds into a "4.3×" badge. The × dismisses it and starts the 15-minute cooldown." and spec § What "too much" means.

**Files:** Create `Sources/OpenNotchKit/RunawayDetector.swift`, `Tests/OpenNotchKitTests/RunawayDetectorTests.swift`.

**Interfaces — Produces:**
```swift
public enum Baseline {
    public static let minSessions = 10
    public static let defaultNormal: [AgentKind: Double] = [.claude: 30_000, .codex: 15_000]  // ponytail: guess until 10 sessions exist
    /// Average over ACTIVE minutes, not wall time: an idle hour would make every burst look abnormal.
    public static func averageRate(weightedTotal: Double, activeMinutes: Int) -> Double   // ÷ max(1, activeMinutes)
    public static func normal(averages: [Double], agent: AgentKind) -> Double             // median if ≥ 10, else default
}
public struct RunawayConfig: Equatable, Sendable {
    public var threshold = 3.0, clearBelow = 2.0, hold: TimeInterval = 120
    public var floor = 200_000.0, cooldown: TimeInterval = 900, reflag = 1.5
    public init()
}
public enum RunawayChange: Equatable { case flagged(sessionId: String, multiple: Double), cleared(sessionId: String) }
public struct RunawayDetector {
    public init(config: RunawayConfig = .init())
    public var config: RunawayConfig
    public mutating func update(sessionId: String, rate: Double, weightedTotal: Double,
                                normal: Double, at now: Date) -> RunawayChange?
    public mutating func acknowledge(sessionId: String, rate: Double, at now: Date)   // Stop, Redirect or ×
    public func isFlagged(_ sessionId: String) -> Bool
}
```

- [ ] **Step 1: Write the failing tests** (normal = 10_000 unless stated)
  - `flagsOnlyAfterHold`: rate 31_000, total 300_000 at `t0`, `t0+60` → nil; at `t0+120` → `.flagged(sessionId: "s", multiple: 3.1)`.
  - `floorBlocksSmallSessions`: rate 50_000, total 150_000, for 10 min → never flagged.
  - `dipRestartsHold`: above at `t0`, 25_000 at `t0+60`, above from `t0+90` → nil at `t0+180`, flagged at `t0+210`.
  - `hysteresis`: once flagged, 25_000 → nil (still flagged); 19_000 → `.cleared`.
  - `cooldownAfterAcknowledge`: flagged, `acknowledge(rate: 31_000)`; 31_000 for 10 min → nil; 47_000 held 2 min → flagged again (≥ 1.5 × 31_000).
  - `cooldownExpires`: after ack, 31_000 from `ack+900` held 2 min → flagged.
  - `normalUsesMedianFromTenSessions`: `normal(averages: [1…10], agent: .claude) == 5.5`; nine values → `defaultNormal[.claude]`.
  - `averageOverActiveMinutes`: `averageRate(weightedTotal: 600_000, activeMinutes: 20) == 30_000`; `activeMinutes: 0` → 600_000.
- [ ] **Step 2–4:** FAIL → implement → PASS. **Step 5:** Commit `feat(kit): baseline and runaway detector`.

### Task 11: Directives, hook script, Claude settings patch

**From:** D, Constraints: "Stop and Redirect exist for Claude Code sessions only, through a `PreToolUse` hook that fails open."

**Files:** Create `Sources/OpenNotchKit/Directive.swift`, `Sources/OpenNotchKit/ClaudeSettingsPatch.swift`, `Tests/OpenNotchKitTests/HookScriptTests.swift`, `Tests/OpenNotchKitTests/ClaudeSettingsPatchTests.swift`.

**Interfaces — Produces:**
```swift
public enum DirectiveAction: Equatable, Sendable { case stop, redirect(String) }
public enum Directive {
    public static func hookOutput(_ action: DirectiveAction) -> Data   // exact JSON confirmed in Task 2
    public static func isSafeSessionId(_ id: String) -> Bool             // ^[A-Za-z0-9-]{1,64}$
    public static let hookScript: String                                 // the POSIX sh below, verbatim
}
public enum ClaudeSettingsPatch {
    public enum PatchError: Error, Equatable { case notAJSONObject }
    public static func install(into settings: Data?, command: String) throws -> Data   // nil = file missing
    public static func remove(from settings: Data, command: String) throws -> Data
    public static func isInstalled(in settings: Data?, command: String) -> Bool
}
```
Hook outputs (adjust only if Task 2 says otherwise): stop → `{"continue":false,"stopReason":"Stopped from OpenNotch"}`; redirect → `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"The user redirected you: <text>"}}`.

Hook script (security-relevant, exact):
```sh
#!/bin/sh
# OpenNotch PreToolUse hook. Fails open: on any problem it exits 0 and the tool runs.
dir="$HOME/Library/Application Support/OpenNotch/directives"
id=$(sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([A-Za-z0-9-]*\)".*/\1/p' | head -n 1)
[ -n "$id" ] || exit 0
f="$dir/$id.json"
[ -f "$f" ] || exit 0
# A directive older than 2 minutes is stale (the session went quiet): drop it.
[ -n "$(find "$f" -mmin -2 2>/dev/null)" ] || { rm -f "$f"; exit 0; }
cat "$f" 2>/dev/null
rm -f "$f"
exit 0
```
Installed entry shape: `{"hooks":{"PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":<command>}]}]}}`. The host passes the script path in double quotes (it contains a space).

- [ ] **Step 1: Write the failing tests.** The script tests write `Directive.hookScript` to a temp folder and run `/bin/sh` with `HOME` set to a temp folder and JSON on stdin.
  - `noDirectivePrintsNothing`: stdout empty, exit 0.
  - `directivePrintedOnceThenDeleted`: write `hookOutput(.stop)` to `<HOME>/Library/Application Support/OpenNotch/directives/abc-1.json`; first run prints it; second run prints nothing.
  - `hostileSessionIdIgnored`: `session_id` `"../../etc/x"`, `""` and `"a b"` → stdout empty, exit 0.
  - `staleDirectiveDropped`: modification date 3 minutes ago → stdout empty and the file is gone.
  - `runsUnder20ms`: median of 20 runs with no directive < 0.020 s.
  - `installIntoMissingFile`: `install(into: nil, command: C)` → exactly the entry shape above.
  - `installKeepsEverythingElse`: input with `statusLine`, a `PreToolUse` entry with `matcher: "Bash"`, and a `PostToolUse` hook → all kept, ours appended.
  - `installIsIdempotent`: install twice → one entry with `C`.
  - `removeOnlyOurs`: after remove, the `Bash` entry and `PostToolUse` remain; `isInstalled == false`.
  - `invalidJSONThrows`: `install(into: Data("not json".utf8), …)` throws `.notAJSONObject`; so does `Data("[]".utf8)`.
- [ ] **Step 2–4:** FAIL → implement → PASS. **Step 5:** Commit `feat(kit): stop/redirect directives and hook script`.

---

## Phase 2 — Kit: spectrum

### Task 12: Spectrum analyzer and 3 bands

**From:** L, Constraints: "Music visualizer: 3 bars, smooth, no jitter."

**Files:** Create `Sources/OpenNotchKit/Spectrum.swift` (imports Accelerate), `Tests/OpenNotchKitTests/SpectrumTests.swift`.

**Interfaces — Produces:**
```swift
public struct SpectrumAnalyzer {
    public init(fftSize: Int = 2048)                        // power of two
    public func magnitudes(_ samples: [Float]) -> [Float]   // fftSize/2 bins, Hann window, vDSP real FFT
}
public struct SpectrumBands {
    public static let defaultEdges: [ClosedRange<Double>] = [20...250, 250...2000, 2000...12000]
    public init(sampleRate: Double, fftSize: Int, edges: [ClosedRange<Double>] = defaultEdges,
                attack: Double = 0.5, release: Double = 0.08)
    public private(set) var levels: [Double]                // 0...1, one per edge
    public mutating func update(magnitudes: [Float]) -> [Double]
}
```
Band energy → dB → map −60…0 dB to 0…1 (curve is the builder's). Smoothing: `level += (target − level) × (target > level ? attack : release)`.

- [ ] **Step 1: Write the failing tests** (48 kHz, 2048 samples, 10 updates each)
  - `lowSineLightsFirstBand`: 100 Hz sine → `levels[0] > 0.5`, and `levels[0] > 3 × levels[1]` and `> 3 × levels[2]`.
  - `highSineLightsThirdBand`: 5 kHz sine → `levels[2]` is the largest.
  - `silenceDecaysSmoothly`: after a loud input, each silent update lowers every level by at most 8% of its value (no jump to 0).
  - `levelsStayInRange`: full-scale white noise → all levels in 0...1.
- [ ] **Step 2–4:** FAIL → implement → PASS. **Step 5:** Commit `feat(kit): spectrum bands`.

---

## Phase 3 — Kit: plugin API 1.1 and plugins

### Task 13: Plugin API 1.1 — tabs and the two services

**From:** D, Constraints: "The plugin API change is additive (minor bump). Existing `.notchplugin` bundles still load."

**Files:**
- Modify: `Sources/OpenNotchKit/PluginAPI.swift`, `APIVersion.swift` (`"1.1.0"`), `PluginRuntime.swift`.
- Create: `Sources/OpenNotchKit/HostServices.swift`, `Sources/OpenNotchKit/TabBar.swift`, `Tests/OpenNotchKitTests/TabBarTests.swift`.
- Modify: `Tests/OpenNotchKitTests/PluginRuntimeTests.swift`, `PluginLoaderTests.swift`, `PluginImportContractTests.swift` (add `HostServices.swift`, `TabBar.swift`, `AgentModel.swift`, `AgentSessions.swift`).

**Interfaces — Consumes:** Tasks 5, 9, 10. **Produces:**
```swift
public struct PluginTab: Identifiable { public let id, title, systemImage: String; public let content: AnyView }
@MainActor public protocol NotchTabProvider { func tabs() -> [PluginTab] }   // separate: 1.0 bundles never get asked
public struct RunawayAlert: Equatable, Sendable { public let session: AgentSession; public let multiple: Double; public let normal: Double }
@MainActor public protocol AgentUsageService: AnyObject, Observable {
    var limits: [PlanLimits] { get }; var liveSessions: [AgentSession] { get }
    var normalRate: [AgentKind: Double] { get }; var alert: RunawayAlert? { get }
    var canControl: Bool { get }          // Claude hook installed
    func stop(sessionId: String); func redirect(sessionId: String, text: String)
    func dismiss(sessionId: String); func refreshLimits()
}
@MainActor public protocol SpectrumService: AnyObject, Observable { var levels: [Double] { get }; var isAvailable: Bool { get } }
// PluginHost — appended at the END (keeps 1.0 witness-table offsets), with defaults returning
// `NoAgents.shared` / `NoSpectrum.shared` (empty @Observable stubs) so FakeHost still compiles:
var agents: AgentUsageService { get }
var spectrum: SpectrumService { get }
// NowPlayingService — appended: func toggleShuffle()   (default no-op; adapter `send 6`)
public struct TabItem: Equatable { public let id, title, systemImage: String }
public enum TabBar {
    public static func items(providerTabs: [TabItem], hasWidgets: Bool, hasQuickActions: Bool) -> [TabItem]
    public static func defaultTab(_ items: [TabItem], hasLiveSession: Bool, isPlaying: Bool) -> String?
}
// PluginRuntime: `tabs: [PluginTab]` (providers, in plugin order); `widgets` now only from non-provider plugins.
```
Synthetic tabs appended by `TabBar.items`, in this order:
- `("widgets", "Widgets", "square.grid.2x2")` when `hasWidgets`.
- `("launcher", "Launcher", "square.grid.3x3.fill")` when `hasQuickActions`.

`defaultTab`: `"agents"` if a session is live, else `"music"` if playing, else the first item.

- [ ] **Step 1: Write the failing tests**
  - `TabBarTests.itemsOrder`: providers `[agents, music]`, widgets true, quick actions true → ids `["agents","music","widgets","launcher"]`; both false → `["agents","music"]`.
  - `TabBarTests.defaultTab`: live → `"agents"`; not live + playing → `"music"`; neither → first id; no items → nil.
  - `PluginRuntimeTests.providerTabsAndWidgetSplit`: a `NotchTabProvider` stub with one tab and one widget, plus `StubPlugin` → `runtime.tabs.map(\.id) == ["t"]`; `runtime.widgets` holds only `StubPlugin`'s widgets.
  - `PluginLoaderTests`: the existing 1.0.0 fixture loads under host 1.1.0, and its widgets appear in `runtime.widgets`.
  - `APIVersionTests`: `apiCompatibility(host: "1.1.0", plugin: "1.0.0") == .compatible`.
- [ ] **Step 2–4:** FAIL → implement → PASS (`swift test`, all suites). **Step 5:** Commit `feat(kit): plugin API 1.1 with tabs and host services`.

### Task 14: State machine — alert phase

**From:** L, Question and choice: "Runaway warning, 360 wide, drops down on its own".

**Files:** Modify `Sources/OpenNotchKit/NotchState.swift`, `NotchFootprint.swift`; tests in `NotchStateTests.swift`, `NotchFootprintTests.swift`.

**Interfaces — Produces:** `NotchPhase.alert`; `NotchEvent.alertRaised`, `.alertFolded`, `.alertClosed`; `NotchFootprint.size(phase:showAmbient:notchSize:ambientSize:expandedSize:alertSize:)`.

- [ ] **Step 1: Write the failing tests** (`handle` results)
  - `collapsed + alertRaised → alert`; `expanded/pinned + alertRaised → unchanged`; `hidden + alertRaised → hidden`.
  - `alert + hoverIn → alert`, `alert + hoverOut → alert`, `alert + click → alert`, `alert + clickOutside → alert` (the strip owns hover and clicks).
  - `alert + alertFolded / alertClosed / escape → collapsed`; `alert + enterFullscreen → hidden`.
  - Footprint: `.alert` → `alertSize`.
- [ ] **Step 2–4:** FAIL → implement → PASS. **Step 5:** Commit `feat(kit): alert phase for the runaway strip`.

### Task 15: Hex style, 3-bar visualizer, MediaPlugin Music tab

**From:** L, Question and choice: "Closed notch, 270 wide: artwork + 3 smooth spectrum bars left of the camera…" and "Music side and the tab pill follow NotchNook."

**Files:** Create `Sources/OpenNotchKit/HexStyle.swift`; modify `MediaPlugin.swift`, `NowPlayingView.swift`, `Tests/OpenNotchKitTests/MediaPluginTests.swift`; add `HexStyle.swift` to the import contract test.

**Interfaces — Produces:**
```swift
public enum Hex {
    public static let bg, ink, muted, code: Color                  // #070707, #F2F2EF, #9B9DA3, #B9BBC0
    public static func line(_ opacity: Double) -> Color            // ink at .07 / .10 / .14
    public static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font   // .custom("Inter", size:)
    public static func mono(_ size: CGFloat) -> Font               // .system(size:, design: .monospaced)
}
public struct SpectrumBars: View { public init(levels: [Double], isPlaying: Bool, height: CGFloat) }  // 3 capsules
```
Behaviour:
- `MediaPlugin` conforms to `NotchTabProvider`. `tabs()` returns `[PluginTab(id: "music", title: "Music", systemImage: "music.note", …)]`.
- `widgets()` returns `[]`. `compactLeading()` returns artwork 18 pt + `SpectrumBars(height: 13)`. `compactTrailing()` returns nil.
- When `host.spectrum.isAvailable == false`, the bars fall back to today's `EqualizerBars` cut to 3 bars, slowed and low-pass smoothed as in the mockup's JS (`v += (target − v) × 0.08`).
- The Music tab follows the mockup: art 52, title, artist, 3-bar viz, progress, shuffle / prev / play / next / output.
  - Shuffle → `toggleShuffle()`.
  - Output → `@Environment(\.openURL)` with `x-apple.systempreferences:com.apple.Sound-Settings.extension` (ponytail: no public route-picker API for SwiftUI).

- [ ] **Step 1: Update the tests:** `mediaPluginProvidesMusicTab` (`tabs().map(\.id) == ["music"]`, `widgets().isEmpty`, `compactTrailing() == nil`); `shuffleCallsService` (`host.np.calls` contains `"toggleShuffle"`).
- [ ] **Step 2–4:** FAIL → implement (`MediaRemoteBridge.toggleShuffle()` = `send(6)`) → PASS. **Step 5:** Commit `feat(kit): Music tab and 3-bar visualizer`.

### Task 16: AgentsPlugin — Agents tab, closed-notch figure, strip content

**From:** L, Question and choice: "Agents side in Hex's style: black and white, Inter, monospace figures, hairline panels, one glossy keycap." and D: "Codex runs are flagged, with no Stop or Redirect buttons."

**Files:** Create `Sources/OpenNotchKit/AgentsPlugin.swift`, `Sources/OpenNotchKit/AgentsViews.swift`, `Tests/OpenNotchKitTests/AgentsPluginTests.swift`; add both to the import contract test.

**Interfaces — Consumes:** Tasks 5, 13, 15. **Produces:**
```swift
@MainActor public struct AgentsPlugin: NotchPlugin, NotchTabProvider {
    public static let manifest = PluginManifest(id: "cafe.notch.agents", name: "Agents", version: "1.0.0", author: "OpenNotch")
    public func tabs() -> [PluginTab]          // id "agents", "Agents", "sparkle"
    public func compactTrailing() -> AnyView?  // tightest % + hairline fill; inverted "4.3×" badge while alert != nil
    public func widgets() -> [PluginWidget]    // []
}
public struct RunawayStrip: View { public init(service: AgentUsageService, onFocusChange: @escaping (Bool) -> Void) }
public func multipleText(_ m: Double) -> String   // 4.31 → "4.3×"
```
Behaviour, per the mockup:
- Agents tab rows:
  - Claude 5h and Weekly, Codex limits, Codex credits.
  - Live sessions: tag CC/CX, project, `tok/min`, `×normal`, 30-minute spark from `burn.history`.
  - A Stop keycap on a flagged Claude row when `canControl`.
  - With no limits for an agent: "—" and "Connect in Settings" (Claude) or nothing (Codex).
- Strip:
  - Shows tag, project, first prompt, `"<multiple> your normal"`, mono stats (rate, total, duration) and a ×.
  - Redirect and Stop keycaps only when `session.agent == .claude && canControl`.
  - Redirect opens a text field and calls `onFocusChange(true)` (Task 4 recipe). Return sends the text; Escape closes the field and calls `onFocusChange(false)`.
  - Hook missing: "Install the hook in Settings to stop sessions from here".

- [ ] **Step 1: Write the failing tests:** `agentsPluginProvidesAgentsTab`, `multipleTextRoundsToOneDecimal` (`4.31 → "4.3×"`, `3 → "3.0×"`), `stripButtonsOnlyForControllableClaude` (a pure helper `stripActions(for: AgentKind, canControl: Bool) -> [StripAction]` → `[.redirect, .stop, .dismiss]` for `.claude, true`; `[.dismiss]` for `.codex, true` and for `.claude, false`).
- [ ] **Step 2–4:** FAIL → implement → PASS. **Step 5:** Commit `feat(kit): Agents plugin`.

---

## Phase 4 — Host: shell

### Task 17: Narrow widths, tab pill, Inter

**From:** L, Question and choice: "Hover panel, 440 wide, **tabs** (Agents, Music) in a floating pill under the panel, as in NotchNook. Opens on Agents while a session runs." and L, Constraints: "Closed notch stays at or under today's width (about 285 on a 14-inch MacBook); target 270."

**Files:** Modify `Sources/OpenNotch/NotchWindow.swift`, `NotchShell.swift`, `AppDelegate.swift`, `Sources/OpenNotchKit/AdapterPaths.swift` (+ test), `Scripts/make-app.sh`. Add `vendor/inter/InterVariable.ttf` + `vendor/inter/OFL.txt`. Get them from the official Inter release (rsms/inter on GitHub) after the owner says yes to the download.

**Acceptance criteria (manual DoD, plus the AdapterPaths test):**
- Ambient width = `notchGap + 80`; ≤ 285 on a 14-inch MacBook (log it once at launch).
- The ambient bar shows when media is present **or** any `PlanLimits` exist.
- Expanded width is 440, and the height follows the tab: Agents ≈ 300, Music / Launcher / Widgets ≈ 150, per the mockup.
- The fixed panel grows to fit the panel, an 8 pt gap and the 36 pt pill, plus spring headroom. The hit-rect covers the pill.
- The pill floats under the panel: the active tab shows icon + title, the others icon only. A clicked tab stays selected while the panel is open. Each open starts on `TabBar.defaultTab`.
- Launcher tab = today's `QuickActionsColumn` laid out as a grid. Widgets tab = today's `widgetGrid` over `runtime.widgets`.
- `AdapterPaths.Resolved` gains `interFont: String`, resolved like the adapter (bundle Resources, else `vendor/inter/`). The host registers it with `CTFontManagerRegisterFontsForURL(…, .process, nil)`. `make-app.sh` copies the font.
- `AppDelegate` adds `AgentsPlugin(host:)` first, then `MediaPlugin`, then `AppLauncherPlugin`.
- `swift test` passes; `swift run OpenNotch` shows the new shell with the default (empty) services.

- [ ] **Step 1:** Add `interFont` to `AdapterPathsTests` (both branches) → FAIL → implement → PASS.
- [ ] **Step 2:** Shell, window and font changes; run the app; check each criterion.
- [ ] **Step 3:** Commit `feat: narrow tabbed notch with Inter`.

### Task 18: Runaway strip in the shell

**From:** D, Constraints: "The runaway strip stays 30 s, then folds into a "4.3×" badge. The × dismisses it and starts the 15-minute cooldown."

**Files:** Modify `NotchWindow.swift`, `NotchShell.swift`.

**Acceptance criteria (manual DoD with a fake alert from a debug menu item, removed before commit, or a low threshold):**
- When `agents.alert` goes nil → non-nil, the controller sends `.alertRaised`. The shell renders `RunawayStrip` at 360 wide.
- The fold timer is 30 s and pauses while the cursor is over the strip. On expiry: `.alertFolded`, and the closed notch shows the "4.3×" badge.
- While in `.alert`, the hit-rect is the strip, and hovering does not open the panel.
- Hovering a closed notch with the badge opens the Agents tab with that session first.
- × → `agents.dismiss` + `.alertClosed`. Stop/Redirect → service call + `.alertClosed`.
- Redirect field: `NotchWindow.canBecomeKey` follows the strip's `onFocusChange`. Typing works without activating the app (Task 4 recipe).

- [ ] **Step 1:** Implement. **Step 2:** Check each criterion. **Step 3:** Commit `feat: runaway strip`.

---

## Phase 5 — Host: services

### Task 19: AgentWatcher and the agents service

**From:** D, Constraints: "Sub-agent work counts with its parent session for rate and baseline." and spec § Session identity.

**Files:** Create `Sources/OpenNotch/AgentWatcher.swift`, `Sources/OpenNotch/AgentUsage.swift` (`@Observable final class AgentUsage: AgentUsageService`); modify `AppDelegate.swift` (`AppHost.agents`).

**Acceptance criteria:**
- FSEvents stream (`kFSEventStreamCreateFlagFileEvents`, latency 0.5 s) on `~/.claude/projects` and `~/.codex/sessions`.
- Per file: a stored byte offset and a `LineSplitter`. Only new bytes are read.
- Lines are parsed and `ingest`ed on a background queue; results are published on the main actor.
- At launch, files modified in the last 5 minutes are read whole (live sessions).
- Baseline:
  - On a utility queue, at launch and every 24 h, read every top-level and sub-agent file modified in the last 30 days.
  - Compute per-session `Baseline.averageRate` and set `normalRate` per agent.
  - Log the duration; it must not block the UI.
- After each publish: for every live session, run `RunawayDetector.update` with `burn.perMinute`; set `alert` to the highest flagged session.
  - Threshold and window come from Settings (Task 23); defaults 3.0 and 600 s.
- `dismiss`, `stop` and `redirect` call `detector.acknowledge`.
- `limits` = Claude limits from Task 20, plus `latestLimits[.codex]`.
- Check: with a live Claude session, the Agents tab lists it with a rising `tok/min`. A Codex run appears under its parent thread.

- [ ] **Step 1:** Implement. **Step 2:** Check with real sessions. **Step 3:** Commit `feat: watch agent logs`.

### Task 20A: Own Claude sign-in (added 2026-11-20)

**From:** `docs/decisions/2026-11-20-claude-usage-source.md`, Question and choice: "Add an OpenNotch sign-in with its own token. The Claude % is always live." and Constraints: "OpenNotch keeps and refreshes its own token in its own Keychain item, separate from Claude Code."

**Files:** Spike note `docs/superpowers/spikes/2026-11-20-claude-sign-in.md`. Kit (pure, test-first): `Sources/OpenNotchKit/ClaudeSignIn.swift` + `Tests/OpenNotchKitTests/ClaudeSignInTests.swift`. Host: `Sources/OpenNotch/ClaudeSignInFlow.swift`.

**Acceptance criteria:**
- Spike first, with the owner at the Mac (record line: Open questions, "A spike with one live sign-in by the owner must confirm them before the client is built."): the note records the authorize and token URLs, client id, scopes, redirect form, and whether `GET /api/oauth/usage` answers 200 with the new token and which auth header it needs. NO-GO (no 200) → stop, tell the owner, and Task 20 runs as "Keep the plan" (record: Open questions, "If it fails, the app falls back to "Keep the plan".").
- Kit: PKCE verifier/challenge (S256), the authorize URL builder, the token-response parser (access token, refresh token, expiry), and `needsRefresh(at:)`. Tests: known PKCE vector, URL has every required query item, parser rejects a body without `access_token`, refresh due 5 min before expiry.
- Host: "Connect" opens the browser; a loopback listener on 127.0.0.1 takes the callback once and closes; the code is exchanged; tokens go to OpenNotch's own Keychain item (service `OpenNotch-claude`), never to `Claude Code-credentials` (record: Constraints, "The Claude Code Keychain item is never written, refreshed or copied").
- Refresh: before a usage call when `needsRefresh`; a failed refresh shows "—" and "Reconnect" (record: Constraints, "When the sign-in, the refresh or the endpoint fails, the Claude rows show "—" … and a "Reconnect" action.").
- Nothing starts before the owner clicks "Connect"; no token value is ever printed, logged or committed (record: Constraints, third line).

- [ ] **Step 1:** Spike with the owner; write the note; commit `docs: spike Claude sign-in`. **Step 2–4:** Kit tests FAIL → implement → PASS; commit `feat(kit): Claude sign-in helpers`. **Step 5:** Host flow; check by hand: Connect → browser → back in the app → Claude % shows; relaunch → no prompt, still connected. Commit `feat: OpenNotch Claude sign-in`.

### Task 20: Claude usage client

> **Amended 2026-11-20 by `docs/decisions/2026-11-20-claude-usage-source.md`:** the token comes from Task 20A's own sign-in, not from the `Claude Code-credentials` item. Replace the Keychain-read criterion with "read OpenNotch's own item via Task 20A", and replace "no refresh is attempted" with "refresh via Task 20A once; on failure show "—" and "Reconnect"". All other criteria stand. If Task 20A's spike is NO-GO, run this task as written.

**From:** D, Constraints: "The app only reads the Claude Code token. It never refreshes, writes or copies it." and "Claude usage is fetched when a transcript changes (at most once a minute) and when the panel opens. No timer."

**Files:** Create `Sources/OpenNotch/ClaudeUsageClient.swift`; modify `AgentUsage.swift`.

**Acceptance criteria:**
- Nothing touches the Keychain until `connect()` (Settings "Connect", Task 23). Connected state is stored in UserDefaults `cafe.notch.agents.claudeConnected`.
- Read: `SecItemCopyMatching` for `kSecClassGenericPassword`, service `Claude Code-credentials`, `kSecReturnData`. Parse with `ClaudeCredential.parse`. The token stays in memory only and is never logged.
- Fetch with the URL and headers from Task 1. Triggers:
  - A Claude file event, if ≥ 60 s since the last fetch.
  - `refreshLimits()` on panel open, also ≥ 60 s.
- Expired token or HTTP 401: no request is retried and no refresh is attempted. Keep the last snapshot; the UI shows its age.
- Keychain denied → "—" with "Connect in Settings".

- [ ] **Step 1:** Implement. **Step 2:** Check: the values match `/usage` in Claude Code; quit and relaunch → no Keychain prompt until Connect. **Step 3:** Commit `feat: Claude plan usage`.

### Task 21: Hook installer and Stop / Redirect

**From:** D, Constraints: "Stop and Redirect exist for Claude Code sessions only, through a `PreToolUse` hook that fails open."

**Files:** Create `Sources/OpenNotch/HookInstaller.swift`; modify `AgentUsage.swift`.

**Acceptance criteria:**
- `install()`:
  1. Write `Directive.hookScript` to `~/Library/Application Support/OpenNotch/hooks/pretooluse.sh` (mode 0755).
  2. Read `~/.claude/settings.json`. Missing → nil; invalid → abort with an error shown in Settings, file untouched.
  3. Back it up to `settings.json.opennotch-backup-<yyyyMMdd-HHmmss>`.
  4. Write `ClaudeSettingsPatch.install` atomically.
- `remove()` reverses it; `isInstalled` drives `canControl`.
- `stop`/`redirect` write `Directive.hookOutput` to `directives/<sessionId>.json` atomically, only if `Directive.isSafeSessionId`. A Claude session id is the transcript file name.
- Check, live: a runaway forced with threshold 0.1 → the strip shows. Stop ends the turn at the next tool call. Redirect makes Claude follow the text. Removing the hook restores the settings content (the diff against the backup shows only our entry gone).

- [ ] **Step 1:** Implement. **Step 2:** Check live. **Step 3:** Commit `feat: stop and redirect Claude sessions`.

### Task 22: Audio tap service

**From:** L, Question and choice: "artwork + 3 smooth spectrum bars left of the camera".

**Files:** Create `Sources/OpenNotch/AudioTapService.swift` (`@Observable final class AudioTap: SpectrumService`); modify `AppDelegate.swift`, `Scripts/make-app.sh` (`NSAudioCaptureUsageDescription`: "OpenNotch shows a live spectrum of the music you play.").

**Acceptance criteria:**
- Follows `nowPlaying.current?.sourceBundleId` → `NSRunningApplication` PID → process tap (exact calls from Task 3).
- Starts when playback starts; tears down tap + aggregate device when playback stops or the source app changes.
- IOProc copies samples into a buffer. A background queue runs `SpectrumAnalyzer` + `SpectrumBands`, publishing `levels` to the main actor at 30 Hz only while playing.
- `isAvailable == false` on macOS < 14.2, tap failure or denied permission → the bars use the fallback.
- Check: bars follow the music (bass hit → left bar); pause → bars settle; CPU of OpenNotch < 5% while playing.

- [ ] **Step 1:** Implement. **Step 2:** Check. **Step 3:** Commit `feat: live spectrum from the playing app`.

---

## Phase 6 — Settings and DoD

### Task 23: Settings — Agents tab and Integrations

**From:** D, Constraints: "The Keychain prompt appears only after the owner clicks "Connect" in Settings."

**Files:** Modify `Sources/OpenNotch/SettingsWindow.swift` (new `AgentsTab`), `AppDelegate.swift`.

**Acceptance criteria:**
- Alert threshold stepper (1.5–10×, default 3×). Window stepper (5–30 min, default 10). Alerts on/off. All stored in `UserDefaultsPluginStorage(pluginId: "cafe.notch.agents")` and applied live.
- Integrations:
  - "Claude plan usage": Connect / Disconnect with state.
  - "Claude hook": Install / Remove with state, and the error from Task 21 when invalid.
  - "Audio": state + Grant. Grant starts the tap, which triggers the prompt; if denied, it opens Privacy settings.
- No Keychain prompt and no settings.json change happen anywhere else.

- [ ] **Step 1:** Implement. **Step 2:** Check each control. **Step 3:** Commit `feat: agents settings`.

### Task 24: README DoD and full check

**From:** D, Question and choice: "Approve the design doc as written, with my calls."

**Files:** Modify `README.md` (new "Definition of Done — spectrum and agents" checklist).

**Acceptance criteria:** the checklist holds the spec's manual DoD, and every item is ticked on the real app (`Scripts/make-app.sh`, open `build/OpenNotch.app`):
- Closed width on a 14-inch MacBook.
- Bars follow the music.
- Limits match Claude Code's `/usage` and Codex's `/status`.
- A forced runaway (low threshold) shows the strip and folds into the badge.
- Stop ends the turn; Redirect changes course.
- A Codex runaway shows no Stop or Redirect.
- Hook removal restores settings.
- No Spotify → bars idle.
- A pre-existing `.notchplugin` (if any) still loads.

`swift test` passes.

- [ ] **Step 1:** Write the checklist. **Step 2:** Run it, tick it, note any failure as a follow-up. **Step 3:** Commit `docs: DoD for spectrum and agents`.
