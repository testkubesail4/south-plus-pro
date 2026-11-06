# Multi-account session and storage design

The repository owns account operations. UI code calls the public facade described in [multi-account-repository-api.md](multi-account-repository-api.md); it does not read or write cookie keys.

## Identity and origin

`ForumAccountId.value` is the normalized origin, a `\u001f` separator, and a positive numeric UID. Normalization lowercases the scheme and host and removes default ports. Display names and login handles are presentation data, so renaming an account does not change its storage scope.

Account selection and reauthentication operate on the current origin. A foreign-origin target must be rejected before changing the active account, credentials, or epoch. To use another site's account, change the site through the network settings and then select an account for that site. Changing sites must not choose the first ready account automatically.

## Cookie slots

| Slot | Storage | Purpose |
| --- | --- | --- |
| Account | `forum_session_cookies_v3:{accountId}` | Credentials for one origin and UID |
| Staging | Memory only | An isolated add or reauthentication attempt |
| Legacy origin | `forum_session_cookies_v2:{host}`, with v1 migration support | Existing credentials whose UID may not yet be known |

`ForumAccountRegistry` persists account summaries and the selected account ID. A summary is `ready` or `needsReauth`. Guest mode has no active account.

Adding an account uses a separate client and staging jar. Challenge loading, rejected credentials, and cancellation leave the active session intact. Once the UID is verified, the operation saves and verifies the account jar, then persists the registry update. Only after storage acknowledges that update does it synchronously install the jar and publish the new active account and epoch. A rejected write leaves the previous live session intact. Adding the same origin and UID updates one record and installs the newly accepted credentials in the live client.

Reauthentication also uses staging. The returned UID must match the target account; a mismatch raises `ForumAccountUidMismatchException` and preserves the previous active session.

The legacy sign-in helpers use an isolated staging jar whenever an account is selected, including when its cookies have expired. Failed or cancelled sign-ins leave that account unchanged. When a successful legacy sign-in changes the UID, the same commit selects the new account and marks the old account `needsReauth`, then clears the old jar.

Selecting a saved account follows the same publication rule: prepare its jar and obtain the registry acknowledgement before changing the live client. Account-list, active-account, and epoch observers must see credentials and metadata from the same session.

## Asynchronous isolation

Every request captures its cookie slot and generation when admitted. Cookie persistence captures the same slot, storage target, and cookie snapshot. A response admitted for an old slot or generation cannot mutate a replacement session.

Slot generations remain retired after deletion, including when the same account ID is added again. Repository and UI work also capture session epochs or local-data scopes before awaiting results. Late identity, history, profile, search, and watch results cannot publish into a different account.

Credential retirement must invalidate the slot before clearing its jar. The clear operation shares the cookie write queue, so it runs after a save that already entered asynchronous storage. Queued writes recheck their captured generation. The completed clear therefore remains the final persisted state; a delayed save cannot restore credentials after logout or removal. Queued clears also capture their storage target, so rebinding the client cannot redirect an account A clear into account B.

## Logout and removal

| Operation | Account record | Credentials | Active session |
| --- | --- | --- | --- |
| Log out current account | Keep as `needsReauth` | Clear account and residual legacy-origin credentials | Enter guest |
| Remove current account | Remove | Clear account and residual legacy-origin credentials | Enter guest |
| Log out another account | Keep as `needsReauth` | Clear that account's credentials | Keep the current account |
| Remove another account | Remove | Clear that account's credentials | Keep the current account |

Cleared scoped jars retain an empty-object tombstone. This prevents fallback to old credentials. Account jars must never be copied back into legacy origin jars. Cached origin identity is removed only for the retired identity; a ready peer on the same origin keeps its own jar and identity.

## Migration and local data

When a legacy session yields a valid UID, write and verify its v3 jar and registry entry before retiring the legacy key. Failures before publication leave the previous session recoverable. Once the new session is durably committed and published, failure to clear the source legacy jar does not roll back that successful login. Logout and removal retry the origin cleanup.

Cold restoration prefers the selected v3 account. Once an origin has account records, an unselected origin enters guest mode instead of importing residual legacy cookies. Site changes also leave registered destination origins in guest mode until the user selects an account. A cold start with a selected account but an empty jar marks that account `needsReauth` and enters guest.

`ForumRepository.localDataScope` is the stable account ID, or `guest:{normalizedOrigin}` for a guest. `localPreferenceAccount` exposes the same scope for existing preference consumers.

| Data | Isolation boundary |
| --- | --- |
| Browsing history | SQLite scope and thread URL |
| Read positions | One scoped preference bucket |
| Profile overview cache | Viewer scope and profile URL |
| Local blocking rules | Stable scope, including origin |
| Notes, tags, search and home preferences | Stable preference scope |
| Task snapshots and watch state | Stable scope, with session checks for asynchronous work |

Old data without an owner stays unowned. Migration preserves it without assigning it to the current account or copying it to every account. Clearing scoped history also clears that scope's read positions and leaves other accounts and unowned data intact.

## Validation boundaries

The account tests cover identity encoding, registry persistence, staging isolation, UID mismatch, cookie admission and retirement, origin checks, and account replacement. Store tests exercise a real SQLite file through migration, close, and reopen. Repository and UI tests cover scope propagation, delayed responses, account actions, and navigation.

Each implementation checkpoint requires independent review and correction of Medium-or-higher findings. The final release gate is a whole-diff review plus changed-file formatting, full analysis, and the full test suite.
