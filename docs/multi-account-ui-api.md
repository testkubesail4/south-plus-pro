# Multi-account UI binding

`account_switcher_binding.dart` connects the profile page and `AccountSwitcherSheet` to `ForumRepository`. The sheet uses the application's existing colors, typography, icons, and modal components.

## Account rows

`AccountSummary` provides the following presentation data:

| Field | Meaning |
| --- | --- |
| `id` | Stable normalized origin and UID; used for every action |
| `displayName` | Primary name, with account metadata as fallback |
| `systemName` | Login name, when known |
| `uid` | Numeric forum identity, when known |
| `avatarUrl` | Optional avatar |
| `status` | `ready` or `needsReauth` |
| `isActive` | Whether this record is selected |

The repository retains records from all origins. The profile page and switcher show accounts for the current normalized origin only. Staging attempts and guest mode do not create account rows.

The active row is visibly selected. A row needing authentication opens the reauthentication flow. Account actions use `id`; display names can collide or change.

## Actions

| UI action | Repository operation |
| --- | --- |
| Select ready account | `selectAccount(id)` |
| Add account | `fetchAddAccountChallenge` and `submitAddAccount` |
| Reauthenticate | `fetchReauthChallenge(id)` and `submitReauthAccount(id, ...)` |
| Remove account | `removeAccount(id)` after confirmation |
| Log out current account | `logoutCurrent()` after confirmation |

The login screen keeps add and reauthentication flows distinct and cancels the matching staging attempt when the user leaves. A rejected login or UID mismatch displays an actionable error while preserving the active account. For sign-in with a selected account, returning from the page cancels the isolated attempt through `cancelLogin()`.

While selection, logout, or removal is pending in the sheet, duplicate actions and user dismissal are disabled. Selection and logout close the sheet after success; add and reauthentication replace it with the login page. Removal refreshes the list in place. Failed sheet operations display an error and enable retry. The login page can be closed to cancel its staging attempt.

Logging out or removing the current account enters guest mode. Removing another account leaves the current account selected. Use the existing site settings before selecting an account from a different origin.

## Scope-sensitive screens

History, read positions, profile data, annotations, and preference consumers use the repository's stable scope. Capture the scope and epoch when work begins. A delayed result from an earlier session must not populate the new session's screen or write under its scope.

History reloads on a session change. Thread restoration and anchor saves reject stale work. Home layout preferences follow the stable scope, including when two accounts have the same display name.

## Validation

Widget coverage includes selection, confirmation, failures and retry, busy-state dismissal, delayed binding completion, login-route replacement, account-list filtering by origin, guest state, and stale history/read-position results. Light and dark presentation and large text require visual inspection in addition to behavioral tests.
