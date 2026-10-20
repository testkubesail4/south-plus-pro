import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../services/home_reading_preferences.dart';
import '../../theme/app_theme.dart';
import '../common/app_switcher.dart';
import '../common/grouped_list.dart';
import '../common/content_width.dart';
import 'favorite_collections_sheets.dart';

class HomeBoardsSettingsScreen extends StatefulWidget {
  HomeBoardsSettingsScreen({super.key, required this.repository})
      : account = repository.localPreferenceAccount,
        epoch = repository.sessionEpoch.value;

  final ForumRepository repository;
  final String? account;
  final int epoch;

  @override
  State<HomeBoardsSettingsScreen> createState() => _HomeBoardsSettingsScreenState();
}

class _HomeBoardsSettingsScreenState extends State<HomeBoardsSettingsScreen> {
  late final _account = widget.account;
  late final _epoch = widget.epoch;
  List<ForumSection>? _sections;
  HomeReadingPreferences? _prefs;
  HomeReadingPreferences? _acknowledgedPrefs;
  Object? _directoryError;
  Object? _prefsError;
  Object? get _error => _directoryError ?? _prefsError;
  bool _busy = false;
  bool get _locked => _busy || _error != null;
  bool _revoked = false;
  int _run = 0;
  int _directoryRun = 0;
  final _expanded = <String>{};

  bool get _current => !_revoked &&
      _account == widget.repository.localPreferenceAccount &&
      _epoch == widget.repository.sessionEpoch.value;

  @override
  void initState() {
    super.initState();
    widget.repository.sessionEpoch.addListener(_revoke);
    widget.repository.sessionUser.addListener(_revoke);
    HomeReadingPreferences.revision.addListener(_reloadPrefs);
    if (_current) {
      _load();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revoke());
    }
  }

  @override
  void dispose() {
    _run++;
    _directoryRun++;
    widget.repository.sessionEpoch.removeListener(_revoke);
    widget.repository.sessionUser.removeListener(_revoke);
    HomeReadingPreferences.revision.removeListener(_reloadPrefs);
    super.dispose();
  }

  void _revoke() {
    if (!mounted || _current) return;
    _revoked = true;
    setState(() { _prefs = null; _sections = null; });
    scheduleMicrotask(() {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) route.navigator?.removeRoute(route);
    });
  }

  Future<void> _load() async {
    final run = ++_directoryRun;
    setState(() => _directoryError = null);
    try {
      final sections = await widget.repository.fetchForumSections();
      if (!mounted || !_current || run != _directoryRun) return;
      setState(() { _sections = sections; _prefs = _prefs?.reconcile(sections); });
      await _reloadPrefs();
    } catch (error) {
      if (mounted && _current && run == _directoryRun) setState(() => _directoryError = error);
    }
  }

  Future<void> _reloadPrefs() async {
    final run = ++_run;
    try {
      final prefs = await HomeReadingPreferences.load(account: _account);
      if (mounted && _current && run == _run) {
        setState(() { _prefs = prefs.reconcile(_sections ?? []); _acknowledgedPrefs = _prefs; _prefsError = null; });
      }
    } catch (error) {
      if (mounted && _current && run == _run) setState(() => _prefsError = error);
    }
  }

  Future<void> _change(Future<void> Function() write) async {
    if (_locked || !_current) return;
    setState(() => _busy = true);
    try {
      await write();
      await _reloadPrefs();
    } catch (_) {
      if (mounted && _current) setState(() => _prefs = _acknowledgedPrefs);
      await _reloadPrefs();
      if (mounted && _current) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法保存首页版块设置，请重试')));
      }
    } finally {
      if (mounted && _current) setState(() => _busy = false);
    }
  }

  String? _fid(ForumBoard board) => widget.repository.searchBoardId(
      ForumCategory(name: board.name, slug: board.slug, url: board.url));

  Future<void> _restore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => SessionBound(
        session: widget.repository.sessionEpoch,
        generation: _epoch,
        child: AlertDialog(
        title: const Text('恢复默认？'),
        content: const Text('恢复分区顺序并显示所有分区与版块（折叠状态不变）'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('恢复默认')),
        ],
      )),
    );
    if (ok == true && mounted && _current) {
      await _change(() => HomeReadingPreferences.restoreLayout(account: _account));
    }
  }

  void _reorder(List<ForumSection> ordered, int oldIndex, int newIndex) {
    if (_locked || !_current) return;
    if (newIndex > oldIndex) newIndex--;
    final next = List<ForumSection>.of(ordered);
    next.insert(newIndex, next.removeAt(oldIndex));
    final ids = [for (final s in next) _prefs!.sectionId(s, _sections!)];
    if (ids.any((id) => id == null)) return;
    setState(() => _prefs = _prefs!.copyWith(sectionOrder: ids.cast<String>()));
    _change(() => HomeReadingPreferences.saveSectionOrder(ids.cast<String>(),
        account: _account, sections: _sections!));
  }

  @override
  Widget build(BuildContext context) {
    if (!_current) return const SizedBox.shrink();
    final sections = _sections;
    final prefs = _prefs;
    final ordered = sections == null || prefs == null ? <ForumSection>[] : prefs.orderedSections(sections);
    return Scaffold(
      appBar: AppBar(title: const Text('首页版块'), actions: [
        TextButton(onPressed: _locked || prefs == null || sections == null ? null : _restore,
            child: const Text('恢复默认')),
      ]),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.symmetric(horizontal: appGutter(MediaQuery.sizeOf(context).width, AppWidths.form), vertical: AppSpace.md),
          children: [
            Text('隐藏只缩短首页。\n最近、搜索、收藏和我的版块里依然可以进入。', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpace.lg),
            // The settings fade in over the spinner.
            AppSwitcher(
              id: sections != null && prefs != null ? 'settings' : _error != null ? 'error' : 'loading',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_error != null)
              ListTile(title: const Text('加载失败'), trailing: TextButton(onPressed: _load, child: const Text('重试'))),
            if (_error == null && (sections == null || prefs == null))
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (sections != null && prefs != null) ...[
              Text('分区（拖动排序，调整后自动保存）', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpace.md),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: ordered.length,
                onReorder: (oldIndex, newIndex) => _reorder(ordered, oldIndex, newIndex),
                itemBuilder: (context, index) {
                  final section = ordered[index];
                  final id = prefs.sectionId(section, sections);
                  final open = id != null && _expanded.contains(id);
                  final shown = id == null || !prefs.hiddenSectionIds.contains(id);
                  final hidden = section.items.where((b) => prefs.hiddenParentFids.contains(_fid(b))).length;
                  return Padding(
                    key: ValueKey(id ?? 'ambiguous-$index'),
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: AppGroup(children: [
                      ListTile(
                        leading: ReorderableDragStartListener(
                          index: index,
                          enabled: !_locked && id != null && ordered.every((s) => prefs.sectionId(s, sections) != null),
                          child: SizedBox(width: 32, height: 48, child: Icon(Icons.drag_indicator, color: AppColors.textMuted)),
                        ),
                        // Hidden stays readable and operable; only quieter.
                        title: Text(section.title,
                            style: shown ? null : TextStyle(color: AppColors.textMuted)),
                        subtitle: Text('${section.items.length} 个版块${hidden == 0 ? '' : ' · 隐藏 $hidden 个'}${shown ? '' : ' · 已隐藏'}'),
                        trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Switch(value: shown, onChanged: _locked || id == null ? null : (value) => _change(() => HomeReadingPreferences.setSectionHidden(id, !value, account: _account, sections: sections))),
                          IconButton(tooltip: open ? '收起版块' : '展开版块', onPressed: id == null ? null : () => setState(() { if (open) { _expanded.remove(id); } else { _expanded.add(id); } }), icon: Icon(open ? Icons.expand_less : Icons.expand_more)),
                        ]),
                      ),
                      if (open)
                        for (final board in section.items)
                          ListTile(
                            contentPadding: const EdgeInsets.only(left: 56, right: 16),
                            title: Text(board.name,
                                style: prefs.hiddenParentFids.contains(_fid(board))
                                    ? TextStyle(color: AppColors.textMuted)
                                    : null),
                            subtitle: board.children.isEmpty ? null : Text('含 ${board.children.length} 个子版块'),
                            trailing: Switch(
                              key: ValueKey('home-parent-visible:${_fid(board)}'),
                              value: !prefs.hiddenParentFids.contains(_fid(board)),
                              onChanged: _locked || _fid(board) == null ? null : (value) => _change(() => HomeReadingPreferences.setParentHidden(_fid(board)!, !value, account: _account, sections: sections)),
                            ),
                          ),
                    ]),
                  );
                },
              ),
            ],
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
