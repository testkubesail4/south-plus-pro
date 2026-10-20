import 'package:flutter/material.dart';

import '../../models/forum_pm_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../common/app_switcher.dart';
import '../common/async_state_view.dart';
import '../common/content_width.dart';
import '../common/grouped_list.dart';
import '../common/thread_row.dart';
import 'pm_compose_screen.dart';
import 'pm_detail_screen.dart';

class PmBoxScreen extends StatefulWidget {
  const PmBoxScreen({
    super.key,
    required this.repository,
    this.embedded = false,
    this.initialPath,
  });

  final ForumRepository repository;

  /// A native box page (from a forum link) to open on.
  final String? initialPath;

  /// Inside the 消息 tab, which supplies the app bar; 写消息 becomes the FAB.
  final bool embedded;

  @override
  State<PmBoxScreen> createState() => _PmBoxScreenState();
}

class _PmBoxScreenState extends State<PmBoxScreen> {
  ForumPmBox _box = ForumPmBox.inbox;
  // Which way the last box change moved along 收件箱 · 发件箱 · 跟踪.
  int _slide = 0;
  String? _pagePath;
  late Future<ForumPmPage> _future;

  @override
  void initState() {
    super.initState();
    if (widget.initialPath case final path?) _openPath(path);
    _future = _fetch();
  }

  Future<ForumPmPage> _fetch() =>
      widget.repository.fetchPmBox(_box, pagePath: _pagePath);

  /// Moves to the box and page a native box path names, if it names one.
  void _openPath(String path) {
    final uri = Uri.parse(path);
    final action = uri.queryParameters['action'] ??
        RegExp(r'^action-(receivebox|sendbox|scout)(?:-|\.)')
            .firstMatch(uri.query)
            ?.group(1);
    for (final box in ForumPmBox.values) {
      if (box.wireName == action) {
        _box = box;
        _pagePath = path;
        break;
      }
    }
  }

  Future<void> _refresh([ForumPmActionResult? result]) async {
    if (result?.refreshPath case final path?) _openPath(path);
    setState(() {
      _future = _fetch();
    });
    try {
      await _future;
    } catch (_) {
      // The FutureBuilder displays refresh failures.
    }
  }

  void _selectBox(ForumPmBox box) {
    if (box == _box) return;
    setState(() {
      _slide = (box.index - _box.index).sign;
      _box = box;
      _pagePath = null;
      _future = _fetch();
    });
  }

  void _openPage(String path) {
    setState(() {
      _pagePath = path;
      _future = _fetch();
    });
  }

  Future<void> _openMessage(ForumPmSummary message) async {
    final result = await Navigator.of(context).push<ForumPmActionResult>(
      MaterialPageRoute(
        builder: (_) => PmDetailScreen(
          repository: widget.repository,
          message: message,
        ),
      ),
    );
    // Incoming detail and chatlog can change read state even after a failed action.
    if (mounted) await _refresh(result);
  }

  Future<void> _compose() async {
    final result = await Navigator.of(context).push<ForumPmActionResult>(
      MaterialPageRoute(
        builder: (_) => PmComposeScreen(repository: widget.repository),
      ),
    );
    if (mounted && result != null) await _refresh(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('短消息'),
              actions: [
                IconButton(
                  tooltip: '写消息',
                  onPressed: _compose,
                  icon: Icon(Icons.edit_outlined),
                ),
              ],
            ),
      floatingActionButton: widget.embedded
          ? FloatingActionButton(
              tooltip: '写消息',
              onPressed: _compose,
              child: const Icon(Icons.edit_outlined),
            )
          : null,
      body: SafeArea(
        top: false,
        child: AppContentWidth(
          maxWidth: AppWidths.list,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ForumPmBox>(
                    // Text-only segments stay on one line at large text.
                    segments: const [
                      ButtonSegment(
                        value: ForumPmBox.inbox,
                        label: Text('收件箱'),
                      ),
                      ButtonSegment(
                        value: ForumPmBox.sendbox,
                        label: Text('发件箱'),
                      ),
                      ButtonSegment(
                        value: ForumPmBox.scout,
                        // Short enough for one line at large text (D§7).
                        label: Text('跟踪'),
                      ),
                    ],
                    showSelectedIcon: false,
                    selected: {_box},
                    onSelectionChanged: (values) => _selectBox(values.single),
                  ),
                ),
              ),
              Divider(height: 1, color: AppColors.border),
              Expanded(
                child: AppSwitcher(
                  direction: _slide,
                  child: FutureBuilder<ForumPmPage>(
                    key: ValueKey(_box),
                    future: _future,
                    builder: (context, snapshot) => AppSwitcher(
                      child: snapshot.hasError
                          ? AsyncErrorView(
                              key: const ValueKey('error'),
                              title: '短消息加载失败',
                              message: forumErrorText(snapshot.error),
                              onRetry: _refresh,
                            )
                          : !snapshot.hasData
                              ? const ThreadListSkeleton(
                                  key: ValueKey('loading'), itemCount: 6)
                              : RefreshIndicator(
                                  key: const ValueKey('list'),
                                  color: AppColors.brand,
                                  onRefresh: _refresh,
                                  child: _PmList(
                                    page: snapshot.data!,
                                    onOpen: _openMessage,
                                    onPage: _openPage,
                                  ),
                                ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PmList extends StatelessWidget {
  const _PmList({
    required this.page,
    required this.onOpen,
    required this.onPage,
  });

  final ForumPmPage page;
  final ValueChanged<ForumPmSummary> onOpen;
  final ValueChanged<String> onPage;

  @override
  Widget build(BuildContext context) {
    // Unread shows as dots on the tabs and rows, so no banner.
    final children = <Widget>[];
    if (page.messages.isEmpty) {
      children.add(const EmptyStateView(
        icon: Icons.mark_email_read_outlined,
        title: '暂无消息',
      ));
    } else if (page.box == ForumPmBox.inbox) {
      // The inbox page holds both groups; split them without reordering.
      for (final (type, label) in const [
        (ForumPmType.personal, '个人消息'),
        (ForumPmType.broadcast, '群发消息'),
      ]) {
        final group = page.messages.where((m) => m.type == type).toList();
        if (group.isEmpty) continue;
        if (children.isNotEmpty) {
          children.add(const SizedBox(height: AppSpace.xl));
        }
        children.add(_group(group, label: label));
      }
    } else {
      children.add(_group(page.messages));
    }
    if (page.pageLinks.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: AppSpace.md),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final link in page.pageLinks)
              OutlinedButton(
                onPressed: () => onPage(link.path),
                child: Text(link.label),
              ),
          ],
        ),
      ));
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      // Clear of the 写消息 FAB.
      padding: const EdgeInsets.only(top: AppSpace.md, bottom: 88),
      children: children,
    );
  }

  // One surface per group, rows divided like any thread list (D§8).
  Widget _group(List<ForumPmSummary> messages, {String? label}) => AppGroup(
        label: label,
        dividerIndent: AppSpace.lg,
        children: [
          for (final message in messages)
            ForumThreadRow(
              title: message.title,
              meta: [
                if (message.peer.isNotEmpty) message.peer,
                if (message.time.isNotEmpty) message.time,
                if (message.recipientRead case final read?)
                  read ? '对方已读' : '对方未读',
              ],
              emphasized: message.unread,
              trailing: message.unread
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpace.md),
                      child: Icon(
                        Icons.circle,
                        size: 8,
                        color: AppColors.noticeDot,
                        semanticLabel: '未读',
                      ),
                    )
                  : null,
              onTap: () => onOpen(message),
            ),
        ],
      );
}
