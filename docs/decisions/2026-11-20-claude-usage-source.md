# Where should the Claude plan % come from?

Decided: 2026-11-20 · Case: c_f323eab8-0291-47cf-ac77-101a050b8e5c

## Question and choice
The usage endpoint works, but this Mac has no Claude Code token to call it with: the CLI login ended (`loginEnded: time_limit`, empty `accessToken`), and desktop-app sessions keep their own login. Which source should the Claude 5-hour and weekly % use?

Chosen: "Add an OpenNotch sign-in with its own token. The Claude % is always live. About one more task, with some terms risk." (Own Claude sign-in)

## Why
- The owner wants the Claude % live, not "—" or a stale snapshot.
- Agent's reasons: a read-only app cannot get a fresh token by itself, and 58 of 59 sessions this week ran in the desktop app, which never updates the Claude Code Keychain item.

## Constraints
- "Connect" opens a browser sign-in. OpenNotch keeps and refreshes its own token in its own Keychain item, separate from Claude Code.
- The Claude Code Keychain item is never written, refreshed or copied (unchanged plan constraint). Agent's call: OpenNotch stops reading it, since its own token replaces it.
- The sign-in starts only after the owner clicks "Connect". The token is never printed, logged or committed.
- Usage is still fetched when a Claude transcript changes (at most once a minute) and when the panel opens. No polling.
- When the sign-in, the refresh or the endpoint fails, the Claude rows show "—" (or the last values with their age) and a "Reconnect" action. Codex limits are unaffected.
- The owner accepts the risk: the flow uses Claude Code's sign-in client on an unofficial endpoint, it can break, and third-party use may go against Anthropic's terms.
- The team plan's time limit also ends this login, so the owner reconnects from time to time.

## Ruled out
- Keep the plan (agent's recommendation): free and read-only, but the Claude % shows "—" on this Mac because the CLI login is dead.
- Sign in to the Claude Code CLI again: no code, but only the CLI refreshes its token and it expires in hours; with the desktop app the numbers go stale the same day.

## Comments
none

## Open questions
- The sign-in details (authorize and token URLs, client id, scopes, redirect) and the usage call's auth header are unconfirmed: the Task 1 spike got a 401 asking for `x-api-key`. A spike with one live sign-in by the owner must confirm them before the client is built. If it fails, the app falls back to "Keep the plan".

## Sources
- Case c_f323eab8-0291-47cf-ac77-101a050b8e5c
- `docs/superpowers/spikes/2026-11-20-usage-endpoint.md`
- `docs/decisions/2026-11-20-usage-token-consent.md`
- `docs/superpowers/plans/2026-11-20-spectrum-and-agents.md`, Tasks 1, 8, 20
