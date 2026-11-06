/// Stable multi-account identity: normalized origin + forum uid.
/// Nickname / display name / login handle never form the id.
class ForumAccountId {
  ForumAccountId({required Uri origin, required String uid})
      : origin = normalizeOrigin(origin),
        uid = uid {
    if (!isValidUid(uid)) {
      throw FormatException('Invalid forum uid', uid);
    }
  }

  static const separator = '';
  static final _uidPattern = RegExp(r'^[1-9]\d*$');

  /// Scheme + host (+ non-default port), host lowercased.
  final Uri origin;

  /// Forum numeric uid.
  final String uid;

  /// Storage form used as prefs key fragment and registry id.
  String get value => '${origin}$separator$uid';

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is ForumAccountId && other.origin == origin && other.uid == uid;

  @override
  int get hashCode => Object.hash(origin, uid);

  static ForumAccountId parse(String value) {
    final parsed = tryParse(value);
    if (parsed == null) {
      throw FormatException('Invalid forum account id', value);
    }
    return parsed;
  }

  static ForumAccountId? tryParse(String value) {
    final sep = value.indexOf(separator);
    if (sep <= 0 || sep >= value.length - 1) return null;
    final originRaw = value.substring(0, sep);
    final uid = value.substring(sep + separator.length);
    if (!_uidPattern.hasMatch(uid)) return null;
    final origin = Uri.tryParse(originRaw);
    if (origin == null || origin.host.isEmpty) return null;
    if (originRaw != normalizeOrigin(origin).toString()) return null;
    return ForumAccountId(origin: normalizeOrigin(origin), uid: uid);
  }

  /// Same canonical origin ForumClient uses (`baseUri.origin`, host lowercased).
  static Uri normalizeOrigin(Uri origin) {
    final host = origin.host.toLowerCase();
    if (host.isEmpty) {
      throw FormatException('Origin host required', origin.toString());
    }
    final scheme =
        origin.scheme.isEmpty ? 'https' : origin.scheme.toLowerCase();
    final defaultPort = scheme == 'https'
        ? 443
        : scheme == 'http'
            ? 80
            : null;
    final port =
        origin.hasPort && origin.port != defaultPort ? origin.port : null;
    return Uri(
      scheme: scheme,
      host: host,
      port: port,
    );
  }

  static bool isValidUid(String uid) => _uidPattern.hasMatch(uid);
}
