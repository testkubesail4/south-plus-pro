import 'forum_account_id.dart';

/// Stable local-data scope for multi-account isolation.
///
/// Production callers should pass an explicit scope captured at request start.
/// Do not default to a process-wide "current account" singleton for late writes.
class AccountScope {
  AccountScope._();

  static const unowned = 'unowned';

  /// Stable account bucket: [ForumAccountId.value].
  static String account(ForumAccountId id) => id.value;

  static String accountFrom({required Uri origin, required String uid}) =>
      ForumAccountId(origin: origin, uid: uid).value;

  /// Guest / signed-out browsing for one forum origin.
  static String guest(Uri origin) =>
      'guest:${ForumAccountId.normalizeOrigin(origin)}';

  static bool isGuest(String scope) => scope.startsWith('guest:');

  static bool isUnowned(String scope) => scope == unowned;

  /// Prefs key fragment helper (blocking, read positions, etc.).
  static String prefsSegment(String scope) => scope;
}
