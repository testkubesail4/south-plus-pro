import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/forum_models.dart';
import 'forum_search_preferences.dart';
import 'forum_url_resolver.dart';
import 'local_state_preferences.dart';

class HomeReadingPreferences {
  const HomeReadingPreferences({
    this.quickRowCount = 8,
    this.collapsedIds = const {},
    this.recentBoards = const [],
    this.sectionOrder = const [],
    this.hiddenSectionIds = const {},
    this.hiddenParentFids = const {},
    this.sectionTitlesById = const {},
  });

  final int quickRowCount;
  final Set<String> collapsedIds;
  final List<ForumSearchPinnedBoard> recentBoards;
  final List<String> sectionOrder;
  final Set<String> hiddenSectionIds;
  final Set<String> hiddenParentFids;
  final Map<String, String> sectionTitlesById;

  HomeReadingPreferences copyWith({
    int? quickRowCount,
    Set<String>? collapsedIds,
    List<ForumSearchPinnedBoard>? recentBoards,
    List<String>? sectionOrder,
    Set<String>? hiddenSectionIds,
    Set<String>? hiddenParentFids,
    Map<String, String>? sectionTitlesById,
  }) => HomeReadingPreferences(
    quickRowCount: quickRowCount ?? this.quickRowCount,
    collapsedIds: Set.unmodifiable(collapsedIds ?? this.collapsedIds),
    recentBoards: List.unmodifiable(recentBoards ?? this.recentBoards),
    sectionOrder: List.unmodifiable(sectionOrder ?? this.sectionOrder),
    hiddenSectionIds: Set.unmodifiable(hiddenSectionIds ?? this.hiddenSectionIds),
    hiddenParentFids: Set.unmodifiable(hiddenParentFids ?? this.hiddenParentFids),
    sectionTitlesById: Map.unmodifiable(sectionTitlesById ?? this.sectionTitlesById),
  );

  static const maxRecentBoards = 8;
  static final revision = ValueNotifier<int>(0);
  static final _fid = RegExp(r'^[1-9]\d*$');
  static final _urls = ForumUrlResolver();
  static const _rowsKey = 'home_quick_rows_v1';
  static const _collapsedKey = 'home_collapsed_ids_v1';
  static const _recentKey = 'home_recent_boards_v1';
  static const _layoutKey = 'home_layout_v2';

  static String _key(String key, String? account) =>
      account == null || account.isEmpty
          ? 'anonymous/$key'
          : 'account/${Uri.encodeComponent(account)}/$key';

  static bool _validSectionId(String id) =>
      (id.startsWith('section-id:') && _fid.hasMatch(id.substring(11))) ||
      (id.startsWith('section:') && id.substring(8).trim().isNotEmpty);

  static bool _validCollapsedId(String id) => _validSectionId(id) ||
      (id.startsWith('board:') && _fid.hasMatch(id.substring(6)));

  static Set<String> _strings(Object? raw, bool Function(String) valid) => {
    if (raw is List)
      for (final id in raw)
        if (id is String && valid(id)) id,
  };

  static HomeReadingPreferences _layout(SharedPreferences prefs, String? account) {
    final key = _key(_layoutKey, account);
    if (!prefs.containsKey(key)) {
      return HomeReadingPreferences(collapsedIds: _strings(
        prefs.get(_key(_collapsedKey, account)), _validCollapsedId));
    }
    final raw = prefs.get(key);
    if (raw is! String) return const HomeReadingPreferences();
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return const HomeReadingPreferences();
      final titles = data['sectionTitlesById'];
      return HomeReadingPreferences(
        sectionOrder: _strings(data['sectionOrder'], _validSectionId).toList(),
        hiddenSectionIds: _strings(data['hiddenSectionIds'], _validSectionId),
        hiddenParentFids: _strings(data['hiddenParentFids'], _fid.hasMatch),
        collapsedIds: _strings(data['collapsedIds'], _validCollapsedId),
        sectionTitlesById: {
          if (titles is Map)
            for (final entry in titles.entries)
              if (entry.key is String &&
                  (entry.key as String).startsWith('section-id:') &&
                  _validSectionId(entry.key as String) &&
                  entry.value is String && (entry.value as String).trim().isNotEmpty)
                entry.key as String: (entry.value as String).trim(),
        },
      );
    } on FormatException {
      return const HomeReadingPreferences();
    }
  }

  String? sectionId(ForumSection section, List<ForumSection> sections) {
    final native = section.nativeId;
    if (native != null && _fid.hasMatch(native)) {
      return sections.where((s) => s.nativeId == native).length == 1
          ? 'section-id:$native' : null;
    }
    final title = section.title.trim();
    if (title.isEmpty || sections.where((s) => s.title.trim() == title).length != 1) {
      return null;
    }
    final matches = sectionTitlesById.entries.where((e) => e.value == title).toList();
    if (matches.length > 1) return null;
    return matches.isEmpty ? 'section:$title' : matches.single.key;
  }

  HomeReadingPreferences reconcile(List<ForumSection> sections) {
    final titles = Map<String, String>.of(sectionTitlesById);
    final replacements = <String, String>{};
    for (final section in sections) {
      final id = sectionId(section, sections);
      if (id == null || !id.startsWith('section-id:')) continue;
      final title = section.title.trim();
      titles[id] = title;
      if (sections.where((s) => s.title.trim() == title).length == 1) {
        replacements['section:$title'] = id;
      }
    }
    Set<String> migrate(Iterable<String> ids) => {
      for (final id in ids) replacements[id] ?? id,
    };
    return copyWith(
      sectionOrder: migrate(sectionOrder).toList(),
      hiddenSectionIds: migrate(hiddenSectionIds),
      collapsedIds: migrate(collapsedIds),
      sectionTitlesById: titles,
    );
  }

  List<ForumSection> orderedSections(List<ForumSection> sections) {
    final remaining = List<ForumSection>.of(sections);
    final ordered = <ForumSection>[];
    for (final id in sectionOrder) {
      final index = remaining.indexWhere((s) => sectionId(s, sections) == id);
      if (index >= 0) ordered.add(remaining.removeAt(index));
    }
    return [...ordered, ...remaining];
  }

  static Map<String, Object> _encode(HomeReadingPreferences state) => {
    'sectionOrder': state.sectionOrder,
    'hiddenSectionIds': state.hiddenSectionIds.toList(),
    'hiddenParentFids': state.hiddenParentFids.toList(),
    'collapsedIds': state.collapsedIds.toList(),
    'sectionTitlesById': state.sectionTitlesById,
  };

  static Future<void> _updateLayout(
    HomeReadingPreferences Function(HomeReadingPreferences) update, {
    String? account, List<ForumSection> sections = const [],
  }) async {
    await LocalStatePreferences.write((prefs) {
      final state = _layout(prefs, account).reconcile(sections);
      return prefs.setString(_key(_layoutKey, account), jsonEncode(_encode(update(state))));
    });
    revision.value++;
  }

  static Future<void> saveSectionOrder(List<String> ids, {
    String? account, List<ForumSection> sections = const [],
  }) async {
    if (ids.any((id) => !_validSectionId(id)) || ids.toSet().length != ids.length) {
      throw ArgumentError.value(ids, 'ids');
    }
    return _updateLayout((s) => s.copyWith(sectionOrder: [
      ...ids, ...s.sectionOrder.where((id) => !ids.contains(id)),
    ]), account: account, sections: sections);
  }

  static Future<void> setSectionHidden(String id, bool hidden, {
    String? account, List<ForumSection> sections = const [],
  }) async {
    if (!_validSectionId(id)) throw ArgumentError.value(id, 'id');
    return _updateLayout((s) => s.copyWith(hiddenSectionIds: {
      ...s.hiddenSectionIds.where((other) => other != id), if (hidden) id,
    }), account: account, sections: sections);
  }

  static Future<void> setParentHidden(String fid, bool hidden, {
    String? account, List<ForumSection> sections = const [],
  }) async {
    if (!_fid.hasMatch(fid)) throw ArgumentError.value(fid, 'fid');
    return _updateLayout((s) => s.copyWith(hiddenParentFids: {
      ...s.hiddenParentFids.where((other) => other != fid), if (hidden) fid,
    }), account: account, sections: sections);
  }

  static Future<void> restoreLayout({String? account}) => _updateLayout(
    (s) => s.copyWith(sectionOrder: [], hiddenSectionIds: {}, hiddenParentFids: {}),
    account: account,
  );

  static List<ForumSearchPinnedBoard> _recent(SharedPreferences prefs, String? account) {
    final raw = prefs.get(_key(_recentKey, account));
    if (raw is! String) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final result = <ForumSearchPinnedBoard>[];
      final seen = <String>{};
      for (final item in decoded) {
        if (item is! Map) continue;
        final id = item['id'];
        final label = item['label'];
        if (id is! String || !_fid.hasMatch(id) || label is! String ||
            label.trim().isEmpty || !seen.add(id)) continue;
        result.add(ForumSearchPinnedBoard(id: id, label: label.trim()));
        if (result.length == maxRecentBoards) break;
      }
      return result;
    } on FormatException { return []; }
  }

  static Future<HomeReadingPreferences> load({String? account}) =>
      LocalStatePreferences.read((prefs) {
        final rows = prefs.get(_key(_rowsKey, account));
        return _layout(prefs, account).copyWith(
          quickRowCount: rows is int && rows >= 3 && rows <= 8 ? rows : 8,
          recentBoards: _recent(prefs, account),
        );
      });

  static Future<void> saveQuickRowCount(int rows, {String? account}) async {
    if (rows < 3 || rows > 8) throw ArgumentError.value(rows, 'rows');
    await LocalStatePreferences.write((prefs) => prefs.setInt(_key(_rowsKey, account), rows));
    revision.value++;
  }

  static Future<void> setCollapsed(String stableId, bool collapsed, {
    String? account, List<ForumSection> sections = const [],
  }) async {
    if (!_validCollapsedId(stableId)) throw ArgumentError.value(stableId, 'stableId');
    return _updateLayout((s) => s.copyWith(collapsedIds: {
      ...s.collapsedIds.where((id) => id != stableId), if (collapsed) stableId,
    }), account: account, sections: sections);
  }

  static Future<void> recordBoardVisit(ForumCategory category, {String? account, String? label}) async {
    final id = _urls.fidFromCategory(category);
    final ownLabel = category.name.trim();
    if (id == null || !_fid.hasMatch(id) || ownLabel.isEmpty) return;
    await LocalStatePreferences.write((prefs) {
      final previous = _recent(prefs, account);
      final known = previous.where((board) => board.id == id).firstOrNull?.label;
      final displayLabel = (label?.trim().isNotEmpty ?? false)
          ? label!.trim()
          : known != null && known.contains(' / ') ? known : ownLabel;
      final boards = [
        ForumSearchPinnedBoard(id: id, label: displayLabel),
        ...previous.where((board) => board.id != id),
      ].take(maxRecentBoards);
      return prefs.setString(_key(_recentKey, account), jsonEncode([
        for (final board in boards) {'id': board.id, 'label': board.label},
      ]));
    });
    revision.value++;
  }

  static Future<void> clearRecentBoards({String? account}) async {
    await LocalStatePreferences.write((prefs) => prefs.remove(_key(_recentKey, account)));
    revision.value++;
  }
}
