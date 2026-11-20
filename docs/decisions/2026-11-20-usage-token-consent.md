# May Task 1 read the Claude Code login for one usage call?

Decided: 2026-11-20 · Case: c_5788dd71-484c-4ce4-bc3c-59634105b8e7

## Question and choice
Task 1 (spike: Claude usage endpoint) needs the access token from the Keychain item `Claude Code-credentials`.

Chosen: "Yes: read the Keychain item once (key names only) and make up to 3 usage calls with the token, never printed or stored."

## Why
- The owner chose the usage endpoint for the Claude 5-hour and weekly % (`docs/decisions/2026-11-20-spectrum-agents-design.md`).
- Agent's reason: without one live call, the URL, the headers and the response shape stay unconfirmed.

## Constraints
- Only key names and value types are printed, never values.
- The token lives in a shell variable for one command only. It is never printed, logged, written to a file or committed.
- At most 3 calls to `GET https://api.anthropic.com/api/oauth/usage`.
- No refresh, no write to the Keychain item.
- The spike note holds field names, units and an anonymised example only: no token, no account ids.

## Ruled out
- Skipping the spike: Claude limit rows would show "—" and Task 20 would be dropped.

## Comments
none

## Open questions
none

## Sources
- Case c_5788dd71-484c-4ce4-bc3c-59634105b8e7
- `docs/superpowers/plans/2026-11-20-spectrum-and-agents.md`, Task 1
- `docs/decisions/2026-11-20-implementation-plan.md` (constraint: ask before reading the token)
