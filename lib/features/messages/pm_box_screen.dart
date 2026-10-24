import 'package:flutter/foundation.dart';
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
import '../common/sub_tabs.dart';
import '../common/thread_row.dart';
import 'pm_compose_screen.dart';
import 'pm_detail_screen.dart';
import 'pm_peer_meta.dart';
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
  // Quiet rereads are numbered as they start. One lands on its page (-1: the
  // first, else the index of an appended one) only if no later-started one
  // has landed there, so newer data always wins and a newer reread that
  // fails hides nothing. Rereads of appended pages numbered up to [_dropped]
  // read pages a write has since dropped; an explicit load ([_reads])
  // retires everything quiet.
  final _landed = <int, int>{};
  int _quietCount = 0;
  int _dropped = 0;
  // The newest accepted write; an older one's reread settles to nothing.
  int _actions = 0;
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
    widget.repository.pmInbox.addListener(_onInboxSnapshot);
  }

  @override
  void dispose() {
    widget.repository.pmInbox.removeListener(_onInboxSnapshot);
    LoadingPreferences.notifier.removeListener(_onLoadingModeChanged);
    _scroll.dispose();
    for (final scroll in _leftScrolls) {
      scroll.dispose();
    }
    super.dispose();
  }

  void _maybeLoadMore() => _more.maybeLoad(_first, _scroll);

  // A fresher inbox first page read elsewhere (a background check) swaps in
  // quietly, but only while the reader is at the top of a one-page inbox:
  // rows never move under someone reading further down.
  void _onInboxSnapshot() {
    final page = widget.repository.pmInbox.value;
    final first = _first;
    if (!mounted ||
        page == null ||
        first == null ||
        identical(page, first) ||
        _box != ForumPmBox.inbox ||
        _pagePath != null ||
        _more.pages.isNotEmpty ||
        (_scroll.hasClients && _scroll.offset > 0)) {
      return;
    }
    setState(() {
      _landed[-1] = ++_quietCount;
      _showQuietly(page, null);
    });
  }

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
    final landed = _landed[-1];
    return widget.repository.fetchPmBox(_box, pagePath: _pagePath).then((page) {
      // A write's reread may already have put a newer page in its place.
      if (mounted && read == _reads && _landed[-1] == landed) {
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

  // Coming back keeps the list as left: no skeleton, no transition. Only what
  // the visit changed on the site is read again, in place.
  Future<void> _openMessage(ForumPmSummary message) async {
    var read = false;
    var wrote = false;
    final result = await Navigator.of(context).push<ForumPmActionResult>(
      MaterialPageRoute(
        builder: (_) => PmDetailScreen(
          repository: widget.repository,
          message: message,
          onRead: () => read = true,
          onWrite: () => wrote = true,
        ),
      ),
    );
    if (!mounted) return;
    // A write that failed may still have reached the site.
    if (result != null || wrote) return _afterAction(result);
    // Reading an incoming message clears its unread mark on the site.
    if (read && message.box == ForumPmBox.inbox) await _revalidate(message);
  }

  Future<void> _compose() async {
    final result = await Navigator.of(context).push<ForumPmActionResult>(
      MaterialPageRoute(
        builder: (_) => PmComposeScreen(repository: widget.repository),
      ),
    );
    if (mounted && result != null) await _afterAction(result);
  }

  /// Reads again the shown page holding [message] and swaps it in place; the
  /// other pages and the scroll position stay, and a failure keeps the rows.
  // shortcut: a chatlog read also clears rows on other loaded pages, which
  // show it at the next refresh; refetch them all if that proves confusing.
  Future<void> _revalidate(ForumPmSummary message) async {
    final first = _first;
    if (first == null) return;
    final id = _messageIdentity(message);
    bool holds(ForumPmPage page) => page.messages.any((m) =>
        identical(m, message) || (id != null && _messageIdentity(m) == id));
    // -1 is the first shown page.
    final index = holds(first) ? -1 : _more.pages.indexWhere(holds);
    if (index == -1 && !holds(first)) return;
    final path = index < 0
        ? _pagePath
        : _more.nextOf(index == 0 ? first : _more.pages[index - 1]);
    // No path is the first page, never an appended one's.
    if (index >= 0 && path == null) return;
    final reads = _reads;
    final token = ++_quietCount;
    final ForumPmPage page;
    try {
      page = await widget.repository.fetchPmBox(_box, pagePath: path);
    } catch (_) {
      return;
    }
    if (!mounted || reads != _reads || token < (_landed[index] ?? 0)) return;
    if (index >= 0 && (token <= _dropped || index >= _more.pages.length)) {
      return;
    }
    setState(() {
      _landed[index] = token;
      if (index < 0) {
        _showQuietly(page, path);
      } else {
        _more.pages[index] = page;
      }
    });
  }

  /// After an accepted write the box reads its page again, quietly unless the
  /// site sends it to another box; the pages appended after it are dropped.
  Future<void> _afterAction(ForumPmActionResult? result) async {
    final (box, shownPath) = (_box, _pagePath);
    if (result?.refreshPath case final path?) _openPath(path);
    if (_box != box) {
      _slide = (_box.index - box.index).sign;
      return _refresh();
    }
    // The list keeps the page it shows until the site's answer replaces it.
    final path = _pagePath;
    _pagePath = shownPath;
    final reads = _reads;
    final action = ++_actions;
    final token = ++_quietCount;
    ForumPmPage? page;
    Object? failure;
    try {
      page = await widget.repository.fetchPmBox(_box, pagePath: path);
    } catch (error) {
      failure = error;
    }
    if (!mounted || reads != _reads || action != _actions) return;
    setState(() {
      // The write moved the rows after the first page, so they go however
      // the reread ends, and so do rereads of them begun so far and pages
      // appended since. Until now they stayed on screen: the list did not
      // jump.
      _more.reset();
      _dropped = _quietCount;
      if (page != null && token > (_landed[-1] ?? 0)) {
        _landed[-1] = token;
        _showQuietly(page, path);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('短消息刷新失败：${forumErrorText(failure)}'),
      ));
    }
  }

  // A settled future: the list swaps its first page, read from [path],
  // without a loading state, and the switcher id (the load generation)
  // stays, so nothing animates.
  void _showQuietly(ForumPmPage page, String? path) {
    _first = page;
    _pagePath = path;
    _future = SynchronousFuture(page);
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
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                child: SubTabs<ForumPmBox>(
                  tabs: const [
                    (ForumPmBox.inbox, '收件箱'),
                    (ForumPmBox.sendbox, '发件箱'),
                    (ForumPmBox.scout, '跟踪'),
                  ],
                  selected: _box,
                  onSelected: _selectBox,
                ),
              ),
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
                                : _reads
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
                                    repository: widget.repository,
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
    required this.repository,
    required this.pages,
    required this.scroll,
    required this.footer,
    required this.onOpen,
    required this.onPage,
  });

  final ForumRepository repository;

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
              metaLine: PmPeerMeta(
                repository: repository,
                peer: message.peer,
                peerUid: message.peerUid,
                rest: [
                  message.time,
                  if (message.recipientRead case final read?)
                    read ? '对方已读' : '对方未读',
                ],
              ),
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
