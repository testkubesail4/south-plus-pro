import 'package:flutter/material.dart';

import '../../models/forum_pm_models.dart';
import '../../services/forum_repository.dart';
import '../../services/loading_preferences.dart';
import '../../theme/app_theme.dart';
import '../common/app_switcher.dart';
import '../common/async_state_view.dart';
import '../common/content_width.dart';
import '../common/grouped_list.dart';
import '../common/page_end.dart';
import '../common/session_bound.dart';
import '../common/thread_row.dart';
import 'pm_compose_screen.dart';
import 'pm_detail_screen.dart';
import '../common/more_pages.dart';

class PmBoxScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final view = _PmBoxView(
      repository: repository,
      embedded: embedded,
      initialPath: initialPath,
    );
    // The shell replaces embedded tabs itself; it owns the root route.
    return embedded
        ? view
        : SessionBound(repository: repository, title: '短消息', child: view);
  }
}

class _PmBoxView extends StatefulWidget {
  const _PmBoxView({
    required this.repository,
    required this.embedded,
    this.initialPath,
  });

  final ForumRepository repository;
  final bool embedded;
  final String? initialPath;

  @override
  State<_PmBoxView> createState() => _PmBoxViewState();
}

String? _messageIdentity(ForumPmSummary message) =>
    message.id.isEmpty ? null : '${message.type.name}:${message.id}';

class _PmBoxViewState extends State<_PmBoxView> {
  ForumPmBox _box = ForumPmBox.inbox;
  // Which way the last box change moved along 收件箱 · 发件箱 · 跟踪.
  int _slide = 0;
  String? _pagePath;
  late Future<ForumPmPage> _future;
  // The page the list starts with, once read.
  ForumPmPage? _first;
  int _reads = 0;
  var _scroll = ScrollController();
  final _leftScrolls = <ScrollController>[];
  late final _more = MorePages<ForumPmPage>(
    fetch: (path) => widget.repository.fetchPmBox(_box, pagePath: path),
    nextOf: (page) => page.nextPagePath,
    idsOf: (page) => [
      for (final message in page.messages) _messageIdentity(message),
    ],
    changed: () {
      if (mounted) setState(() {});
    },
    domain: LoadingDomain.pm,
  );

  @override
  void initState() {
    super.initState();
    if (widget.initialPath case final path?) _openPath(path);
    _future = _fetch();
    _scroll.addListener(_maybeLoadMore);
    LoadingPreferences.notifier.addListener(_onLoadingModeChanged);
    if (!LoadingPreferences.isReady) LoadingPreferences.load().ignore();
  }

  @override
  void dispose() {
    LoadingPreferences.notifier.removeListener(_onLoadingModeChanged);
    _scroll.dispose();
    for (final scroll in _leftScrolls) {
      scroll.dispose();
    }
    super.dispose();
  }

  void _maybeLoadMore() => _more.maybeLoad(_first, _scroll);

  // The footer follows the mode; a page already on its way still lands.
  // 自动接续 starts at the next scroll to the end, never by itself.
  void _onLoadingModeChanged() {
    if (mounted) setState(() {});
  }

  Future<ForumPmPage> _fetch() {
    if (_reads > 0) {
      // An outgoing list keeps its own position until it finishes fading.
      _leftScrolls.removeWhere((scroll) {
        if (scroll.hasClients) return false;
        scroll.dispose();
        return true;
      });
      _leftScrolls.add(_scroll..removeListener(_maybeLoadMore));
      _scroll = ScrollController()..addListener(_maybeLoadMore);
    }
    final read = ++_reads;
    _first = null;
    _more.reset();
    return widget.repository.fetchPmBox(_box, pagePath: _pagePath).then((page) {
      if (mounted && read == _reads) {
        _first = page;
        // A page too short to scroll reads on by itself.
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
      }
      return page;
    });
  }

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
                child: FutureBuilder<ForumPmPage>(
                  future: _future,
                  builder: (context, snapshot) {
                    final waiting =
                        snapshot.connectionState != ConnectionState.done;
                    return AppSwitcher(
                      id: (
                        _box,
                        waiting
                            ? 'loading'
                            : snapshot.hasError
                                ? 'error'
                                : snapshot.data
                      ),
                      direction: _slide,
                      child: !waiting && snapshot.hasError
                          ? AsyncErrorView(
                              key: const ValueKey('error'),
                              title: '短消息加载失败',
                              message: forumErrorText(snapshot.error),
                              onRetry: _refresh,
                            )
                          : waiting || !snapshot.hasData
                              ? const ThreadListSkeleton(
                                  key: ValueKey('loading'), itemCount: 6)
                              : RefreshIndicator(
                                  key: const ValueKey('list'),
                                  color: AppColors.brand,
                                  onRefresh: _refresh,
                                  child: _PmList(
                                    pages: [snapshot.data!, ..._more.pages],
                                    scroll: _scroll,
                                    footer: _footer(snapshot.data!),
                                    onOpen: _openMessage,
                                    onPage: _openPage,
                                  ),
                                ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _footer(ForumPmPage first) {
    final last = _more.pages.isEmpty ? first : _more.pages.last;
    final next = last.nextPagePath;
    // Any page link the forum showed means there are other pages.
    if (next == null &&
        _more.pages.isEmpty &&
        first.currentPage <= 1 &&
        first.pageLinks.isEmpty) {
      return null;
    }
    return PageEndFooter(
      next: next == null ? null : last.currentPage + 1,
      // The forum gives no page count, so no end is claimed.
      endConfirmed: false,
      manual: !_more.continuous,
      loading: _more.loading,
      failed: _more.error != null,
      error: _more.error,
      paused: _more.paused,
      // 手动翻页 turns to the next page alone; 自动接续 appends.
      onNext: next == null
          ? null
          : !_more.continuous
              ? () => _openPage(next)
              : () => _more.retry(first, _scroll),
    );
  }
}

class _PmList extends StatelessWidget {
  const _PmList({
    required this.pages,
    required this.scroll,
    required this.footer,
    required this.onOpen,
    required this.onPage,
  });

  /// The first page, then those 自动接续 appended.
  final List<ForumPmPage> pages;
  final ScrollController scroll;
  final Widget? footer;
  final ValueChanged<ForumPmSummary> onOpen;
  final ValueChanged<String> onPage;

  @override
  Widget build(BuildContext context) {
    // Unread shows as dots on the tabs and rows, so no banner.
    final children = <Widget>[];
    // The links of the last page read, so none leads back.
    final page = pages.last;
    final seen = <String>{};
    for (final (i, shown) in pages.indexed) {
      final messages = [
        for (final m in shown.messages)
          if (!MorePages.repeats(seen, _messageIdentity(m))) m,
      ];
      if (i > 0) children.add(PageBoundary(page: shown.currentPage));
      if (messages.isEmpty) {
        // No footer: the forum has no other page, so the box is empty.
        if (footer == null) {
          children.add(const EmptyStateView(
            icon: Icons.mark_email_read_outlined,
            title: '暂无消息',
          ));
        } else if (shown.messages.isEmpty) {
          children.add(const PageEmptyNote('本页没有消息'));
        }
      } else if (shown.box == ForumPmBox.inbox) {
        // The inbox page holds both groups; split them without reordering.
        var first = true;
        for (final (type, label) in const [
          (ForumPmType.personal, '个人消息'),
          (ForumPmType.broadcast, '群发消息'),
        ]) {
          final group = messages.where((m) => m.type == type).toList();
          if (group.isEmpty) continue;
          if (!first) children.add(const SizedBox(height: AppSpace.xl));
          first = false;
          children.add(_group(group, label: label));
        }
      } else {
        children.add(_group(messages));
      }
    }
    if (footer case final footer?) children.add(footer);
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
      controller: scroll,
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
