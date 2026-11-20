# Spike — Claude usage endpoint and Keychain item

Date: 2026-11-20 · Plan Task 1 · Owner consent: `docs/decisions/2026-11-20-usage-token-consent.md`

## Verdict

- **Response shape: GO.** Known from Claude Code's own cache of this response (see below).
- **Token source: NO-GO on this Mac.** The Keychain item holds no usable token. The Claude Code CLI login ended (`loginEnded: "time_limit"`, `accessToken` empty, `expiresAt: 0`). Desktop-app sessions (58 of 59 in the last 7 days) keep their own login and never update this item.
- No authenticated call was made: there was no token to send.
- Fallback per plan: Claude limit rows show "—" (or the last snapshot with its age); Codex limits still work. The owner is told before Task 20.

## Endpoint

- `GET https://api.anthropic.com/api/oauth/usage`
- Headers: `Authorization: Bearer <accessToken>`, `anthropic-beta: oauth-2025-04-20`.
- Without a token: `HTTP 401`, body `{"type":"error","error":{"type":"authentication_error","message":"x-api-key header is required",…}}`. So the path exists; the Bearer header is not confirmed live.

## Keychain item

Generic password, service `Claude Code-credentials`, value is JSON. Top-level keys: `claudeAiOauth`, `mcpOAuth`, `trustedDeviceToken`.

`claudeAiOauth` keys and types:

| Key | Type | Note |
|---|---|---|
| `accessToken` | str | empty on this Mac |
| `refreshToken` | str | never read by the app |
| `expiresAt` | int | **milliseconds** since 1970 (`refreshTokenExpiresAt` has 13 digits); `0` here |
| `refreshTokenExpiresAt` | int | ms |
| `scopes` | list | includes `user:profile`, `user:inference` |
| `subscriptionType` | str | e.g. `team` |
| `subscriptionTypeSource` | str | |
| `rateLimitTier` | str | |
| `loginEnded` | str | `time_limit` here: the login ended; treat as no token |

Only "Claude Code-credentials" and "Claude Safe Storage" (the desktop app's Electron key, off-limits) exist as Claude Keychain services.

`ClaudeCredential.parse` (Task 8) must return nil when `accessToken` is empty or `loginEnded` is present.

## Response shape

Source: `~/.claude.json` → `cachedUsageUtilization.utilization`, which Claude Code writes from this endpoint (wrapper fields `fetchedAtMs` and `accountUuid` are Claude Code's, not the response). Last written 2026-11-02 by the CLI.

- Windows are objects or `null`. Used ones: `five_hour`, `seven_day`. Null on this account: `seven_day_opus`, `seven_day_sonnet`, `seven_day_oauth_apps`, and a dozen code-named keys.
- `utilization`: percent 0–100 (number). `resets_at`: ISO-8601 with microseconds and offset (`2026-11-02T18:30:00.181910+00:00`), so parse with fractional seconds.
- `extra_usage`: paid overage (`is_enabled`, `monthly_limit`, `used_credits`, `currency`, `decimal_places`). Not shown (non-goal: no money).
- `limits`: a newer list (`kind` `session` / `weekly_all` / `weekly_scoped`, `percent`, `resets_at`, `severity`, `is_active`). The decoder uses `five_hour` and `seven_day`; `limits` is ignored.

Anonymised example (Task 8 fixture):

```json
{
  "five_hour": {"utilization": 16, "resets_at": "2026-11-02T18:30:00.181910+00:00",
                "limit_dollars": null, "used_dollars": null, "remaining_dollars": null, "locked_reason": null},
  "seven_day": {"utilization": 9, "resets_at": "2026-11-06T19:00:00.181929+00:00",
                "limit_dollars": null, "used_dollars": null, "remaining_dollars": null, "locked_reason": null},
  "seven_day_oauth_apps": null,
  "seven_day_opus": null,
  "seven_day_sonnet": null,
  "extra_usage": {"is_enabled": true, "monthly_limit": 100000, "used_credits": 0, "utilization": null,
                  "currency": "EUR", "decimal_places": 2},
  "limits": [
    {"kind": "session", "group": "session", "percent": 16, "severity": "normal",
     "resets_at": "2026-11-02T18:30:00.181910+00:00", "scope": null, "is_active": true},
    {"kind": "weekly_all", "group": "weekly", "percent": 9, "severity": "normal",
     "resets_at": "2026-11-06T19:00:00.181929+00:00", "scope": null, "is_active": false}
  ]
}
```

## What this changes

- Task 8: fixture above; credential parse rejects an empty token or `loginEnded`.
- Task 20: as planned, the read-only token path works only while a CLI login is live. On this Mac it shows "—" until the owner decides otherwise (asked in Waggle).
