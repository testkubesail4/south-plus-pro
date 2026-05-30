import 'dart:convert';

import '../models/forum_models.dart';
import 'forum_url_resolver.dart';
import 'local_database.dart';

class UserProfileCache {
  UserProfileCache({
    ForumUrlResolver? urls,
    Duration? maxAge,
    Future<LocalDatabase> Function()? databaseProvider,
  })  : urls = urls ?? ForumUrlResolver(),
        maxAge = maxAge ?? const Duration(days: 7),
        _databaseProvider = databaseProvider ?? LocalDatabase.instance;

  static const _keyPrefix = 'profile_overview_v1:';

  final ForumUrlResolver urls;
  final Duration maxAge;
  final Future<LocalDatabase> Function() _databaseProvider;

  Future<UserProfile?> loadOverview(String url) async {
    final db = await _databaseProvider();
    final cached = db.profileOverview(_cacheKey(url));
    if (cached == null || cached.payloadJson.isEmpty) return null;
    final decoded = jsonDecode(cached.payloadJson);
    if (decoded is! Map<String, dynamic>) return null;
    if (DateTime.now().toUtc().difference(cached.cachedAt) > maxAge) {
      return null;
    }
    return _overviewFromCache(decoded);
  }

  Future<void> saveOverview(String requestedUrl, UserProfile profile) async {
    final db = await _databaseProvider();
    final keys = {
      _cacheKey(requestedUrl),
      _cacheKey(profile.url),
      _cacheKey(urls.userTabUrl(profile.uid, UserProfileTab.profile)),
    };
    db.saveProfileOverview(
      cacheKeys: keys,
      profileUrl: profile.url,
      uid: profile.uid,
      payloadJson: jsonEncode(_overviewToCache(profile)),
      cachedAt: DateTime.now().toUtc(),
    );
  }

  String _cacheKey(String url) {
    return '$_keyPrefix${urls.absoluteUrl(url)}';
  }

  Map<String, dynamic> _overviewToCache(UserProfile profile) {
    return <String, dynamic>{
      'uid': profile.uid,
      'name': profile.name,
      'url': profile.url,
      'tagline': profile.tagline,
      'avatarUrl': profile.avatarUrl,
      'level': profile.level,
      'isOnline': profile.isOnline,
      'statusText': profile.statusText,
      'messageUrl': profile.messageUrl,
      'signature': profile.signature,
      'info': profile.info.map(_fieldToCache).toList(),
      'stats': profile.stats.map(_fieldToCache).toList(),
    };
  }

  Map<String, dynamic> _fieldToCache(UserProfileField field) {
    return <String, dynamic>{
      'label': field.label,
      'value': field.value,
    };
  }

  UserProfile? _overviewFromCache(Map<String, dynamic> cache) {
    final uid = cache['uid'];
    final name = cache['name'];
    final url = cache['url'];
    if (uid is! String ||
        uid.isEmpty ||
        name is! String ||
        name.isEmpty ||
        url is! String) {
      return null;
    }
    return UserProfile(
      uid: uid,
      name: name,
      url: url,
      tagline: cache['tagline'] is String ? cache['tagline'] as String : null,
      avatarUrl:
          cache['avatarUrl'] is String ? cache['avatarUrl'] as String : null,
      level: cache['level'] is String ? cache['level'] as String : null,
      isOnline: cache['isOnline'] is bool ? cache['isOnline'] as bool : null,
      statusText:
          cache['statusText'] is String ? cache['statusText'] as String : null,
      messageUrl:
          cache['messageUrl'] is String ? cache['messageUrl'] as String : null,
      signature:
          cache['signature'] is String ? cache['signature'] as String : null,
      info: _fieldsFromCache(cache['info']),
      stats: _fieldsFromCache(cache['stats']),
    );
  }

  List<UserProfileField> _fieldsFromCache(Object? fields) {
    if (fields is! List) return const [];
    return fields
        .whereType<Map<String, dynamic>>()
        .map((field) {
          final label = field['label'];
          final value = field['value'];
          if (label is! String || value is! String) return null;
          return UserProfileField(label: label, value: value);
        })
        .whereType<UserProfileField>()
        .toList();
  }
}
