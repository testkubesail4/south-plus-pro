import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/forum_repository.dart';
import '../../services/user_note_store.dart';
import '../../services/user_tag_store.dart';
import '../../theme/app_theme.dart';

const userNoteMaxLength = 40;

/// Local, per-scope UID notes for one screen. Notes only show for the storage
/// scope they were loaded for; any scope change clears them at once and
/// reloads after the repository finished its (possibly multi-step) switch.
class UserNoteController extends ChangeNotifier {
  UserNoteController(this.repository) {
    UserNoteStore.revision.addListener(reload);
    UserTagStore.revision.addListener(reload);
    // The epoch moves before the final user/config is set, the user moves
    // after: observe both, and reload from a microtask so the scope is final.
    repository.sessionEpoch.addListener(_onScopeChange);
    repository.sessionUser.addListener(_onScopeChange);
    reload();
  }

  final ForumRepository repository;
  Map<String, String> _notes = const {};
  Map<String, List<String>> _tags = const {};
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

  Map<String, String> get notes => _loadedScope == repository.localPreferenceAccount && _hasLoaded ? _notes : const {};
  Map<String, List<String>> get tags => _loadedScope == repository.localPreferenceAccount && _hasTagsLoaded ? _tags : const {};

  List<String> tagsFor(String? uid) => uid == null ? const [] : tags[uid] ?? const [];

  void _onScopeChange() {
    _generation++;
    _notes = const {};
    _tags = const {};
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
    } catch (error) { noteError = error; }
    try {
      loadedTags = await UserTagStore.load(account: scope);
    } catch (error) { tagError = error; }
    if (_disposed || generation != _generation) return;
    if (scope != repository.localPreferenceAccount) return reload();
    if (loadedNotes != null) { _notes = loadedNotes; _hasLoaded = true; }
    if (loadedTags != null) { _tags = loadedTags; _hasTagsLoaded = true; }
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
  required String name,
  String? note,
  List<String> tags = const [],
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
  });

  final ForumRepository repository;
  // Captured when the sheet opened; a write never lands in another account.
  final String? account;
  final int epoch;
  final String uid;
  final String name;
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

  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
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

  void _removeOwnRoute() {
    final route = _route;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  bool get _current => mounted && !_revoked &&
      widget.account == widget.repository.localPreferenceAccount &&
      widget.epoch == widget.repository.sessionEpoch.value;

  List<String> _draftTags() => UserTagStore.normalize([
    ..._tags,
    if (_addingTag && _tagController.text.trim().isNotEmpty) _tagController.text,
  ]);

  String? get _visibleTagError {
    if (_tagError == null) return null;
    try {
      if (listEquals(_draftTags(), _savedTags)) return null;
    } on ArgumentError { /* Invalid drafts still show their validation error. */ }
    return _tagError!.startsWith('备注已保存；') && _controller.text.trim() != _savedNote
        ? '标签未保存，请重试' : _tagError;
  }

  void _addTag() {
    try {
      final tags = _draftTags();
      setState(() { _tags = tags; _tagController.clear(); _addingTag = false; _tagError = null; });
    } on ArgumentError catch (error) {
      setState(() => _tagError = error.message.toString());
    }
  }

  Future<void> _write(String text) async {
    if (!_current || _busy) return;
    final note = text.trim();
    List<String> tags;
    try {
      tags = _draftTags();
    } on ArgumentError catch (error) {
      setState(() => _tagError = error.message.toString());
      return;
    }
    setState(() {
      _busy = true; _error = null; _tagError = null; _tags = tags;
      _tagController.clear(); _addingTag = false;
    });
    var savingTags = false;
    try {
      if (note != _savedNote) {
        await UserNoteStore.save(widget.uid, note, account: widget.account);
        if (!_current) return;
        setState(() { _savedNote = note; _noteSaved = true; _hasWritten = true; });
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
          Text('备注与标签', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpace.xs),
          Text(
            '原名：${widget.name}　UID ${widget.uid}',
            style: theme.textTheme.bodySmall,
          ),
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
              helperText: '仅本机保存，不会同步到论坛',
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
          // Assigned tags are neutral, as they are next to the name; brand
          // colour would read as "selected".
          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final (index, tag) in _tags.indexed)
              InputChip(
                label: Text(tag),
                labelStyle: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textMuted),
                backgroundColor: AppColors.inkSoft,
                side: BorderSide.none,
                shape: const StadiumBorder(),
                visualDensity: VisualDensity.compact,
                deleteIcon: const Icon(Icons.close, size: 16),
                deleteIconColor: AppColors.textMuted,
                deleteButtonTooltipMessage: '移除 $tag',
                onDeleted: _busy ? null : () => setState(() => _tags = [..._tags]..removeAt(index)),
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
                onPressed: _busy ? null : () => setState(() => _addingTag = true),
              ),
          ]),
          if (_addingTag) ...[
            const SizedBox(height: AppSpace.sm),
            TextField(
              key: const ValueKey('user-tag-input'),
              controller: _tagController,
              autofocus: true,
              enabled: !_busy,
              onChanged: (_) => setState(() => _tagError = null),
              onSubmitted: (_) => _busy ? null : _addTag(),
              decoration: InputDecoration(
                labelText: '标签',
                counterText: '${_tagController.text.trim().runes.length}/16',
                helperText: '最多 16 个字符，部分表情占多个字符',
                suffixIcon: IconButton(tooltip: '添加标签', onPressed: _busy ? null : _addTag, icon: const Icon(Icons.check)),
              ),
            ),
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
            TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: Text(_hasWritten ? '关闭' : '取消')),
            const SizedBox(width: AppSpace.sm),
            FilledButton(onPressed: _busy ? null : () => _write(_controller.text),
                child: Text(_visibleTagError != null || _error != null ? '重试保存' : '保存')),
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
