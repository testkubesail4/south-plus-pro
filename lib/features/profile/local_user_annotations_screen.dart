import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../common/content_width.dart';
import '../common/grouped_list.dart';
import '../common/user_note.dart';
import '../common/user_tags_inline.dart';
import 'favorite_collections_sheets.dart' show SessionBound;
import 'user_profile_screen.dart';

class LocalUserAnnotationsScreen extends StatefulWidget {
  LocalUserAnnotationsScreen({super.key, required this.repository})
      : account = repository.localPreferenceAccount,
        epoch = repository.sessionEpoch.value;

  final ForumRepository repository;
  final String? account;
  final int epoch;

  @override
  State<LocalUserAnnotationsScreen> createState() => _LocalUserAnnotationsScreenState();
}

class _LocalUserAnnotationsScreenState extends State<LocalUserAnnotationsScreen> {
  late final _annotations = UserNoteController(widget.repository);
  final _search = TextEditingController();
  int _tab = 0;
  String? _tagFilter;
  bool _revoked = false;

  bool get _current => !_revoked && widget.account == widget.repository.localPreferenceAccount &&
      widget.epoch == widget.repository.sessionEpoch.value;

  @override
  void initState() {
    super.initState();
    widget.repository.sessionEpoch.addListener(_scopeChanged);
    widget.repository.sessionUser.addListener(_scopeChanged);
    if (!_current) WidgetsBinding.instance.addPostFrameCallback((_) => _scopeChanged());
  }

  @override
  void dispose() {
    widget.repository.sessionEpoch.removeListener(_scopeChanged);
    widget.repository.sessionUser.removeListener(_scopeChanged);
    _annotations.dispose();
    _search.dispose();
    super.dispose();
  }

  void _scopeChanged() {
    if (!mounted || _current) return;
    _revoked = true;
    _search.clear();
    setState(() {});
    scheduleMicrotask(() {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) route.navigator?.removeRoute(route);
    });
  }

  Future<void> _edit(String uid) async {
    if (!_current || _annotations.isLoading ||
        _annotations.noteLoadError != null || _annotations.tagLoadError != null) return;
    // No name is known here; the header shows the UID once.
    final url = widget.repository.userProfileUrl(uid);
    await showUserNoteEditor(context,
      repository: widget.repository, uid: uid, name: null,
      note: _annotations.noteFor(uid), tags: _annotations.tagsFor(uid),
      onOpenProfile: url == null ? null : () => _openProfile(url));
  }

  // The forum profile is read only after this tap, never to draw a row.
  // The route is bound to the scope of the tap: a switch before its first
  // frame removes only this route, and the profile never reads the old UID
  // under another account.
  void _openProfile(String url) {
    if (!_current) return;
    final repository = widget.repository;
    final account = repository.localPreferenceAccount;
    final epoch = repository.sessionEpoch.value;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SessionBound(
        session: repository.sessionEpoch,
        generation: epoch,
        child: Builder(
          builder: (_) => repository.localPreferenceAccount == account
              ? UserProfileScreen(userUrl: url, repository: repository)
              : const SizedBox.shrink(),
        ),
      ),
    ));
  }

  /// Tap opens the user's forum profile; the pencil edits the annotations.
  /// The note is labelled so it never reads as another tag.
  Widget _userRow(String uid, {required bool editable}) {
    final url = widget.repository.userProfileUrl(uid);
    final edit = editable ? () => _edit(uid) : null;
    return AppRow(
      key: ValueKey('annotation-user:$uid'),
      icon: Icons.person_outline,
      title: Text('UID $uid'),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // One line: a long note ellipsizes on its own, the tags keep theirs.
        if (_annotations.noteFor(uid) case final note?)
          Text('备注：$note', maxLines: 1, overflow: TextOverflow.ellipsis),
        if (_annotations.tagsFor(uid).isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          UserTagsInline(tags: _annotations.tagsFor(uid), onShowAll: edit ?? () {}),
        ],
      ]),
      // Without a valid profile address the row itself edits.
      onTap: url == null ? edit : () => _openProfile(url),
      enabled: true,
      trailing: url == null
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                key: ValueKey('annotation-edit:$uid'),
                tooltip: '编辑备注与标签',
                onPressed: edit,
                icon: const Icon(Icons.edit_outlined),
              ),
              Icon(Icons.chevron_right, color: AppColors.textFaint),
            ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_current) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(title: const Text('备注与标签')),
      body: SafeArea(top: false, child: ListenableBuilder(
        listenable: _annotations,
        builder: (context, _) {
          final ids = {..._annotations.notes.keys, ..._annotations.tags.keys}.toList()
            ..sort((a, b) => BigInt.parse(a).compareTo(BigInt.parse(b)));
          final tagUsers = <String, Set<String>>{};
          final tagLabels = <String, String>{};
          for (final uid in ids) {
            for (final tag in _annotations.tagsFor(uid)) {
              final key = tag.toLowerCase();
              tagLabels.putIfAbsent(key, () => tag);
              (tagUsers[key] ??= {}).add(uid);
            }
          }
          final query = _search.text.trim().toLowerCase();
          final users = ids.where((uid) =>
            (_tagFilter == null || (tagUsers[_tagFilter]?.contains(uid) ?? false)) &&
            (query.isEmpty || uid.contains(query) ||
                (_annotations.noteFor(uid)?.toLowerCase().contains(query) ?? false) ||
                _annotations.tagsFor(uid).any((tag) => tag.toLowerCase().contains(query)))).toList();
          final tagKeys = tagUsers.keys.where((key) => query.isEmpty || key.contains(query)).toList()..sort();
          final failed = _annotations.noteLoadError != null || _annotations.tagLoadError != null;
          return ListView(
            padding: EdgeInsets.symmetric(horizontal: appGutter(MediaQuery.sizeOf(context).width, AppWidths.form), vertical: AppSpace.md),
            children: [
              TextField(controller: _search, onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搜索 UID、备注或标签')),
              const SizedBox(height: AppSpace.md),
              SegmentedButton<int>(segments: [
                ButtonSegment(value: 0, label: Text(failed || _annotations.isLoading ? '用户' : '用户 ${ids.length}')),
                ButtonSegment(value: 1, label: Text(failed || _annotations.isLoading ? '标签' : '标签 ${tagUsers.length}')),
              ], selected: {_tab}, onSelectionChanged: (value) => setState(() { _tab = value.first; _tagFilter = null; })),
              const SizedBox(height: AppSpace.sm),
              Text('仅保存在本机，按当前账号区分', style: Theme.of(context).textTheme.bodySmall),
              if (failed)
                ListTile(
                  title: Text('${_annotations.noteLoadError != null ? '备注' : ''}${_annotations.noteLoadError != null && _annotations.tagLoadError != null ? '与' : ''}${_annotations.tagLoadError != null ? '标签' : ''}加载失败'),
                  trailing: TextButton(onPressed: _annotations.reload, child: const Text('重试')),
                ),
              if (_annotations.isLoading && ids.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              const SizedBox(height: AppSpace.md),
              if (_tab == 0) ...[
                if (_tagFilter != null)
                  ListTile(leading: const Icon(Icons.arrow_back), title: Text('标签：${tagLabels[_tagFilter] ?? _tagFilter}'),
                      onTap: () => setState(() => _tagFilter = null)),
                if (users.isEmpty && !_annotations.isLoading && !failed)
                  const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('暂无标记'))),
                if (users.isNotEmpty)
                  AppGroup(children: [
                    for (final uid in users)
                      _userRow(uid, editable: !_annotations.isLoading && !failed),
                  ]),
              ] else ...[
                if (tagKeys.isEmpty && !_annotations.isLoading && !failed)
                  const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('暂无标签'))),
                if (tagKeys.isNotEmpty)
                  AppGroup(children: [
                    for (final key in tagKeys)
                      AppRow(title: Align(alignment: Alignment.centerLeft, child: UserTagCapsule(tag: tagLabels[key]!)),
                        value: '${tagUsers[key]!.length} 位用户',
                        onTap: () => setState(() { _tab = 0; _tagFilter = key; })),
                  ]),
                const SizedBox(height: AppSpace.md),
                Text('点开标签查看用户；在用户上编辑可增删标签', style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          );
        },
      )),
    );
  }
}
