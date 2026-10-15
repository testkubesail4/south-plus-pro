import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/forum_models.dart';
import 'forum_request_exception.dart';
import 'forum_block_content.dart';
import 'parsers/forum_response_parser.dart';

String? threadContentKey(ThreadReply reply) => reply.blockContentKey;

enum LocalBlockScope { topics, all }

enum FloorBlock { none, user, content }

class BlockedUser {
  const BlockedUser(
      {required this.uid,
      required this.name,
      required this.userBlocked,
      required this.avatarBlocked});

  final String uid;
  final String name;
  final bool userBlocked;
  final bool avatarBlocked;
}

class LocalBlockedUser {
  const LocalBlockedUser(
      {required this.uid, required this.name, required this.scope});

  final String uid;
  final String name;
  final LocalBlockScope scope;
}

class BlockingRules {
  const BlockingRules(
      {this.users = const [],
      this.localUsers = const [],
      this.contentKeys = const {}});

  final List<BlockedUser> users;
  final List<LocalBlockedUser> localUsers;
  final Set<String> contentKeys;

  bool isUserBlocked(String? uid, {bool topic = false}) =>
      uid != null &&
      (users.any((user) => user.uid == uid && user.userBlocked) ||
          localUsers.any((user) =>
              user.uid == uid && (topic || user.scope == LocalBlockScope.all)));

  bool isAvatarBlocked(String? uid) =>
      uid != null && users.any((user) => user.uid == uid && user.avatarBlocked);

  bool isContentBlocked(String? key) {
    if (key == null) return false;
    final normalized = matchableBlockContent(key);
    return contentKeys.any((term) => matchableBlockContent(term) == normalized);
  }

  bool isThreadBlocked(ForumThread thread) =>
      isUserBlocked(thread.authorUid, topic: true);

  FloorBlock floorBlock(
      {String? uid, required String? contentKey, bool isOpeningPost = false}) {
    if (isUserBlocked(uid)) return FloorBlock.user;
    if (!isOpeningPost && isContentBlocked(contentKey)) {
      return FloorBlock.content;
    }
    return FloorBlock.none;
  }
}

class ForumBlockingSettings {
  ForumBlockingSettings(
      {required String? Function() accountUid,
      required Future<String> Function(String, Map<String, String>) request})
      : _accountUid = accountUid,
        _request = request;

  final String? Function() _accountUid;
  final Future<String> Function(String, Map<String, String>) _request;
  final notifier = ValueNotifier<BlockingRules>(const BlockingRules());
  final _responseParser = const ForumResponseParser();
  String? _owner;
  int _generation = 0;
  Future<void> _queue = Future.value();
  Future<void>? _loadFuture;
  Map<String, dynamic>? _native;
  Map<String, dynamic>? _local;
  DateTime? nativeSyncedAt;

  bool get canWriteNative => _validUid(_accountUid());

  void reset() {
    _generation++;
    _owner = null;
    _native = null;
    _local = null;
    _loadFuture = null;
    nativeSyncedAt = null;
    notifier.value = const BlockingRules();
  }

  String? _syncOwner() {
    final uid = _accountUid();
    if (uid != _owner) {
      reset();
      _owner = uid;
    }
    return _validUid(uid) ? uid : null;
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  void _requireOwner(String owner, int generation) {
    if (_accountUid() != owner || generation != _generation) {
      throw const ForumRequestException(
          ForumRequestKind.loginRequired, '登录状态已改变，请重新打开屏蔽配置');
    }
  }

  Future<void> load({bool refresh = false}) {
    final owner = _syncOwner();
    if (owner == null) return Future.value();
    if (!refresh && _loadFuture != null) return _loadFuture!;
    final generation = _generation;
    return _loadFuture = _enqueue(() async {
      _requireOwner(owner, generation);
      final local = await _readLocal(owner);
      _requireOwner(owner, generation);
      _local = local;
      _publish();
      final config = await _readNative();
      _requireOwner(owner, generation);
      _native = config;
      nativeSyncedAt = DateTime.now();
      _publish();
    });
  }

  Future<String> _send(String action, Map<String, String> fields) async {
    try {
      final response = await _request(action, fields);
      if (response.trim().isEmpty || response.trim() == '{}')
        return response.trim();
      final payload = _responseParser.ajaxPayload(response) ??
          html_parser.parseFragment(response).querySelector('ajax')?.text;
      if (payload == null) {
        throw const ForumRequestException(
            ForumRequestKind.server, '屏蔽配置响应格式无效');
      }
      final decoded = html_parser.parseFragment(payload).text ?? '';
      if (decoded.trim().isEmpty && payload.trim().isNotEmpty) {
        throw const ForumRequestException(
            ForumRequestKind.server, '屏蔽配置响应格式无效');
      }
      return decoded;
    } on ForumRequestException {
      rethrow;
    } catch (_) {
      throw const ForumRequestException(
          ForumRequestKind.network, '屏蔽配置同步失败，请检查网络后重试');
    }
  }

  Map<String, dynamic> _newNativeConfig() => {
        'version': '3.1',
        'blist': <String, dynamic>{},
        'curiosity': false,
        'showBTN': true,
      };

  Future<Map<String, dynamic>> _readNative() async {
    final payload = await _send('getblocklist', const {});
    if (payload.trim().isEmpty) return _newNativeConfig();
    try {
      final config = jsonDecode(payload);
      if (config is Map<String, dynamic> && config.isEmpty)
        return _newNativeConfig();
      if (config is! Map<String, dynamic> ||
          config['version'] != '3.1' ||
          config['blist'] is! Map<String, dynamic>)
        throw const FormatException();
      for (final entry in (config['blist'] as Map<String, dynamic>).entries) {
        final user = entry.value;
        if (!_validUid(entry.key) ||
            user is! Map<String, dynamic> ||
            user['name'] is! String ||
            user['level'] is! List ||
            (user['level'] as List).any((level) => level is! String)) {
          throw const FormatException();
        }
      }
      return config;
    } catch (_) {
      throw const ForumRequestException(
          ForumRequestKind.server, '屏蔽配置格式或版本不受支持，原配置未修改');
    }
  }

  Future<void> setUser(
    String uid,
    String name, {
    required bool blocked,
    bool avatarOnly = false,
  }) {
    final owner = _syncOwner();
    if (owner == null) {
      return Future.error(const ForumRequestException(
          ForumRequestKind.loginRequired, '登录后可配置屏蔽规则'));
    }
    if (!_validUid(uid)) {
      return Future.error(const ForumRequestException(
          ForumRequestKind.invalidInput, '用户 UID 无效'));
    }
    final generation = _generation;
    return _enqueue(() async {
      _requireOwner(owner, generation);
      // Native updates submit the whole object: always merge a fresh read.
      final config = await _readNative();
      _requireOwner(owner, generation);
      final users = config['blist'] as Map<String, dynamic>;
      final entry = Map<String, dynamic>.from(
          users[uid] as Map? ?? {'name': name, 'level': <String>[]});
      final levels = List<String>.from(entry['level'] as List);
      final level = avatarOnly ? 'avatar' : 'topic';
      if (blocked) {
        if (!levels.contains(level)) levels.add(level);
        entry['name'] = name;
      } else {
        levels.removeWhere((value) => value == level);
      }
      if (levels.isEmpty) {
        users.remove(uid);
      } else {
        entry['level'] = levels;
        users[uid] = entry;
      }
      final result = await _send(
          'updateblocklist', {'blocklistconfig': jsonEncode(config)});
      _requireOwner(owner, generation);
      if (result != 'success') {
        throw const ForumRequestException(
            ForumRequestKind.server, '服务器未确认屏蔽配置保存成功，请刷新后重试');
      }
      _native = config;
      nativeSyncedAt = DateTime.now();
      _publish();
    });
  }

  Future<Map<String, dynamic>> _readLocal(String owner) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('blocking.local.$owner');
      if (raw == null) {
        return {
          'version': 1,
          'users': <String, dynamic>{},
          'content': <String>[]
        };
      }
      final config = jsonDecode(raw);
      if (config is! Map<String, dynamic> ||
          config['version'] != 1 ||
          config['users'] is! Map<String, dynamic> ||
          config['content'] is! List ||
          (config['content'] as List).any((value) => value is! String)) {
        throw const FormatException();
      }
      for (final user in (config['users'] as Map<String, dynamic>).entries) {
        if (!_validUid(user.key) ||
            user.value is! Map ||
            user.value['name'] is! String ||
            !LocalBlockScope.values
                .any((scope) => scope.name == user.value['scope'])) {
          throw const FormatException();
        }
      }
      return config;
    } catch (_) {
      throw const ForumRequestException(
          ForumRequestKind.server, '本机屏蔽配置无法读取，原配置未修改');
    }
  }

  Future<void> _editLocal(void Function(Map<String, dynamic>) edit) {
    final owner = _syncOwner();
    if (owner == null) {
      return Future.error(const ForumRequestException(
          ForumRequestKind.loginRequired, '登录后可配置屏蔽规则'));
    }
    final generation = _generation;
    return _enqueue(() async {
      final config = await _readLocal(owner);
      _requireOwner(owner, generation);
      edit(config);
      try {
        final prefs = await SharedPreferences.getInstance();
        _requireOwner(owner, generation);
        if (!await prefs.setString(
            'blocking.local.$owner', jsonEncode(config))) {
          throw const ForumRequestException(
              ForumRequestKind.server, '本机屏蔽配置保存失败');
        }
      } on ForumRequestException {
        rethrow;
      } catch (_) {
        throw const ForumRequestException(
            ForumRequestKind.server, '本机屏蔽配置保存失败');
      }
      _requireOwner(owner, generation);
      _local = config;
      _publish();
    });
  }

  Future<void> setContent(String key, {required bool blocked}) {
    key = key.trim();
    if (key.isEmpty || key.length > 2048) {
      return Future.error(const ForumRequestException(
          ForumRequestKind.invalidInput, '请选择可屏蔽的简短回复内容'));
    }
    return _editLocal((config) {
      final terms = List<String>.from(config['content'] as List);
      final normalized = matchableBlockContent(key);
      if (blocked) {
        if (!terms.any((term) => matchableBlockContent(term) == normalized)) {
          terms.add(key);
        }
      } else {
        terms.removeWhere((term) => matchableBlockContent(term) == normalized);
      }
      config['content'] = terms;
    });
  }

  Future<void> setLocalUser(String uid, String name,
      {required LocalBlockScope? scope}) {
    if (!_validUid(uid)) {
      return Future.error(const ForumRequestException(
          ForumRequestKind.invalidInput, '用户 UID 无效'));
    }
    return _editLocal((config) {
      final users = config['users'] as Map<String, dynamic>;
      if (scope == null) {
        users.remove(uid);
      } else {
        users[uid] = {'name': name, 'scope': scope.name};
      }
    });
  }

  void _publish() {
    final entries = (_native?['blist'] as Map<String, dynamic>?)?.entries ??
        const <MapEntry<String, dynamic>>[];
    final localEntries = (_local?['users'] as Map<String, dynamic>?)?.entries ??
        const <MapEntry<String, dynamic>>[];
    notifier.value = BlockingRules(
      contentKeys: Set.unmodifiable(
          List<String>.from(_local?['content'] as List? ?? const [])),
      localUsers:
          List.unmodifiable(localEntries.map((entry) => LocalBlockedUser(
                uid: entry.key,
                name: entry.value['name'] as String,
                scope: LocalBlockScope.values
                    .byName(entry.value['scope'] as String),
              ))),
      users: List.unmodifiable(entries.map((entry) {
        final user = entry.value as Map<String, dynamic>;
        final levels = user['level'] as List;
        return BlockedUser(
            uid: entry.key,
            name: user['name'] as String,
            userBlocked: levels.contains('topic'),
            avatarBlocked: levels.contains('avatar'));
      })),
    );
  }

  static bool _validUid(String? uid) =>
      uid != null && RegExp(r'^[1-9]\d*$').hasMatch(uid);
}
