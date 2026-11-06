# ForumRepository multi-account API

Account types are defined in `lib/services/forum_account_registry.dart`. The UI binding is described in [multi-account-ui-api.md](multi-account-ui-api.md), and storage invariants in [multi-account-backend-design.md](multi-account-backend-design.md).

## Observable state

```dart
ValueListenable<List<AccountSummary>> get accounts;
ValueListenable<AccountSummary?> get activeAccount;
ValueListenable<int> get sessionEpoch;

String get localDataScope;
String get localPreferenceAccount;
```

`accounts` includes saved accounts from all origins, including those needing reauthentication. UI account lists filter it to the current normalized origin. `activeAccount == null` represents guest mode. Both local-scope getters use the stable account ID or an origin-specific guest scope.

Capture the scope or session epoch before starting asynchronous work. Check that the captured session is still current before publishing an account-sensitive result.

## Select, log out, and remove

```dart
Future<void> switchAccount(String accountId);
Future<void> selectAccount(String accountId);
Future<void> logoutAccount(String accountId);
Future<void> logoutCurrent();
Future<void> removeAccount(String accountId);
```

`selectAccount` is an alias for `switchAccount`. Selection rejects an unknown account, a foreign-origin account, or an account needing reauthentication. A ready account whose stored jar is missing becomes `needsReauth` and enters guest mode.

Logging out retains the record as `needsReauth`; removing an account deletes its record. Both clear its credentials. Acting on the current account enters guest mode. Acting on another account leaves the current account selected. No operation implicitly selects a different ready account.

## Add an account

```dart
Future<LoginChallenge> fetchAddAccountChallenge();

Future<AccountSummary> submitAddAccount({
  required String username,
  required String password,
  required String captcha,
  Map<String, String> fields = const {},
});

Future<void> cancelAddAccount();

Future<AccountSummary> addAccount({
  required String username,
  required String password,
  String captcha = '',
  Map<String, String> fields = const {},
});
```

The challenge and submit calls share an isolated staging client. Pass the challenge's hidden fields back to submit. A successful submit verifies a numeric UID, saves the account, and selects it. The same origin and UID update the existing entry and install the accepted credentials. Failed or cancelled attempts leave the active account intact.

The one-shot `addAccount` wrapper obtains the challenge and submits the supplied credentials. The login screen uses the split challenge/submit flow so it can display the captcha.

## Reauthenticate an account

```dart
Future<LoginChallenge> fetchReauthChallenge(String accountId);

Future<AccountSummary> submitReauthAccount(
  String accountId, {
  required String username,
  required String password,
  required String captcha,
  Map<String, String> fields = const {},
});

Future<void> cancelReauthAccount();

Future<AccountSummary> reauthAccount(
  String accountId, {
  required String username,
  required String password,
  String captcha = '',
  Map<String, String> fields = const {},
});
```

The target must belong to the current origin. The authenticated UID must equal the target UID; a mismatch raises `ForumAccountUidMismatchException`. A successful operation replaces the target credentials and selects the account. A failed attempt leaves the previous active account intact.

Starting another challenge or changing network configuration cancels pending staging work. Closing the login flow calls the matching cancellation method.

## Session restoration and legacy login

`restoreSession()` restores the selected v3 account when present. Empty selected jars become `needsReauth`. Legacy credentials on an origin without registered accounts remain eligible for migration until a verified UID allows promotion to the stable account slot. Registered origins without a selection enter guest mode; residual legacy cookies must not revive a removed or logged-out account.

The existing `fetchLoginChallenge`, `submitLogin`, and `login` methods remain available to legacy callers. The account switcher uses the add/reauthentication facade. Existing sign-in prompts continue to use the legacy sign-in helpers.

When an account is selected, legacy sign-in uses staging even if that account has expired cookies. It preserves the selected account until the new credentials and registry update are acknowledged. A successful sign-in with a different UID retires the old slot and marks its account `needsReauth` as it installs the new identity. Leaving the sign-in page calls `cancelLogin()` to abandon its pending staging attempt; this does not change the current account.

Changing sites clears the active selection and preserves saved records. It does not choose a ready account on the destination site. Changing network mode on the same site carries the current jar into the replacement client; any cached identity must still match its credential generation.
