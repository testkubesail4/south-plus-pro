import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/watch_models.dart';
import '../../services/forum_repository.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';

final _positive = RegExp(r'^[1-9]\d*$');

/// The thread ID in a forum thread URL, or null.
String? watchTidOf(String url) {
  final tid = RegExp(r'(?:[?&-])tid[-=]([1-9]\d*)').firstMatch(url)?.group(1);
  return tid;
}

/// The signed-in user's own UID, when known.
String? watchSelfUid(ForumRepository repository) {
  final uid =
      repository.isLoggedIn ? repository.accountIdentity.value?.uid : null;
  return uid != null && _positive.hasMatch(uid) ? uid : null;
}

/// What a 关注 entry point watches: one thread, user or board.
class WatchTarget {
  const WatchTarget({
    required this.scope,
    required this.subjectId,
    required this.label,
    this.people = const [],
    this.involving,
  });

  final WatchScope scope;
  final String subjectId;

  /// Thread title, user name or board name, kept with the rule.
  final String label;

  /// `(uid, name)` of people the reader can pick as 某人, e.g. floor authors.
  final List<(String, String)> people;

  /// A UID the editor starts with as 涉及, e.g. the floor's author.
  final String? involving;
}

IconData watchScopeIcon(WatchScope scope) => switch (scope) {
      WatchScope.thread => Icons.article_outlined,
      WatchScope.user => Icons.person_outline,
      WatchScope.board => Icons.dashboard_outlined,
    };

String _kindName(WatchContentKind kind) => switch (kind) {
      WatchContentKind.topics => '新主题',
      WatchContentKind.replies => '新回复',
      WatchContentKind.favorites => '新可见收藏',
    };

// 我, or a spaced name or UID that reads well between Chinese words.
String _who(String uid, String? selfUid, Map<String, String> names) =>
    uid == selfUid ? '我' : ' ${names[uid] ?? 'UID $uid'} ';

/// One plain sentence of what [rule] reports: filters joined by 且, kinds
/// by 或. [names] gives people's names by UID where known.
String watchRuleSummary(
  WatchRule rule,
  String? selfUid, [
  Map<String, String> names = const {},
]) {
  final keyword = rule.keyword.trim();
  final field = rule.keywordField == WatchKeywordField.title ? '标题' : '正文';
  switch (rule.scope) {
    case WatchScope.thread:
      final involving = rule.involvingUid;
      return [
        involving == null
            ? '所有新回复'
            : '回复或引用${_who(involving, selfUid, names)}的新回复',
        if (keyword.isNotEmpty) '且正文含「$keyword」',
      ].join('，');
    case WatchScope.user:
      final kinds = [
        for (final kind in WatchContentKind.values)
          if (rule.kinds.contains(kind)) _kindName(kind),
      ];
      return [
        'TA 的${kinds.join('或')}',
        if (rule.involvingUid case final uid?)
          '且涉及${_who(uid, selfUid, names)}'.trimRight(),
        if (keyword.isNotEmpty) '且$field含「$keyword」',
      ].join('，');
    case WatchScope.board:
      return '标题含「$keyword」的新主题';
  }
}

String _clock(DateTime at) => '${at.hour.toString().padLeft(2, '0')}:'
    '${at.minute.toString().padLeft(2, '0')}';

/// Where a rule's checking stands, in a few words.
String watchStatusText(WatchService watch, WatchRule rule) {
  if (rule.paused) return '已暂停';
  final status = watch.statuses[rule.id];
  final checked = status?.checkedAt;
  return switch (status?.phase) {
    null || WatchPhase.baseline => '等待首次检查',
    WatchPhase.pending => watch.pendingUntil == null ? '等待检查' : '待继续（已达请求上限）',
    WatchPhase.current =>
      checked == null ? '已检查' : '${_clock(checked.toLocal())} 已检查',
    WatchPhase.incomplete => '有内容待确认，下次继续',
    WatchPhase.unavailable =>
      status!.reason.isEmpty ? '无法检查' : '无法检查：${status.reason}',
    WatchPhase.paused => '已暂停',
  };
}

/// Opens the 关注 sheet for [target]: its rules to edit and a new one, or
/// straight into a new rule when there are none.
Future<void> showWatchSheet(
  BuildContext context, {
  required ForumRepository repository,
  required WatchTarget target,
  WatchRule? edit,
}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: AppWidths.sheet),
      builder: (_) =>
          WatchSheet(repository: repository, target: target, edit: edit),
    );

class WatchSheet extends StatefulWidget {
  const WatchSheet({
    super.key,
    required this.repository,
    required this.target,
    this.edit,
  });

  final ForumRepository repository;
  final WatchTarget target;
  final WatchRule? edit;

  @override
  State<WatchSheet> createState() => _WatchSheetState();
}

enum _Involve { none, self, someone }

/// The account a 关注 screen or action began under; a write checks it is
/// still the one signed in, so nothing lands in another account.
class WatchSessionScope {
  WatchSessionScope(this.repository)
      : _user = repository.sessionUser.value,
        _owner = repository.localPreferenceAccount,
        _epoch = repository.sessionEpoch.value;

  final ForumRepository repository;
  final String? _user;
  final String? _owner;
  final int _epoch;

  bool get current =>
      repository.sessionUser.value == _user &&
      repository.localPreferenceAccount == _owner &&
      repository.sessionEpoch.value == _epoch;
}

class _WatchSheetState extends State<WatchSheet> {
  WatchService get _watch => widget.repository.watch;
  WatchTarget get _target => widget.target;
  // Both read as the sheet opens, before any change can be heard.
  late final WatchSessionScope _scope;
  late final String? _selfUid;
  late final Listenable _session = Listenable.merge(
      [widget.repository.sessionUser, widget.repository.sessionEpoch]);

  // Null lists the target's rules; otherwise the editor is open, with the
  // rule it edits (or none for a new one).
  bool _editing = false;
  WatchRule? _rule;

  final _keyword = TextEditingController();
  final _uid = TextEditingController();
  var _involve = _Involve.none;
  var _kinds = <WatchContentKind>{WatchContentKind.topics};
  var _field = WatchKeywordField.title;
  var _notify = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scope = WatchSessionScope(widget.repository);
    _selfUid = watchSelfUid(widget.repository);
    _session.addListener(_onSession);
    if (widget.edit case final rule?) {
      _open(rule);
    } else if (_existing.isEmpty) {
      _open(null);
    }
  }

  // Another account signed in: this sheet's rules and form are not theirs.
  void _onSession() {
    if (!_scope.current && mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    _keyword.dispose();
    _uid.dispose();
    super.dispose();
  }

  List<WatchRule> get _existing => [
        for (final rule in _watch.rules)
          if (rule.scope == _target.scope &&
              rule.subjectId == _target.subjectId)
            rule,
      ];

  Map<String, String> get _names =>
      {for (final (uid, name) in _target.people) uid: name};

  void _open(WatchRule? rule) {
    _editing = true;
    _rule = rule;
    _error = null;
    _notify = rule?.notificationsEnabled ?? true;
    _keyword.text = rule?.keyword ?? '';
    _field = rule?.keywordField ??
        (_target.scope == WatchScope.thread
            ? WatchKeywordField.body
            : WatchKeywordField.title);
    _kinds = {
      ...?rule?.kinds,
      if (rule == null)
        _target.scope == WatchScope.user
            ? WatchContentKind.topics
            : _target.scope == WatchScope.thread
                ? WatchContentKind.replies
                : WatchContentKind.topics,
    };
    final involving = rule == null ? _target.involving : rule.involvingUid;
    if (involving == null) {
      _involve = _Involve.none;
      _uid.text = '';
    } else if (involving == _selfUid) {
      _involve = _Involve.self;
      _uid.text = '';
    } else {
      _involve = _Involve.someone;
      _uid.text = involving;
    }
    if (_target.scope == WatchScope.user && _involve != _Involve.none) {
      _kinds = {WatchContentKind.replies};
    }
  }

  void _setInvolve(_Involve value) => setState(() {
        _involve = value;
        _error = null;
        // 涉及 only narrows replies; topics and favorites leave the rule.
        if (_target.scope == WatchScope.user && value != _Involve.none) {
          _kinds = {WatchContentKind.replies};
        }
      });

  String? get _involvingUid => switch (_involve) {
        _Involve.none => null,
        _Involve.self => _selfUid,
        _Involve.someone =>
          _positive.hasMatch(_uid.text.trim()) ? _uid.text.trim() : null,
      };

  // Null when the form cannot make a rule, with the reason in [_problem].
  WatchRule? _build() {
    final scope = _target.scope;
    final keyword = _keyword.text.trim();
    if (_involve != _Involve.none && _involvingUid == null) return null;
    if (scope == WatchScope.board && keyword.isEmpty) return null;
    if (scope == WatchScope.user && _kinds.isEmpty) return null;
    try {
      return WatchRule(
        id: _rule?.id ?? _newId(),
        scope: scope,
        subjectId: _target.subjectId,
        label: _target.label.length > 500
            ? _target.label.substring(0, 500)
            : _target.label,
        kinds: switch (scope) {
          WatchScope.thread => {WatchContentKind.replies},
          WatchScope.board => {WatchContentKind.topics},
          WatchScope.user => _kinds,
        },
        involvingUid: scope == WatchScope.board ? null : _involvingUid,
        keyword: keyword,
        keywordField: switch (scope) {
          WatchScope.thread => WatchKeywordField.body,
          WatchScope.board => WatchKeywordField.title,
          WatchScope.user => _field,
        },
        paused: _rule?.paused ?? false,
        notificationsEnabled: _notify,
      );
    } on ArgumentError {
      return null;
    }
  }

  String? get _problem {
    if (_involve == _Involve.someone && _involvingUid == null) {
      return '请填写对方的数字 UID';
    }
    if (_involve == _Involve.self && _selfUid == null) {
      return '暂时读不到你的 UID，请稍后再试';
    }
    if (_target.scope == WatchScope.board && _keyword.text.trim().isEmpty) {
      return '请填写标题关键字';
    }
    if (_target.scope == WatchScope.user && _kinds.isEmpty) {
      return '至少选择一项';
    }
    return null;
  }

  static String _newId() =>
      'watch_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';

  // A new rule starts active, so it needs a free active slot.
  bool get _full =>
      _rule == null && _watch.activeCount >= WatchService.maxActiveRules;

  Future<void> _save() async {
    final rule = _build();
    if (rule == null || _busy || !_scope.current) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_rule == null) {
        await _watch.addRule(rule);
      } else {
        await _watch.updateRule(rule);
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text(_rule == null ? '已关注' : '已保存')),
      );
    } on WatchLimitException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(WatchRule rule) async {
    if (_busy || !_scope.current) return;
    setState(() => _busy = true);
    try {
      await _watch.removeRule(rule.id);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('已删除关注')));
    } catch (_) {
      if (mounted) setState(() => _error = '删除失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _watch,
      builder: (context, _) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpace.lg,
          0,
          AppSpace.lg,
          AppSpace.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            const SizedBox(height: AppSpace.md),
            if (_editing) ..._editor(context) else ..._list(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final scope = switch (_target.scope) {
      WatchScope.thread => '帖子',
      WatchScope.user => '用户',
      WatchScope.board => '版块',
    };
    return Row(
      children: [
        WatchScopeTile(scope: _target.scope),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _target.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              Text(
                _editing
                    ? (_rule == null ? '关注$scope · 新规则' : '关注$scope · 编辑规则')
                    : '关注$scope',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _list(BuildContext context) {
    final rules = _existing;
    final theme = Theme.of(context);
    return [
      for (final rule in rules)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(watchRuleSummary(rule, _selfUid, _names)),
          subtitle: Text(watchStatusText(_watch, rule)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => setState(() => _open(rule)),
        ),
      const SizedBox(height: AppSpace.sm),
      OutlinedButton.icon(
        onPressed: _full ? null : () => setState(() => _open(null)),
        icon: const Icon(Icons.add),
        label: const Text('新增关注规则'),
      ),
      if (_full) ...[
        const SizedBox(height: AppSpace.xs),
        Text(
          '已启用 ${WatchService.maxActiveRules} 条，先暂停或删除一条',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    ];
  }

  List<Widget> _editor(BuildContext context) {
    final theme = Theme.of(context);
    final scope = _target.scope;
    final rule = _build();
    final problem = _problem;
    final label = theme.textTheme.labelLarge;
    Widget section(String text) => Padding(
          padding: const EdgeInsets.only(top: AppSpace.lg, bottom: AppSpace.sm),
          child: Text(text, style: label),
        );
    final summary =
        rule == null ? null : watchRuleSummary(rule, _selfUid, _names);
    return [
      // The rule as one sentence: what AND/OR mean here, in words.
      Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: AppColors.inkSoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Semantics(
          liveRegion: true,
          child: Text(
            summary ?? problem ?? '',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: summary == null ? AppColors.textMuted : null,
            ),
          ),
        ),
      ),
      if (scope == WatchScope.user) ...[
        section('内容'),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            for (final kind in WatchContentKind.values)
              FilterChip(
                label: Text(_kindName(kind)),
                selected: _kinds.contains(kind),
                onSelected: _involve != _Involve.none &&
                        kind != WatchContentKind.replies
                    ? null
                    : (on) => setState(() {
                          _kinds = on
                              ? {..._kinds, kind}
                              : ({..._kinds}..remove(kind));
                        }),
              ),
          ],
        ),
        if (_involve != _Involve.none) _hint(context, '涉及只适用于回复'),
      ],
      if (scope != WatchScope.board) ...[
        section(scope == WatchScope.thread ? '哪些回复' : '涉及'),
        if (scope == WatchScope.thread)
          _threadModes(context)
        else
          SegmentedButton<_Involve>(
            segments: [
              const ButtonSegment(value: _Involve.none, label: Text('不限')),
              ButtonSegment(
                value: _Involve.self,
                label: const Text('我'),
                enabled: _selfUid != null,
              ),
              const ButtonSegment(value: _Involve.someone, label: Text('某人')),
            ],
            showSelectedIcon: false,
            selected: {_involve},
            onSelectionChanged: (values) => _setInvolve(values.single),
          ),
        if (_involve == _Involve.someone) ..._someone(context),
      ],
      section(switch (scope) {
        WatchScope.thread => '只看含关键字的回复（可选）',
        WatchScope.user => '关键字（可选）',
        WatchScope.board => '标题关键字',
      }),
      if (scope == WatchScope.user) ...[
        SegmentedButton<WatchKeywordField>(
          segments: const [
            ButtonSegment(value: WatchKeywordField.title, label: Text('标题')),
            ButtonSegment(value: WatchKeywordField.body, label: Text('正文')),
          ],
          showSelectedIcon: false,
          selected: {_field},
          onSelectionChanged: (values) =>
              setState(() => _field = values.single),
        ),
        const SizedBox(height: AppSpace.sm),
      ],
      TextField(
        controller: _keyword,
        maxLength: 200,
        decoration: InputDecoration(
          hintText: scope == WatchScope.board ? '例如：汉化' : null,
          counterText: '',
        ),
        onChanged: (_) => setState(() => _error = null),
      ),
      if (scope == WatchScope.user &&
          _field == WatchKeywordField.body &&
          _keyword.text.trim().isNotEmpty)
        _hint(context, '匹配正文检查较慢'),
      const SizedBox(height: AppSpace.md),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('系统通知'),
        value: _notify,
        onChanged: (value) => setState(() => _notify = value),
      ),
      if (_error case final error?)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: Text(
            error,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      if (_full)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: Text(
            '已启用 ${WatchService.maxActiveRules} 条，先暂停或删除一条',
            style: theme.textTheme.bodySmall,
          ),
        ),
      FilledButton(
        onPressed: rule == null || _busy || _full ? null : _save,
        child: Text(_rule == null ? '关注' : '保存'),
      ),
      if (_rule case final existing?) ...[
        const SizedBox(height: AppSpace.xs),
        TextButton(
          onPressed: _busy ? null : () => _delete(existing),
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          child: const Text('删除关注'),
        ),
      ],
    ];
  }

  Widget _threadModes(BuildContext context) {
    Widget option(_Involve value, String title) => RadioListTile<_Involve>(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: value,
          title: Text(title),
          enabled: value != _Involve.self || _selfUid != null,
        );
    return RadioGroup<_Involve>(
      groupValue: _involve,
      onChanged: (value) {
        if (value != null) _setInvolve(value);
      },
      child: Column(
        children: [
          option(_Involve.none, '所有新回复'),
          option(_Involve.self, '回复或引用我的'),
          option(_Involve.someone, '回复或引用某人的'),
        ],
      ),
    );
  }

  List<Widget> _someone(BuildContext context) {
    final people = [
      for (final (uid, name) in _target.people)
        if (uid != _selfUid && _positive.hasMatch(uid)) (uid, name),
    ];
    return [
      if (people.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            for (final (uid, name) in people)
              ChoiceChip(
                label: Text(name),
                selected: _uid.text.trim() == uid,
                onSelected: (_) => setState(() {
                  _uid.text = uid;
                  _error = null;
                }),
              ),
          ],
        ),
      ],
      const SizedBox(height: AppSpace.sm),
      TextField(
        controller: _uid,
        keyboardType: TextInputType.number,
        maxLength: 12,
        decoration: const InputDecoration(labelText: '对方 UID', counterText: ''),
        onChanged: (_) => setState(() => _error = null),
      ),
    ];
  }

  Widget _hint(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.xs),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );
}

/// The leading scope glyph of a 关注 row or sheet.
class WatchScopeTile extends StatelessWidget {
  const WatchScopeTile({super.key, required this.scope});

  final WatchScope scope;

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.inkSoft,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child:
            Icon(watchScopeIcon(scope), size: 20, color: AppColors.textMuted),
      );
}
