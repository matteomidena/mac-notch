# Spike: OpenNotch's own Claude sign-in

Date: 2026-11-20 · Plan Task 20A · Decision `docs/decisions/2026-11-20-claude-usage-source.md`

## Verdict

- **NO-GO.** The browser sign-in worked, but the token endpoint refused the code exchange with HTTP 403 and a non-JSON body. No token was issued, so the usage call was never reached.
- Following the plan, Task 20 runs as "Keep the plan": it reads the `Claude Code-credentials` item read-only. On this Mac the Claude rows show "—" until the Claude Code CLI is signed in again.
- No workaround was tried. A 403 with a non-JSON body looks like an edge filter in front of the endpoint. Changing the client's identity to get past it would mean evading that filter, and the decision already noted that third-party use of this client may go against Anthropic's terms.

## Sign-in details (read from the local Claude Code binary, read-only)

| Item | Value |
|---|---|
| Authorize URL (claude.ai login) | `https://claude.com/cai/oauth/authorize` |
| Authorize URL (Console login) | `https://platform.claude.com/oauth/authorize` |
| Token URL | `https://platform.claude.com/v1/oauth/token` |
| Client id | `9d1c250a-e61b-44d9-88ed-5944d1962f5e` |
| Redirect | `http://localhost:<port>/callback` (manual: `https://platform.claude.com/oauth/code/callback`) |
| Authorize query | `code=true`, `client_id`, `response_type=code`, `redirect_uri`, `scope`, `code_challenge`, `code_challenge_method=S256`, `state` |
| Claude Code's scopes | `org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload` |
| Token request | JSON POST: `grant_type=authorization_code`, `code`, `redirect_uri`, `client_id`, `code_verifier`, `state` |
| Refresh request | JSON POST: `grant_type=refresh_token`, `refresh_token`, `client_id`, `scope` |
| Usage call (untested here) | `GET https://api.anthropic.com/api/oauth/usage`, `Authorization: Bearer`, `anthropic-beta: oauth-2025-04-20` |

## Run

- A throwaway Python stdlib script in the session scratchpad (not the repo) did PKCE S256, listened on `127.0.0.1` with a random port, and opened the default browser. It asked for `user:profile user:inference`.
- The owner approved in the browser. The callback arrived after 30 s with `code` and `state`, the state matched, and the listener closed.
- The token exchange answered **HTTP 403** with a non-JSON body. The script printed only the status, so the body's content is unknown.
- The script printed only statuses and key names. No token or code was printed, logged or stored.

## What this changes

- Task 20A: stop after this note. No Kit or host sign-in code.
- Task 20: run as written (read-only `Claude Code-credentials`, no refresh), per the amendment's NO-GO clause.
- Task 23: no "Connect" sign-in. Settings shows the Claude usage source state and "—" when the Claude Code token is missing or expired.
