import 'forum_account_id.dart';

/// Slot id forms for multi-account cookie jars.
class ForumSessionSlots {
  ForumSessionSlots._();

  static String origin(Uri origin) =>
      'origin:${ForumAccountId.normalizeOrigin(origin).host}';

  static String account(String accountId) {
    ForumAccountId.parse(accountId);
    return accountId;
  }

  static String staging(Uri origin, String nonce) {
    final host = ForumAccountId.normalizeOrigin(origin).host;
    if (nonce.isEmpty || nonce.contains(':')) {
      throw FormatException('Invalid staging nonce', nonce);
    }
    return 'staging:$host:$nonce';
  }

  static bool isStaging(String slotId) => slotId.startsWith('staging:');

  static bool isOrigin(String slotId) => slotId.startsWith('origin:');

  static bool isAccount(String slotId) =>
      !isStaging(slotId) && !isOrigin(slotId);

  /// Prefs key for a persistable slot, or null when memory-only (staging).
  static String? cookiesPrefsKey(String slotId, {Uri? origin}) {
    if (isStaging(slotId)) return null;
    if (isOrigin(slotId)) {
      final host = slotId.substring('origin:'.length);
      return 'forum_session_cookies_v2:${host.toLowerCase()}';
    }
    ForumAccountId.parse(slotId);
    return 'forum_session_cookies_v3:$slotId';
  }
}
