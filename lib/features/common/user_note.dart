import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/forum_repository.dart';
import '../../services/user_note_store.dart';
import '../../theme/app_theme.dart';

const userNoteMaxLength = 40;

/// Local, per-scope UID notes for one screen. Notes only show for the storage
/// scope they were loaded for; any scope change clears them at once and
/// reloads after the repository finished its (possibly multi-step) switch.
class UserNoteController extends ChangeNotifier {
  UserNoteController(this.repository) {
    UserNoteStore.revision.addListener(reload);
    // The epoch moves before the final user/config is set, the user moves
    // after: observe both, and reload from a microtask so the scope is final.
    repository.sessionEpoch.addListener(_onScopeChange);
    repository.sessionUser.addListener(_onScopeChange);
    reload();
  }

  final ForumRepository repository;
  Map<String, String> _notes = const {};
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

  void _onScopeChange() {
    _generation++;
    _notes = const {};
    _hasLoaded = false;
    notifyListeners();
    scheduleMicrotask(reload);
  }

  Future<void> reload() async {
    if (_disposed) return;
    final generation = ++_generation;
    final scope = repository.localPreferenceAccount;
    Map<String, String> loaded;
    try {
      loaded = await UserNoteStore.load(account: scope);
    } catch (_) {
      loaded = const {};
    }
    if (_disposed || generation != _generation) return;
    if (scope != repository.localPreferenceAccount) {
      // The scope moved while loading; load again for the final one.
      return reload();
    }
    _notes = loaded;
    _loadedScope = scope;
    _hasLoaded = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    UserNoteStore.revision.removeListener(reload);
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
  });

  final ForumRepository repository;
  // Captured when the sheet opened; a write never lands in another account.
  final String? account;
  final int epoch;
  final String uid;
  final String name;
  final String? note;

  @override
  State<_UserNoteSheet> createState() => _UserNoteSheetState();
}

class _UserNoteSheetState extends State<_UserNoteSheet> {
  late final _controller = TextEditingController(text: widget.note);
  bool _busy = false;
  String? _error;
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
    super.dispose();
  }

  // Blank at once, then remove only this sheet's route; routes above or below
  // it stay.
  void _revoke() {
    if (_revoked || !mounted) return;
    _controller.clear();
    setState(() => _revoked = true);
    _removeOwnRoute();
  }

  void _removeOwnRoute() {
    final route = _route;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  Future<void> _write(String text) async {
    if (_revoked) return;
    if (widget.account != widget.repository.localPreferenceAccount) {
      setState(() => _error = '登录状态已变化，未保存');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await UserNoteStore.save(widget.uid, text, account: widget.account);
      // Disposal is deferred after a revoke: check the flag, and only ever
      // close this sheet's own route, never whatever is current.
      final route = _route;
      if (!mounted || _revoked || route == null || !route.isActive) return;
      if (route.isCurrent) {
        route.navigator?.pop(true);
      } else {
        route.navigator?.removeRoute(route);
      }
    } catch (_) {
      if (!mounted || _revoked) return;
      setState(() {
        _busy = false;
        _error = '保存失败，请重试';
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
          Text('用户备注', style: theme.textTheme.titleMedium),
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
            decoration: InputDecoration(
              labelText: '备注',
              helperText: '仅本机保存，不会同步到论坛',
              errorText: _error,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Row(
            children: [
              if (widget.note != null)
                TextButton(
                  onPressed: _busy ? null : () => _write(''),
                  child: const Text('清除'),
                ),
              const Spacer(),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              const SizedBox(width: AppSpace.sm),
              FilledButton(
                onPressed: _busy ? null : () => _write(_controller.text),
                child: const Text('保存'),
              ),
            ],
          ),
        ],
      ),
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
