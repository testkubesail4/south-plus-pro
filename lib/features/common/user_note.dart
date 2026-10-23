import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/forum_repository.dart';
import '../../services/user_note_store.dart';
import '../../services/tag_color_store.dart';
import '../../services/tag_vocabulary.dart';
import '../../services/user_display_name_store.dart';
import '../../services/user_tag_store.dart';
import '../../theme/app_theme.dart';
import 'user_tags_inline.dart';

const userNoteMaxLength = 40;

/// Local, per-scope UID notes for one screen. Notes only show for the storage
/// scope they were loaded for; any scope change clears them at once and
/// reloads after the repository finished its (possibly multi-step) switch.
class UserNoteController extends ChangeNotifier {
  UserNoteController(this.repository) {
    UserNoteStore.revision.addListener(reload);
    UserTagStore.revision.addListener(reload);
    TagColorStore.revision.addListener(reload);
    UserDisplayNameStore.revision.addListener(reload);
    // The epoch moves before the final user/config is set, the user moves
    // after: observe both, and reload from a microtask so the scope is final.
    repository.sessionEpoch.addListener(_onScopeChange);
    repository.sessionUser.addListener(_onScopeChange);
    reload();
  }

  final ForumRepository repository;
  Map<String, String> _notes = const {};
  Map<String, List<String>> _tags = const {};
  // Names learned from the forum; a missing or unreadable one shows the UID.
  Map<String, UserDisplayName> _names = const {};
  Map<String, String> _tagColors = const {};
  Object? noteLoadError;
  Object? tagLoadError;
  bool isLoading = true;
  bool _hasTagsLoaded = false;
  // The scope _notes belongs to; null until the first load completes.
  String? _loadedScope;
  bool _hasLoaded = false;
  int _generation = 0;
  bool _disposed = false;

  String? noteFor(String? uid) {
    if (uid == null || !_hasLoaded) return null;
    return _loadedScope == repository.localPreferenceAccount
        ? _notes[uid]
        : null;
  }

  Map<String, String> get notes =>
      _loadedScope == repository.localPreferenceAccount && _hasLoaded
          ? _notes
          : const {};
  Map<String, List<String>> get tags =>
      _loadedScope == repository.localPreferenceAccount && _hasTagsLoaded
          ? _tags
          : const {};

  List<String> tagsFor(String? uid) =>
      uid == null ? const [] : tags[uid] ?? const [];

  /// Normalized tag label → colour id, for a [TagColorScope].
  Map<String, String> get tagColors =>
      _loadedScope == repository.localPreferenceAccount ? _tagColors : const {};

  /// The learned forum names for [uid] in the loaded scope, if any.
  UserDisplayName? namesFor(String? uid) =>
      uid == null || _loadedScope != repository.localPreferenceAccount
          ? null
          : _names[uid];

  void _onScopeChange() {
    _generation++;
    _notes = const {};
    _tags = const {};
    _names = const {};
    _tagColors = const {};
    _hasLoaded = false;
    _hasTagsLoaded = false;
    noteLoadError = null;
    tagLoadError = null;
    isLoading = true;
    notifyListeners();
    scheduleMicrotask(reload);
  }

  Future<void> reload() async {
    if (_disposed) return;
    final generation = ++_generation;
    final scope = repository.localPreferenceAccount;
    isLoading = true;
    notifyListeners();
    Map<String, String>? loadedNotes;
    Map<String, List<String>>? loadedTags;
    Object? noteError;
    Object? tagError;
    try {
      loadedNotes = await UserNoteStore.load(account: scope);
    } catch (error) {
      noteError = error;
    }
    try {
      loadedTags = await UserTagStore.load(account: scope);
    } catch (error) {
      tagError = error;
    }
    Map<String, UserDisplayName>? loadedNames;
    try {
      loadedNames = await UserDisplayNameStore.load(account: scope);
    } catch (_) {
      // Names only label rows; without them the UID shows.
    }
    Map<String, String>? loadedColors;
    try {
      loadedColors = await TagColorStore.load(account: scope);
    } catch (_) {
      // Colours only decorate tags; without them they stay neutral.
    }
    if (_disposed || generation != _generation) return;
    if (scope != repository.localPreferenceAccount) return reload();
    if (loadedNotes != null) {
      _notes = loadedNotes;
      _hasLoaded = true;
    }
    if (loadedTags != null) {
      _tags = loadedTags;
      _hasTagsLoaded = true;
    }
    _names = loadedNames ?? const {};
    _tagColors = loadedColors ?? const {};
    _loadedScope = scope;
    noteLoadError = noteError;
    tagLoadError = tagError;
    isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    UserNoteStore.revision.removeListener(reload);
    UserTagStore.revision.removeListener(reload);
    TagColorStore.revision.removeListener(reload);
    UserDisplayNameStore.revision.removeListener(reload);
    repository.sessionEpoch.removeListener(_onScopeChange);
    repository.sessionUser.removeListener(_onScopeChange);
    super.dispose();
  }
}

/// Opens the note editor; true when a note was saved or cleared.
Future<bool> showUserNoteEditor(
  BuildContext context, {
  required ForumRepository repository,
  required String uid,
  // The real name when one is known; null shows the UID alone.
  required String? name,
  String? note,
  List<String> tags = const [],
  // Offered only while nothing is unsaved; the sheet closes first.
  VoidCallback? onOpenProfile,
  // Names the forum itself showed for this UID (a floor's author link, a
  // loaded profile), remembered once an annotation is saved. Never a
  // placeholder or fallback.
  String? learnNickname,
  String? learnHashName,
}) async {
  // Captured now, not in the deferred builder: a switch before the first
  // frame must blank the sheet instead of re-binding it to the new scope.
  final account = repository.localPreferenceAccount;
  final epoch = repository.sessionEpoch.value;
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: AppWidths.sheet),
    builder: (_) => _UserNoteSheet(
      repository: repository,
      account: account,
      epoch: epoch,
      uid: uid,
      name: name,
      note: note,
      tags: tags,
      onOpenProfile: onOpenProfile,
      learnNickname: learnNickname,
      learnHashName: learnHashName,
    ),
  );
  return saved ?? false;
}

class _UserNoteSheet extends StatefulWidget {
  const _UserNoteSheet({
    required this.repository,
    required this.account,
    required this.epoch,
    required this.uid,
    required this.name,
    required this.note,
    required this.tags,
    this.onOpenProfile,
    this.learnNickname,
    this.learnHashName,
  });

  final VoidCallback? onOpenProfile;
  final String? learnNickname;
  final String? learnHashName;
  final ForumRepository repository;
  // Captured when the sheet opened; a write never lands in another account.
  final String? account;
  final int epoch;
  final String uid;
  final String? name;
  final String? note;
  final List<String> tags;

  @override
  State<_UserNoteSheet> createState() => _UserNoteSheetState();
}

class _UserNoteSheetState extends State<_UserNoteSheet> {
  late final _controller = TextEditingController(text: widget.note);
  final _tagController = TextEditingController();
  late List<String> _tags = List.of(widget.tags);
  late List<String> _savedTags = List.of(widget.tags);
  late String _savedNote = (widget.note ?? '').trim();
  bool _addingTag = false;
  bool _hasWritten = false;
  bool _noteSaved = false;
  bool _busy = false;
  String? _error;
  String? _tagError;
  // The scope changed under the open sheet: its text and the note it was
  // opened for no longer belong on screen.
  bool _revoked = false;
  ModalRoute<Object?>? _route;
  // Every tag in the captured account, for picking; never written from here.
  Map<String, List<String>>? _vocabulary;
  bool _vocabularyFailed = false;
  // The store revision the vocabulary was read at; a later write makes it
  // stale for resolving new labels.
  int? _vocabularyRevision;
  bool _resolving = false;
  // Label colours of the captured account; written at once, apart from 保存.
  Map<String, String> _colors = const {};
  String? _colorError;

  @override
  void initState() {
    super.initState();
    _loadVocabulary();
    _loadColors();
    TagColorStore.revision.addListener(_loadColors);
    // The epoch moves before the final user/origin is set and the user moves
    // after it, so any change of either revokes the sheet.
    widget.repository.sessionEpoch.addListener(_revoke);
    widget.repository.sessionUser.addListener(_revoke);
    final repository = widget.repository;
    if (repository.sessionEpoch.value != widget.epoch ||
        repository.localPreferenceAccount != widget.account) {
      // Already stale when first built.
      _revoked = true;
      _controller.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) => _removeOwnRoute());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  Future<void> _loadColors() async {
    try {
      final colors = await TagColorStore.load(account: widget.account);
      if (_current) setState(() => _colors = colors);
    } catch (_) {
      // Without colours the chips stay neutral.
    }
  }

  String? _colorOf(String tag) {
    try {
      return _colors[TagColorStore.key(tag)];
    } on ArgumentError {
      return null;
    }
  }

  /// A label's colour is the account's, for every user with that tag, so it
  /// is saved at once rather than with this user's draft.
  Future<void> _pickColor(String tag) async {
    final current = _colorOf(tag);
    final picked =
        await showTagColorPicker(context, tag: tag, current: current);
    if (picked == null || !_current || picked == (current ?? '')) return;
    try {
      await TagColorStore.save(tag, picked.isEmpty ? null : picked,
          account: widget.account);
      if (_current) setState(() => _colorError = null);
    } catch (_) {
      if (_current) setState(() => _colorError = '颜色未保存，请重试');
    }
  }

  @override
  void dispose() {
    TagColorStore.revision.removeListener(_loadColors);
    widget.repository.sessionEpoch.removeListener(_revoke);
    widget.repository.sessionUser.removeListener(_revoke);
    _controller.dispose();
    _tagController.dispose();
    super.dispose();
  }

  // Blank at once, then remove only this sheet's route; routes above or below
  // it stay.
  void _revoke() {
    if (_revoked || !mounted) return;
    _controller.clear();
    _tagController.clear();
    _tags = [];
    setState(() => _revoked = true);
    _removeOwnRoute();
  }

  // Read once, from the scope the sheet was opened for; a later scope change
  // revokes the sheet, so another account's words never show here.
  Future<void> _loadVocabulary() async {
    // A write that lands while reading makes the result older than the
    // revision it ends at: read again rather than mark it fresh.
    for (var attempt = 0; attempt < 3; attempt++) {
      final revision = UserTagStore.revision.value;
      try {
        final all = await UserTagStore.load(account: widget.account);
        if (!_current) return;
        if (revision != UserTagStore.revision.value) continue;
        setState(() {
          _vocabulary = all;
          _vocabularyRevision = revision;
          _vocabularyFailed = false;
        });
        return;
      } catch (_) {
        if (_current) setState(() => _vocabularyFailed = true);
        return;
      }
    }
    if (_current) setState(() => _vocabularyFailed = true);
  }

  /// A source a new label may be resolved against: the loaded snapshot while
  /// the store has not moved since, otherwise a fresh read of the same scope.
  Future<bool> _currentVocabulary() async {
    if (_vocabulary != null &&
        !_vocabularyFailed &&
        _vocabularyRevision == UserTagStore.revision.value) {
      return true;
    }
    await _loadVocabulary();
    return _current && _vocabulary != null && !_vocabularyFailed;
  }

  static const _unreadable = '已有标签暂时无法读取，请重试';

  void _removeOwnRoute() {
    final route = _route;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  bool get _current =>
      mounted &&
      !_revoked &&
      widget.account == widget.repository.localPreferenceAccount &&
      widget.epoch == widget.repository.sessionEpoch.value;

  // A typed, unadded tag counts too, in its stored spelling when it has one.
  List<String> _draftTags() => UserTagStore.normalize([
        ..._tags,
        if (_addingTag && _tagController.text.trim().isNotEmpty)
          _storedSpelling(_tagController.text) ?? _tagController.text,
      ]);

  String? get _visibleTagError {
    if (_tagError == null) return null;
    try {
      if (listEquals(_draftTags(), _savedTags)) return null;
    } on ArgumentError {/* Invalid drafts still show their validation error. */}
    return _tagError!.startsWith('备注已保存；') &&
            _controller.text.trim() != _savedNote
        ? '标签未保存，请重试'
        : _tagError;
  }

  /// Both drafts equal what the store acknowledged: leaving loses nothing.
  bool get _clean {
    try {
      return _controller.text.trim() == _savedNote &&
          listEquals(_draftTags(), _savedTags);
    } on ArgumentError {
      return false;
    }
  }

  void _openProfile() {
    final open = widget.onOpenProfile;
    final route = _route;
    if (open == null || _busy || !_clean || !_current) return;
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      route.navigator?.pop(_hasWritten);
    } else {
      route.navigator?.removeRoute(route);
    }
    open();
  }

  /// The stored spelling of [text] in this account's vocabulary, if any.
  String? _storedSpelling(String text) {
    final key = text.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final entry in tagVocabulary(_vocabulary ?? const {}, query: text)) {
      if (entry.label.toLowerCase() == key) return entry.label;
    }
    return null;
  }

  /// Adds the typed tag, in its stored spelling when the account already has
  /// it, so one word never splits by letter case. The field stays open for
  /// the next pick.
  ///
  /// Every add, picked or typed, is resolved against a current source (the
  /// snapshot while the store has not moved, else a fresh read); without one
  /// nothing is added and the text stays.
  Future<void> _addTag([String? picked]) async {
    if (_resolving) return;
    // What the field held when this add began; text typed while the source
    // is read is the user's next query and is left alone.
    final query = _tagController.text;
    final typed = picked ?? query;
    if (typed.trim().isEmpty) return;
    setState(() => _resolving = true);
    final ok = await _currentVocabulary();
    if (!_current) return;
    setState(() => _resolving = false);
    if (!ok) {
      setState(() => _tagError = _unreadable);
      return;
    }
    final label = _storedSpelling(typed) ?? typed;
    try {
      final tags = UserTagStore.normalize([..._tags, label]);
      setState(() {
        _tags = tags;
        if (_tagController.text == query) _tagController.clear();
        _tagError = null;
        if (tags.length >= UserTagStore.maxTags) _addingTag = false;
      });
    } on ArgumentError catch (error) {
      setState(() => _tagError = error.message.toString());
    }
  }

  /// Tags already used in this account, best matches first, without the ones
  /// this user has. Picking only edits this user's draft.
  Widget _suggestions(ThemeData theme) {
    final vocabulary = _vocabulary;
    final muted = theme.textTheme.bodySmall;
    if (_vocabularyFailed) {
      return Text('已有标签暂时无法读取', style: muted);
    }
    if (vocabulary == null) return const SizedBox.shrink();
    final query = _tagController.text.trim();
    final tooLong = query.runes.length > UserTagStore.maxTagRunes;
    final entries = tagVocabulary(vocabulary, query: query, exclude: _tags)
        .take(12)
        .toList();
    final onUser = _tags.any((t) => t.toLowerCase() == query.toLowerCase());
    final offerNew = query.isNotEmpty &&
        !tooLong &&
        !onUser &&
        _storedSpelling(query) == null;
    if (tooLong) {
      return Text('最多 ${UserTagStore.maxTagRunes} 个字符，这个标签太长',
          key: const ValueKey('user-tag-too-long'),
          style: muted?.copyWith(color: theme.colorScheme.error));
    }
    if (!offerNew && entries.isEmpty) return const SizedBox.shrink();
    final chipStyle =
        theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted);
    return Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
      if (offerNew)
        ActionChip(
          key: const ValueKey('tag-suggestion-new'),
          label: Text('新建「$query」'),
          labelStyle:
              theme.textTheme.bodySmall?.copyWith(color: AppColors.brand),
          backgroundColor: AppColors.surface,
          side: BorderSide(color: AppColors.brand.withValues(alpha: 0.35)),
          shape: const StadiumBorder(),
          visualDensity: VisualDensity.compact,
          onPressed: _busy || _resolving ? null : () => _addTag(query),
        ),
      for (final entry in entries)
        ActionChip(
          key: ValueKey('tag-suggestion:${entry.label}'),
          tooltip: '${entry.userCount} 位用户使用',
          label: Text('${entry.label} · ${entry.userCount}'),
          labelStyle: chipStyle,
          backgroundColor: AppColors.inkSoft,
          side: BorderSide.none,
          shape: const StadiumBorder(),
          visualDensity: VisualDensity.compact,
          onPressed: _busy || _resolving ? null : () => _addTag(entry.label),
        ),
    ]);
  }

  /// Remembers the forum's names for this UID after an annotation write was
  /// acknowledged. Best effort: it never delays, fails or changes that result.
  void _learnName() {
    // The captured scope only, whether or not the sheet is still shown.
    if (_revoked ||
        widget.account != widget.repository.localPreferenceAccount ||
        widget.epoch != widget.repository.sessionEpoch.value) {
      return;
    }
    String? clean(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    final nickname = clean(widget.learnNickname);
    final hashName = clean(widget.learnHashName);
    if (nickname == null && hashName == null) return;
    UserDisplayNameStore.save(widget.uid,
            nickname: nickname, hashName: hashName, account: widget.account)
        .then((_) {}, onError: (Object _) {});
  }

  Future<void> _write(String text) async {
    if (!_current || _busy || _resolving) return;
    // Pending tag text is a new assignment too: resolve its spelling first.
    // The whole save, this read included, locks the fields, so nothing typed
    // after 保存 can be lost when it completes.
    if (_addingTag && _tagController.text.trim().isNotEmpty) {
      setState(() => _busy = true);
      final ok = await _currentVocabulary();
      if (!_current) return;
      if (!ok) {
        setState(() {
          _busy = false;
          _tagError = _unreadable;
        });
        return;
      }
    }
    final note = text.trim();
    List<String> tags;
    try {
      tags = _draftTags();
    } on ArgumentError catch (error) {
      setState(() {
        _busy = false;
        _tagError = error.message.toString();
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _tagError = null;
      _tags = tags;
      _tagController.clear();
      _addingTag = false;
    });
    var savingTags = false;
    try {
      if (note != _savedNote) {
        await UserNoteStore.save(widget.uid, note, account: widget.account);
        if (!_current) return;
        setState(() {
          _savedNote = note;
          _noteSaved = true;
          _hasWritten = true;
        });
      }
      if (!_current) return;
      savingTags = true;
      if (!listEquals(tags, _savedTags)) {
        await UserTagStore.save(widget.uid, tags, account: widget.account);
        if (!_current) return;
        _savedTags = tags;
        _hasWritten = true;
      }
      final route = _route;
      if (!_current || route == null || !route.isActive) return;
      if (route.isCurrent) {
        route.navigator?.pop(true);
      } else {
        route.navigator?.removeRoute(route);
      }
      // Only after the annotation outcome is settled and shown.
      if (_hasWritten) _learnName();
    } catch (_) {
      if (!_current) return;
      setState(() {
        _busy = false;
        if (savingTags) {
          _tagError = _noteSaved ? '备注已保存；标签未保存，请重试' : '标签未保存，请重试';
        } else {
          _error = '备注保存失败，标签尚未保存';
        }
      });
      // A partial save still wrote something; its outcome is shown first.
      if (_hasWritten) _learnName();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_revoked) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpace.lg,
        0,
        AppSpace.lg,
        AppSpace.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('备注与标签', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpace.xs),
                  // Each identity once: the UID alone when no name is known.
                  Text(
                    switch (widget.name?.trim()) {
                      final name? when name.isNotEmpty =>
                        '原名 $name · UID ${widget.uid}',
                      _ => 'UID ${widget.uid}',
                    },
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (widget.onOpenProfile != null)
              Tooltip(
                message: _clean ? '查看个人资料' : '先保存或撤销修改',
                child: TextButton.icon(
                  key: const ValueKey('annotation-editor-profile'),
                  onPressed: _busy || !_clean ? null : _openProfile,
                  icon: const Icon(Icons.person_outline, size: 18),
                  label: const Text('个人资料'),
                ),
              ),
          ]),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_busy,
            maxLength: userNoteMaxLength,
            textInputAction: TextInputAction.done,
            onSubmitted: _busy ? null : _write,
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(
              labelText: '备注',
              errorText: _error,
            ),
          ),
          if (_noteSaved && _controller.text.trim() == _savedNote)
            _StatusLine(
                icon: Icons.check_circle_outline,
                color: AppColors.success,
                text: '备注已保存'),
          const SizedBox(height: AppSpace.lg),
          Row(children: [
            Expanded(child: Text('标签', style: theme.textTheme.titleSmall)),
            Text('${_tags.length}/${UserTagStore.maxTags}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textFaint)),
          ]),
          const SizedBox(height: AppSpace.sm),
          // Tags wear their label's colour, as next to the name; tapping one
          // picks it. Brand colour would read as "selected" and is not offered.
          Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final (index, tag) in _tags.indexed)
                  InputChip(
                    key: ValueKey('user-tag-chip:$tag'),
                    label: Text(tag),
                    labelStyle: theme.textTheme.bodySmall?.copyWith(
                        color: AppTagColors.of(_colorOf(tag))?.$2 ??
                            AppColors.textMuted),
                    backgroundColor:
                        AppTagColors.of(_colorOf(tag))?.$1 ?? AppColors.inkSoft,
                    tooltip: '设置「$tag」的颜色',
                    onPressed: _busy ? null : () => _pickColor(tag),
                    side: BorderSide.none,
                    shape: const StadiumBorder(),
                    visualDensity: VisualDensity.compact,
                    deleteIcon: const Icon(Icons.close, size: 16),
                    deleteIconColor: AppColors.textMuted,
                    deleteButtonTooltipMessage: '移除 $tag',
                    onDeleted: _busy
                        ? null
                        : () =>
                            setState(() => _tags = [..._tags]..removeAt(index)),
                  ),
                if (_tags.length < UserTagStore.maxTags && !_addingTag)
                  ActionChip(
                    label: const Text('+ 添加标签'),
                    labelStyle: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.text),
                    backgroundColor: AppColors.surface,
                    side: BorderSide(color: AppColors.borderStrong),
                    shape: const StadiumBorder(),
                    visualDensity: VisualDensity.compact,
                    onPressed:
                        _busy ? null : () => setState(() => _addingTag = true),
                  ),
              ]),
          if (_colorError case final error?)
            _StatusLine(
                icon: Icons.error_outline,
                color: theme.colorScheme.error,
                text: error),
          if (_tags.length >= UserTagStore.maxTags)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: Text('已达 ${UserTagStore.maxTags} 个标签上限',
                  key: const ValueKey('user-tag-full'),
                  style: theme.textTheme.bodySmall),
            )
          else if (_addingTag) ...[
            const SizedBox(height: AppSpace.sm),
            TextField(
              key: const ValueKey('user-tag-input'),
              controller: _tagController,
              autofocus: true,
              enabled: !_busy,
              onChanged: (_) => setState(() => _tagError = null),
              onSubmitted: (_) => _busy || _resolving ? null : _addTag(),
              decoration: InputDecoration(
                labelText: '标签',
                hintText: '搜索或新建标签',
                counterText: '${_tagController.text.trim().runes.length}/16',
                suffixIcon: IconButton(
                    tooltip: '添加标签',
                    onPressed: _busy || _resolving ? null : _addTag,
                    icon: const Icon(Icons.check)),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            _suggestions(theme),
          ],
          if (_visibleTagError != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: _StatusLine(
                  icon: Icons.error_outline,
                  color: theme.colorScheme.error,
                  text: _visibleTagError!),
            ),
          const SizedBox(height: AppSpace.lg),
          Row(children: [
            // Clears the note draft only; like every other edit it is kept by
            // 保存, so it can never commit a pending tag change.
            if (widget.note != null && _controller.text.isNotEmpty)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _controller.clear();
                          _error = null;
                        }),
                child: const Text('清除备注'),
              ),
            const Spacer(),
            TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: Text(_hasWritten ? '关闭' : '取消')),
            const SizedBox(width: AppSpace.sm),
            FilledButton(
                onPressed: _busy ? null : () => _write(_controller.text),
                child: Text(_visibleTagError != null || _error != null
                    ? '重试保存'
                    : '保存')),
          ]),
        ],
      ),
    );
  }
}

/// One short saved/failed line under a field.
class _StatusLine extends StatelessWidget {
  const _StatusLine(
      {required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xs),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Text(text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: color)),
        ),
      ]),
    );
  }
}

/// The original name with the local note beside it; the note ellipsizes first.
class UserNoteLabel extends StatelessWidget {
  const UserNoteLabel({
    super.key,
    required this.name,
    this.note,
    this.style,
  });

  final String name;
  final String? note;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyMedium;
    final text = note;
    if (text == null || text.isEmpty) {
      return Text(name,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: base);
    }
    // One text run: the tail, so the note, is what the ellipsis cuts first.
    return Semantics(
      label: '$name，备注 $text',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          text: name,
          children: [
            TextSpan(
              text: '  $text',
              style: TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: base,
      ),
    );
  }
}
