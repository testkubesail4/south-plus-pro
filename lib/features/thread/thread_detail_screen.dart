import 'dart:async' show scheduleMicrotask;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show
        BoxHitTestResult,
        ContainerRenderObjectMixin,
        MultiChildLayoutParentData,
        RenderBoxContainerDefaultsMixin,
        ScrollDirection;

import '../../models/forum_models.dart';
import '../../services/external_link_launcher.dart';
import '../../services/attachment_saver.dart';
import '../../services/perf_trace.dart';
import '../../services/forum_blocking_settings.dart';
import '../../services/forum_repository.dart';
import '../../services/thread_paging_settings.dart';
import '../../services/thread_share_service.dart';
import '../../theme/app_theme.dart';
import '../board/board_thread_list_screen.dart';
import '../common/async_state_view.dart';
import '../common/cached_forum_image.dart';
import '../common/content_width.dart';
import '../common/forum_link_opener.dart';
import '../common/forum_pager.dart';
import '../common/thread_row.dart' show AppTag;
import '../common/user_note.dart';
import '../profile/blocking_settings_screen.dart';
import '../profile/favorite_collections_sheets.dart' show showNewCategoryDialog;
import '../profile/user_profile_screen.dart';
import '../reply/reply_sheet.dart';
import '../search/search_screen.dart';
import 'thread_floor_actions.dart';
import 'thread_page_end_card.dart';
import 'thread_post_body.dart';
import 'thread_render_models.dart';
import 'thread_sale_box_view.dart'
    show ThreadPurchaseScope, ThreadSaleBoxNotice;

class ThreadDetailScreen extends StatefulWidget {
  const ThreadDetailScreen({
    super.key,
    required this.thread,
    required this.repository,
  });

  final ForumThread thread;
  final ForumRepository repository;

  @override
  State<ThreadDetailScreen> createState() => _ThreadDetailScreenState();
}

class _ThreadDetailScreenState extends State<ThreadDetailScreen> {
  final _scrollController = ScrollController();
  final _replyKey = GlobalKey<ReplyComposerState>();
  final Set<String> _buyingSaleBoxes = <String>{};
  // Sale box buy path -> what the last purchase attempt left inside the box.
  Map<String, ThreadSaleBoxNotice> _saleBoxNotices = const {};
  // Post key -> block paths a purchase unlocked (purchaseRevealPaths), and
  // the reveals that already ran: a refresh or a scroll never replays one.
  final _purchaseReveals = <String, Set<String>>{};
  final _revealPlayed = <String>{};
  late final _notes = UserNoteController(widget.repository);
  final Set<String> _loadingQuoteDrafts = <String>{};
  final Map<String, ThreadFavoriteState> _favoriteOverrides =
      <String, ThreadFavoriteState>{};
  bool _favoriteBusy = false;
  // Moves when the session or the thread changes: an open category sheet
  // closes and a favorite call still in flight is ignored.
  final _favoriteFlow = ValueNotifier<int>(0);
  bool _savingAttachment = false;
  // The reply box docks under the list instead of ending it, so paging
  // never moves it and opening it never moves the reading position.
  bool _composerOpen = false;
  // Hidden floors the reader chose to see anyway: cleared by a new page or
  // thread load and by a session change.
  final _revealedPosts = Set<Object>.identity();
  bool _loading = true;
  Object? _loadError;
  late ForumThread _thread;
  String? _authorFilterName;
  ThreadDetail? _detail;
  int _page = 1;
  int? _visiblePage;
  int _loadRunId = 0;
  final _purchaseRefreshRuns = <int, int>{};
  ThreadDetail? _compiledDetail;
  ThreadPostRenderModel _openingPostRenderModel = ThreadPostRenderModel.empty;
  Map<ThreadReply, String> _replyStableIds = <ThreadReply, String>{};
  Map<String, ThreadPostRenderModel> _replyRenderModels =
      <String, ThreadPostRenderModel>{};
  List<ThreadDetailListEntry> _detailEntries = const <ThreadDetailListEntry>[];
  bool _onlyOriginalPosterActive = false;
  bool _authorFilterActive = false;
  int _visibleFloorCount = 0;
  // One-shot URL fragment target, consumed by the first successful load.
  String? _pendingAnchor;
  Object? _anchorTarget;
  final _anchorKey = GlobalKey(debugLabel: 'thread-anchor-target');
  // One-shot: reveal the last reply after the next load (最新回复).
  bool _pendingLatest = false;
  // Pages appended below the loaded page by scrolling to the end.
  final _morePages = <ThreadDetail>[];
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  final _replyPages = Map<ThreadReply, int>.identity();
  // Mounted posts (ThreadDetail = opening post, or a ThreadReply) for
  // finding the post at the top of the screen.
  final _mountedPosts = Map<Object, BuildContext>.identity();

  @override
  void initState() {
    super.initState();
    _thread = widget.thread;
    _pendingAnchor = _fragmentOf(widget.thread.url);
    ThreadPagingSettings.notifier.addListener(_onPagingSettingChanged);
    widget.repository.blocking.notifier.addListener(_onBlockingChanged);
    widget.repository.sessionEpoch.addListener(_onSessionChanged);
    _notes.addListener(_onNotesChanged);
    _openAtSavedPosition();
  }

  static final _explicitPage = RegExp(r'(?:^|[?&\-])page[-=](\d+|e)');

  /// A plain thread link resumes where the reader stopped last time; links
  /// to a page or floor open exactly what they point to.
  Future<void> _openAtSavedPosition() async {
    try {
      await ThreadPagingSettings.load();
    } catch (_) {
      ThreadPagingSettings.notifier.value = false;
    }
    if (!mounted) return;
    final page = _explicitPage.firstMatch(widget.thread.url)?.group(1);
    ThreadReadPosition? position;
    if (_pendingAnchor == null && page == null) {
      try {
        position = await widget.repository.loadThreadReadPosition(_thread);
      } catch (_) {
        // An unreadable saved position just opens the first page.
      }
    }
    if (!mounted) return;
    final resumes = position != null &&
        (position.page > 1 || (position.anchor ?? 'tpc') != 'tpc');
    if (!resumes) {
      await _loadPage(1);
      return;
    }
    _pendingAnchor = position.anchor;
    await _loadPage(position.page);
    if (!mounted || _detail == null) return;
    _messenger.showSnackBar(SnackBar(
      content: Text('已回到上次阅读位置（第 ${position.page} 页）'),
      action: SnackBarAction(label: '从头看', onPressed: _jumpToFirst),
      // An action alone would keep it on screen until dismissed.
      persist: false,
    ));
  }

  // The thread's own messenger: its notices stay on this screen, never
  // queue behind or follow the reader to other screens.
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  ScaffoldMessengerState get _messenger =>
      _messengerKey.currentState ?? ScaffoldMessenger.of(context);

  static String? _fragmentOf(String url) {
    final fragment = Uri.tryParse(url)?.fragment ?? '';
    return fragment.isEmpty ? null : fragment;
  }

  @override
  void didUpdateWidget(covariant ThreadDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thread.url == widget.thread.url) return;
    _favoriteFlow.value++;
    _favoriteBusy = false;
    _favoriteOverrides.clear();
    _thread = widget.thread;
    _authorFilterName = null;
    _detail = null;
    _page = 1;
    _pendingAnchor = _fragmentOf(widget.thread.url);
    _anchorTarget = null;
    _morePages.clear();
    _revealedPosts.clear();
    _purchaseReveals.clear();
    _revealPlayed.clear();
    _saleBoxNotices = const {};
    _resetDetailRenderState();
    _loadPage(1);
  }

  void _onNotesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    await _loadPage(_page, showSnackBarOnError: false);
  }

  Future<void> _loadPage(
    int page, {
    bool scrollToTop = false,
    bool showSnackBarOnError = true,
  }) async {
    final normalizedPage = page < 1 ? 1 : page;
    final runId = ++_loadRunId;
    _purchaseRefreshRuns.clear();
    setState(() {
      _loading = true;
      _loadError = null;
      // A replacement load supersedes any page being appended.
      _loadingMore = false;
      _loadMoreFailed = false;
      if (_detail != null) _recomputeDetailRenderState();
    });
    try {
      final detail = await widget.repository.fetchThreadDetail(
        _thread,
        page: normalizedPage,
      );
      if (!mounted || runId != _loadRunId) return;
      final anchor = _pendingAnchor;
      final latest = _pendingLatest;
      setState(() {
        _detail = detail;
        _thread = detail.thread;
        _page = detail.pagination.currentPage;
        _visiblePage = null;
        _loading = false;
        _pendingAnchor = null;
        _pendingLatest = false;
        _morePages.clear();
        _revealedPosts.clear();
        _loadingMore = false;
        _loadMoreFailed = false;
        _anchorTarget = latest
            ? (detail.replies.isEmpty ? detail : detail.replies.last)
            : anchor == null
                ? null
                : _anchorTargetIn(detail, anchor);
        _recomputeDetailRenderState();
      });
      if (anchor != null || latest) {
        // The reveal steps down from the top of the newly loaded page.
        if (_scrollController.hasClients) _scrollController.jumpTo(0);
        _revealAnchor();
      } else if (scrollToTop && _scrollController.hasClients) {
        await _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    } catch (error) {
      if (!mounted || runId != _loadRunId) return;
      _pendingLatest = false;
      setState(() {
        _loadError = error;
        _loading = false;
      });
      if (_detail != null && showSnackBarOnError) {
        _messenger.showSnackBar(
          SnackBar(content: Text('页面加载失败：$error')),
        );
      }
    }
  }

  /// The post whose parsed DOM anchors contain [anchor] exactly; never guessed.
  static Object? _anchorTargetIn(ThreadDetail detail, String anchor) {
    if (detail.bodyAnchors.contains(anchor)) return detail;
    for (final reply in detail.replies) {
      if (reply.anchors.contains(anchor)) return reply;
    }
    return null;
  }

  /// Steps the lazy list forward until the target row is mounted, then
  /// reveals it; falls back to a notice on the page actually shown.
  Future<void> _revealAnchor() async {
    for (var attempt = 0; _anchorTarget != null && attempt < 200; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final target = _anchorKey.currentContext;
      if (target != null) {
        await Scrollable.ensureVisible(target);
        // shortcut: re-aligns once after the next layout; images that finish
        // loading later above the target can still shift it.
        await WidgetsBinding.instance.endOfFrame;
        final settled = _anchorKey.currentContext;
        if (mounted && settled != null) await Scrollable.ensureVisible(settled);
        return;
      }
      if (!_scrollController.hasClients) continue;
      final position = _scrollController.position;
      if (position.pixels >= position.maxScrollExtent) break;
      position.jumpTo(math.min(
        position.pixels + position.viewportDimension,
        position.maxScrollExtent,
      ));
    }
    if (!mounted) return;
    _messenger.showSnackBar(
      const SnackBar(content: Text('未找到指定楼层，已显示所在页')),
    );
  }

  ThreadDetail? get _lastLoaded =>
      _morePages.isEmpty ? _detail : _morePages.last;

  void _maybeLoadMore() {
    if (!ThreadPagingSettings.notifier.value) return;
    final last = _lastLoaded;
    if (last == null ||
        _loading ||
        _loadingMore ||
        _loadMoreFailed ||
        !last.pagination.hasNext ||
        !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.extentAfter < position.viewportDimension * 1.5) {
      _loadMore();
    }
  }

  /// Appends the page after the last loaded one.
  Future<void> _loadMore() async {
    final last = _lastLoaded;
    if (last == null || _loadingMore) return;
    final runId = _loadRunId;
    final page = last.pagination.currentPage + 1;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
      _recomputeDetailRenderState();
    });
    try {
      final detail = await widget.repository.fetchThreadDetail(
        _thread,
        page: page,
      );
      if (!mounted || runId != _loadRunId) return;
      setState(() {
        _loadingMore = false;
        // A short or redirected answer must not repeat a loaded page.
        if (detail.pagination.currentPage > last.pagination.currentPage) {
          _addRenderModels(detail, idPrefix: 'p$page:');
          _morePages.add(detail);
        } else {
          _loadMoreFailed = true;
        }
        _recomputeDetailRenderState();
      });
    } catch (_) {
      if (!mounted || runId != _loadRunId) return;
      setState(() {
        _loadingMore = false;
        _loadMoreFailed = true;
        _recomputeDetailRenderState();
      });
    }
  }

  void _retryLoadMore() {
    _loadMoreFailed = false;
    _loadMore();
  }

  void _addRenderModels(ThreadDetail detail, {String idPrefix = ''}) {
    for (var index = 0; index < detail.replies.length; index++) {
      final reply = detail.replies[index];
      final stableId = '$idPrefix${threadReplyStableId(reply, index: index)}';
      _replyStableIds[reply] = stableId;
      _replyRenderModels[stableId] =
          ThreadPostRenderModel.fromSegments(reply.segments);
      _replyPages[reply] = detail.pagination.currentPage;
    }
  }

  /// First floor: the opening post on page 1.
  Future<void> _jumpToFirst() async {
    if (_detail?.pagination.currentPage == 1) {
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
      return;
    }
    final url = widget.repository.firstThreadPageUrl(_thread);
    if (url == null) return;
    _thread = _thread.copyWith(url: url);
    _pendingAnchor = _fragmentOf(url);
    await _loadPage(1);
  }

  /// Latest floor: the last reply on the last page.
  Future<void> _jumpToLatest() async {
    final last = _lastLoaded;
    if (last != null && !last.pagination.hasNext) {
      setState(() {
        _anchorTarget = last.replies.isEmpty ? last : last.replies.last;
        _recomputeDetailRenderState();
      });
      await _revealAnchor();
      return;
    }
    final url = widget.repository.latestThreadPageUrl(_thread);
    if (url == null) return;
    _thread = _thread.copyWith(url: url);
    _pendingLatest = true;
    await _loadPage(1);
  }

  Future<void> _scrollToEdge({required bool top}) async {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (top) {
      await position.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      return;
    }
    // The lazy list's end grows as rows on the way get laid out.
    for (var i = 0; i < 8 && position.pixels < position.maxScrollExtent; i++) {
      await position.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    // ...or shrinks once they have: settle on the real end, not past it.
    if (position.pixels > position.maxScrollExtent) {
      position.jumpTo(position.maxScrollExtent);
    }
    // Reaching the end on request is reading to the end.
    if (mounted) _maybeLoadMore();
  }

  // A wheel turned at the very end moves nothing, so no scroll notification
  // follows; the turn itself asks for more.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && event.scrollDelta.dy > 0) {
      _maybeLoadMore();
    }
  }

  // Only the reader's own scrolling loads more; opening a thread or jumping
  // to a floor never requests extra pages.
  bool _userScrolling = false;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    switch (notification) {
      case UserScrollNotification(:final direction):
        _userScrolling = direction != ScrollDirection.idle;
      // Pulling at the very end overscrolls instead of updating.
      case ScrollUpdateNotification() || OverscrollNotification()
          when _userScrolling:
        _maybeLoadMore();
      case ScrollEndNotification():
        _saveReadPosition(notification);
      default:
    }
    return false;
  }

  /// Remembers the post at the top of the list once scrolling stops.
  void _saveReadPosition(ScrollEndNotification notification) {
    // A jump notifies before the new layout; measure after the next frame.
    final scrollable = notification.context;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted && scrollable != null && scrollable.mounted) {
          _saveTopPost(scrollable);
        }
      })
      ..ensureVisualUpdate();
  }

  void _saveTopPost(BuildContext scrollable) {
    final listBox = scrollable.findRenderObject();
    if (listBox is! RenderBox || !listBox.attached) return;
    final top = listBox.localToGlobal(Offset.zero).dy;
    Object? first;
    var firstY = double.infinity;
    _mountedPosts.forEach((post, context) {
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y + box.size.height > top && y < firstY) {
        first = post;
        firstY = y;
      }
    });
    final position = switch (first) {
      final ThreadDetail detail => ThreadReadPosition(
          page: detail.pagination.currentPage,
          anchor: detail.bodyAnchors.contains('tpc') ? 'tpc' : null,
        ),
      final ThreadReply reply when _replyPages[reply] != null =>
        ThreadReadPosition(
          page: _replyPages[reply]!,
          // Native post ids only; read_/fl- aliases are not stored.
          anchor:
              reply.anchors.where(RegExp(r'^[1-9]\d*$').hasMatch).firstOrNull,
        ),
      _ => null,
    };
    if (position != null && position.page != _visiblePage) {
      setState(() => _visiblePage = position.page);
    }
    if (position != null) {
      widget.repository
          .saveThreadReadPosition(_thread, position)
          .catchError((Object _) {});
    }
  }

  void _postMounted(Object post, BuildContext context, bool mounted) {
    if (mounted) {
      _mountedPosts[post] = context;
    } else if (identical(_mountedPosts[post], context)) {
      _mountedPosts.remove(post);
    }
  }

  Future<void> _goToPage(int page) async {
    final detail = _detail;
    if (detail != null) {
      final target = page.clamp(1, detail.pagination.totalPages).toInt();
      if (target == _page) {
        // Appended pages may sit below: return to this page's top.
        if (_morePages.isNotEmpty) await _scrollToEdge(top: true);
        return;
      }
      await _loadPage(target, scrollToTop: true);
      return;
    }
    await _loadPage(page, scrollToTop: true);
  }

  Future<void> _showAuthorPosts(ThreadReply reply) async {
    final authorPostsUrl = reply.authorPostsUrl;
    if (authorPostsUrl == null || authorPostsUrl.isEmpty) return;
    await _showAuthorFilter(authorPostsUrl, reply.author);
  }

  /// Server uid filtering only: a local name filter over an unfiltered page
  /// keeps unfiltered page counts and can leave whole pages empty.
  Future<void> _showOriginalPosterPosts(ForumThread thread) async {
    final url = widget.repository.originalPosterPostsUrl(thread);
    if (url == null) {
      _messenger.showSnackBar(
        const SnackBar(content: Text('无法只看楼主：缺少楼主身份')),
      );
      return;
    }
    await _showAuthorFilter(url, thread.author ?? '楼主');
  }

  Future<void> _showAuthorFilter(String authorPostsUrl, String author) async {
    final current = _detail?.thread ?? _thread;
    setState(() {
      _thread = current.copyWith(url: authorPostsUrl);
      _authorFilterName = author;
      _recomputeDetailRenderState();
    });
    await _loadPage(1, scrollToTop: true);
  }

  // Covers filters chosen here and uid deep links alike; never reloads the
  // incoming URL, which may itself carry the filter or a page/fragment.
  Future<void> _clearAuthorFilter() async {
    final current = _detail?.thread ?? _thread;
    final url = widget.repository.unfilteredThreadUrl(current);
    if (url == null) return;
    setState(() {
      _thread = current.copyWith(url: url);
      _authorFilterName = null;
      _recomputeDetailRenderState();
    });
    await _loadPage(1, scrollToTop: true);
  }

  void _resetDetailRenderState() {
    _compiledDetail = null;
    _replyPages.clear();
    _openingPostRenderModel = ThreadPostRenderModel.empty;
    _replyStableIds = <ThreadReply, String>{};
    _replyRenderModels = <String, ThreadPostRenderModel>{};
    _detailEntries = const <ThreadDetailListEntry>[];
    _onlyOriginalPosterActive = false;
    _authorFilterActive = false;
    _visibleFloorCount = 0;
  }

  void _recomputeDetailRenderState() {
    final detail = _detail;
    if (detail == null) {
      _resetDetailRenderState();
      return;
    }

    if (!identical(_compiledDetail, detail)) {
      _compiledDetail = detail;
      _openingPostRenderModel = ThreadPostRenderModel.fromSegments(
        detail.bodySegments,
      );
      _replyStableIds = <ThreadReply, String>{};
      _replyRenderModels = <String, ThreadPostRenderModel>{};
      _replyPages.clear();
      _addRenderModels(detail);
      for (final page in _morePages) {
        _addRenderModels(page, idPrefix: 'p${page.pagination.currentPage}:');
      }
    }

    // Filter state comes from the validated uid in the loaded URL, not names.
    _onlyOriginalPosterActive =
        widget.repository.isOriginalPosterFilter(detail.thread);
    _authorFilterActive =
        widget.repository.unfilteredThreadUrl(detail.thread) != null;

    final visibleReplies = detail.replies;
    final hasOpeningPost = detail.body.trim().isNotEmpty ||
        detail.bodySegments.isNotEmpty ||
        detail.bodyImages.isNotEmpty ||
        detail.bodyLinks.isNotEmpty ||
        detail.bodySaleBoxes.isNotEmpty;
    _visibleFloorCount = visibleReplies.length + (hasOpeningPost ? 1 : 0);

    final last = _lastLoaded!;
    ThreadDetailReplyEntry replyEntry(ThreadReply reply) =>
        ThreadDetailReplyEntry(
          key: identical(_anchorTarget, reply)
              ? _anchorKey
              : ValueKey(
                  'thread-reply-${_replyStableIds[reply] ?? reply.floor ?? reply.author}',
                ),
          reply: reply,
          stableId: _replyStableIds[reply] ?? '',
          renderModel: _replyRenderModels[_replyStableIds[reply]] ??
              ThreadPostRenderModel.empty,
        );

    final entries = <ThreadDetailListEntry>[
      const ThreadDetailTopSpacingEntry(12),
      ThreadDetailOpeningPostEntry(
        key: identical(_anchorTarget, detail)
            ? _anchorKey
            : ValueKey(
                'thread-opening-${detail.thread.url}-${detail.pagination.currentPage}',
              ),
        hasBody: hasOpeningPost,
        renderModel: _openingPostRenderModel,
      ),
      if (_authorFilterActive)
        ThreadDetailAuthorFilterChipEntry(
          key: const ValueKey('thread-author-filter-chip'),
          visibleFloorCount: _visibleFloorCount,
        ),
      const ThreadDetailTopSpacingEntry(16),
      if (_authorFilterActive && _visibleFloorCount == 0)
        const ThreadDetailEmptyStateEntry(
          key: ValueKey('thread-empty-author-filter'),
          title: '没有该作者内容',
          message: '当前筛选结果没有可展示的楼层。',
        ),
      for (final reply in visibleReplies) replyEntry(reply),
      for (final page in _morePages) ...[
        ThreadDetailPageDividerEntry(
          page.pagination.currentPage,
          key: ValueKey('thread-page-${page.pagination.currentPage}'),
        ),
        for (final reply in page.replies) replyEntry(reply),
      ],
      if (_autoLoadNextPage && last.pagination.totalPages > 1)
        ThreadDetailLoadMoreEntry(
          key: const ValueKey('thread-load-more'),
          hasMore: last.pagination.hasNext,
          loading: _loadingMore,
          failed: _loadMoreFailed,
        ),
      ThreadDetailPaginationEntry(
        pagination: last.pagination,
        key: ValueKey(
          'thread-pagination-bottom-${detail.thread.url}-${last.pagination.currentPage}',
        ),
      ),
    ];
    _detailEntries = List<ThreadDetailListEntry>.unmodifiable(entries);
  }

  void _openUserProfile(String userUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          userUrl: userUrl,
          repository: widget.repository,
        ),
      ),
    );
  }

  @override
  void dispose() {
    ThreadPagingSettings.notifier.removeListener(_onPagingSettingChanged);
    widget.repository.blocking.notifier.removeListener(_onBlockingChanged);
    widget.repository.sessionEpoch.removeListener(_onSessionChanged);
    _notes.removeListener(_onNotesChanged);
    _notes.dispose();
    _favoriteFlow.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _showFloorActions(ThreadReply reply, bool openingPost) async {
    final repository = widget.repository;
    final blocking = repository.blocking;
    // Every write below belongs to the session this menu opened in.
    final epoch = repository.sessionEpoch.value;
    bool sameSession() => mounted && repository.sessionEpoch.value == epoch;
    final signedIn = repository.isLoggedIn;
    if (signedIn) {
      // A fresh session may not know its own uid or rules yet (read-only).
      try {
        await repository.ensureAccountIdentity();
        await blocking.load();
      } catch (_) {
        // The menu still opens; unavailable items say why.
      }
      if (!sameSession()) return;
    }
    final rules = blocking.notifier.value;
    final uid = reply.authorUid;
    // The opening post is never matched by content (as on the site).
    final contentKey = openingPost ? null : reply.blockContentKey;
    // Both native and local rules are keyed by the signed-in account's uid.
    final accountKnown = blocking.canWriteNative;
    final userBlocked =
        rules.users.any((user) => user.uid == uid && user.userBlocked);
    final avatarBlocked = rules.isAvatarBlocked(uid);
    final contentBlocked = rules.isContentBlocked(contentKey);
    final action = await showThreadFloorActions(
      context,
      author: reply.author,
      floor: reply.floor,
      avatar: _AuthorAvatar(
        author: reply.author,
        avatarUrl: avatarBlocked ? null : reply.authorAvatarUrl,
      ),
      canShowAuthorPosts: reply.authorPostsUrl != null,
      canEditNote: uid != null,
      hasNote: _notes.noteFor(uid) != null,
      block: ThreadFloorBlockState(
        userBlocked: userBlocked,
        avatarBlocked: avatarBlocked,
        contentBlocked: contentBlocked,
        canBlockUser: uid != null && accountKnown,
        canBlockContent: contentKey != null && accountKnown,
        userBlockUnavailableReason: !signedIn
            ? '登录后可同步南+屏蔽配置'
            : !accountKnown
                ? '暂时无法识别当前账号'
                : '无法识别此用户',
        contentBlockUnavailableReason: openingPost
            ? '主题内容不参与内容屏蔽'
            : contentKey == null
                ? null
                : !signedIn
                    ? '登录后可配置'
                    : '暂时无法识别当前账号',
      ),
    );
    if (action == null || !sameSession()) return;
    switch (action) {
      case ThreadFloorAction.showAuthorPosts:
        await _showAuthorPosts(reply);
      case ThreadFloorAction.editNote:
        // The controller reloads itself on the store's revision.
        await showUserNoteEditor(
          context,
          repository: repository,
          uid: uid!,
          name: reply.author,
          note: _notes.noteFor(uid),
        );
      case ThreadFloorAction.manageBlocking:
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => BlockingSettingsScreen(repository: widget.repository),
        ));
      case ThreadFloorAction.blockUser:
        await _applyBlock(
          userBlocked ? '已取消屏蔽此人' : '已屏蔽此人',
          (blocked) => blocking.setUser(uid!, reply.author, blocked: blocked),
          !userBlocked,
          sameSession,
        );
      case ThreadFloorAction.blockAvatar:
        await _applyBlock(
          avatarBlocked ? '已取消屏蔽头像' : '已屏蔽头像',
          (blocked) => blocking.setUser(
            uid!,
            reply.author,
            blocked: blocked,
            avatarOnly: true,
          ),
          !avatarBlocked,
          sameSession,
        );
      case ThreadFloorAction.blockContent:
        await _applyBlock(
          contentBlocked ? '已取消屏蔽此内容' : '已屏蔽相同内容',
          (blocked) => blocking.setContent(contentKey!, blocked: blocked),
          !contentBlocked,
          sameSession,
        );
    }
  }

  /// Applies one rule change, offering to undo it; nothing is written once
  /// the screen or the session that asked for it is gone.
  Future<void> _applyBlock(
    String done,
    Future<void> Function(bool blocked) write,
    bool blocked,
    bool Function() sameSession,
  ) async {
    if (!sameSession()) return;
    try {
      await write(blocked);
      if (!mounted) return;
      _messenger.showSnackBar(SnackBar(
        content: Text(done),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => _applyBlock('已撤销', write, !blocked, sameSession),
        ),
        persist: false,
      ));
    } catch (error) {
      if (!mounted) return;
      // Engine errors carry fixed, response-free messages.
      _messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  /// Opens the docked composer and focuses its content once it shows.
  void _openComposer() {
    if (!_composerOpen) setState(() => _composerOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _replyKey.currentState?.focusContent();
    });
  }

  void _closeComposer() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_composerOpen) setState(() => _composerOpen = false);
  }

  void _replyToFloor(String title) {
    _replyKey.currentState?.replyTo(title);
    _openComposer();
  }

  String _localQuoteDraft(ThreadReply reply) {
    final content = reply.content.length > 300
        ? '${reply.content.substring(0, 300)}...'
        : reply.content;
    final floor = reply.floor == null ? '' : ' ${reply.floor}';
    return '[quote]引用 ${reply.author}$floor：$content[/quote]\n';
  }

  Future<void> _quoteReply(ThreadReply reply) async {
    final quoteUrl = reply.quoteUrl;
    if (quoteUrl == null || quoteUrl.isEmpty) {
      _replyKey.currentState?.insertContent(_localQuoteDraft(reply));
      _openComposer();
      return;
    }
    if (_loadingQuoteDrafts.contains(quoteUrl)) return;

    setState(() {
      _loadingQuoteDrafts.add(quoteUrl);
    });

    try {
      final draft = await widget.repository.fetchQuoteDraft(reply);
      if (!mounted) return;
      _replyKey.currentState?.insertContent(
        draft == null || draft.isEmpty ? _localQuoteDraft(reply) : '$draft\n',
      );
    } catch (error) {
      if (!mounted) return;
      _replyKey.currentState?.insertContent(_localQuoteDraft(reply));
      _messenger.showSnackBar(
        SnackBar(content: Text('引用加载失败，已使用本地引用：$error')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingQuoteDrafts.remove(quoteUrl);
      });
    }
    _openComposer();
  }

  bool get _autoLoadNextPage => ThreadPagingSettings.notifier.value;

  // Reveal choices belong to the account that made them.
  void _onSessionChanged() {
    if (!mounted) return;
    // Another account's purchases are not this one's.
    _favoriteFlow.value++;
    setState(() {
      _favoriteBusy = false;
      // Another account's favorite is not this one's.
      _favoriteOverrides.clear();
      _revealedPosts.clear();
      _saleBoxNotices = const {};
    });
  }

  // Rules apply as they change, here or in 屏蔽配置; nothing is refetched.
  void _onBlockingChanged() {
    if (mounted) setState(() {});
  }

  // 设置 can change while this thread stays open below it.
  void _onPagingSettingChanged() {
    if (mounted && _detail != null) setState(_recomputeDetailRenderState);
  }

  Future<void> _handleReplySubmitted(String result) async {
    _closeComposer();
    _messenger.showSnackBar(
      SnackBar(content: Text('$result，已刷新当前页')),
    );
    await _refresh();
  }

  double? _postY(Object? post) {
    final box = _mountedPosts[post]?.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize
        ? box.localToGlobal(Offset.zero).dy
        : null;
  }

  String _openingPostKey() => 'opening:${_detail?.pagination.currentPage ?? 1}';

  Map<String, ThreadPostRenderModel> _renderModelsByPostKey() => {
        ..._replyRenderModels,
        _openingPostKey(): _openingPostRenderModel,
      };

  /// Marks the content that unlocked [buyPath]'s box on the floor [postKey]
  /// so only it fades in. Every other floor is left alone, and anything that
  /// does not match exactly shows without the fade.
  void _recordPurchaseReveals(
    Map<String, ThreadPostRenderModel> before,
    String? postKey,
    String buyPath,
  ) {
    final old = postKey == null ? null : before[postKey];
    final after = postKey == null ? null : _renderModelsByPostKey()[postKey];
    if (old == null || after == null) return;
    final paths = purchaseRevealPaths(old, after, buyPath: buyPath);
    if (paths.isNotEmpty) _purchaseReveals[postKey!] = paths;
  }

  void _setSaleBoxNotice(String buyPath, ThreadSaleBoxNotice? notice) {
    final next = Map.of(_saleBoxNotices);
    if (notice == null) {
      next.remove(buyPath);
    } else {
      next[buyPath] = notice;
    }
    _saleBoxNotices = Map.unmodifiable(next);
  }

  /// Loads [source]'s page again and installs it. True when the new page was
  /// installed; false when it was superseded (another load, another session,
  /// the page gone), in which case nothing changed.
  Future<bool> _refreshPurchasedPage(
    ThreadDetail source,
    int runId, {
    required int epoch,
    required String? floorId,
    required double? floorY,
    required String? postKey,
    required String buyPath,
  }) async {
    final repository = widget.repository;
    bool current() => mounted && repository.sessionEpoch.value == epoch;
    final page = source.pagination.currentPage;
    final refreshRun = (_purchaseRefreshRuns[page] ?? 0) + 1;
    _purchaseRefreshRuns[page] = refreshRun;
    final updated = await repository.fetchThreadDetail(
      source.thread,
      page: page,
    );
    if (!current() ||
        runId != _loadRunId ||
        _purchaseRefreshRuns[page] != refreshRun) {
      return false;
    }
    if (updated.pagination.currentPage != source.pagination.currentPage) {
      throw StateError('购买后的页面发生跳转，请手动刷新');
    }
    final index = _morePages
        .indexWhere((detail) => detail.pagination.currentPage == page);
    if (_detail?.pagination.currentPage != page && index < 0) return false;
    final before = _renderModelsByPostKey();
    setState(() {
      if (index < 0) {
        _detail = updated;
        _thread = updated.thread;
      } else {
        _morePages[index] = updated;
      }
      _compiledDetail = null;
      _recomputeDetailRenderState();
      _recordPurchaseReveals(before, postKey, buyPath);
    });
    // Lazy row measurement can shift a floor even when scroll pixels stay put.
    await WidgetsBinding.instance.endOfFrame;
    if (!current() ||
        runId != _loadRunId ||
        _purchaseRefreshRuns[page] != refreshRun ||
        floorY == null) {
      return true;
    }
    final post = floorId == null
        ? updated
        : _replyStableIds.entries
            .where((entry) => entry.value == floorId)
            .map((entry) => entry.key)
            .firstOrNull;
    final newY = _postY(post);
    if (newY != null && _scrollController.hasClients) {
      final position = _scrollController.position;
      position.jumpTo(
        (position.pixels + newY - floorY).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    }
    return true;
  }

  /// The loaded page and floor holding the sale box [buyPath], if any.
  ({ThreadDetail source, ThreadReply? reply, String? floorId, String? postKey})?
      _locateSaleBox(String buyPath) {
    final source = [if (_detail != null) _detail!, ..._morePages]
        .where(
          (page) => [
            ...page.bodySaleBoxes,
            for (final reply in page.replies) ...reply.saleBoxes,
          ].any((box) => box.buyPath == buyPath),
        )
        .firstOrNull;
    if (source == null) return null;
    final reply = source.replies
        .where((reply) => reply.saleBoxes.any((box) => box.buyPath == buyPath))
        .firstOrNull;
    final floorId = _replyStableIds[reply];
    return (
      source: source,
      reply: reply,
      floorId: floorId,
      // The floor whose box this is; null when it cannot be named (no reveal).
      postKey: reply == null ? _openingPostKey() : floorId,
    );
  }

  /// Reads the page holding the box again, the only action left on a box that
  /// was paid for or whose purchase is unconfirmed. Never buys.
  Future<void> _refreshSaleBoxPage(String buyPath) async {
    if (_buyingSaleBoxes.contains(buyPath)) return;
    final located = _locateSaleBox(buyPath);
    if (located == null) return;
    final repository = widget.repository;
    final epoch = repository.sessionEpoch.value;
    final runId = _loadRunId;
    setState(() => _buyingSaleBoxes.add(buyPath));
    try {
      final applied = await _refreshPurchasedPage(
        located.source,
        runId,
        epoch: epoch,
        floorId: located.floorId,
        floorY: _postY(located.reply ?? located.source),
        postKey: located.postKey,
        buyPath: buyPath,
      );
      final notice = _saleBoxNotices[buyPath];
      if (applied &&
          notice != null &&
          _locateSaleBox(buyPath) != null &&
          repository.sessionEpoch.value == epoch) {
        // The fresh page still shows the box: say so, never offer a purchase.
        setState(() => _setSaleBoxNotice(
              buyPath,
              ThreadSaleBoxNotice(
                notice.unconfirmed
                    ? '购买结果未确认，页面仍显示未购买。可稍后再刷新，或在网页端核对 SP 币记录'
                    : '已购买，页面仍未更新。可稍后再刷新',
                canRetry: false,
                unconfirmed: notice.unconfirmed,
              ),
            ));
      }
    } catch (error) {
      if (mounted && repository.sessionEpoch.value == epoch) {
        _messenger.showSnackBar(
          SnackBar(content: Text('页面刷新失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _buyingSaleBoxes.remove(buyPath));
    }
  }

  Future<void> _handleBuySaleBox(ThreadSaleBox saleBox) async {
    final buyPath = saleBox.buyPath;
    // One purchase per box: not while one is running, and never again once it
    // went through (or its outcome is unknown) while the box stays locked.
    if (_buyingSaleBoxes.contains(buyPath) ||
        _saleBoxNotices[buyPath]?.canRetry == false) {
      return;
    }
    final located = _locateSaleBox(buyPath);
    final floorY =
        located == null ? null : _postY(located.reply ?? located.source);
    final runId = _loadRunId;
    final repository = widget.repository;
    final epoch = repository.sessionEpoch.value;
    bool sameSession() => mounted && repository.sessionEpoch.value == epoch;
    setState(() {
      _buyingSaleBoxes.add(buyPath);
      _setSaleBoxNotice(buyPath, null);
    });

    try {
      final result = await repository.buySaleBox(saleBox);
      if (!sameSession()) return;
      _messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.success ? '${result.message}，已刷新当前页' : result.message,
          ),
        ),
      );
      if (!result.success) {
        setState(() => _setSaleBoxNotice(
              buyPath,
              ThreadSaleBoxNotice(result.message, canRetry: true),
            ));
        return;
      }
      // Paid: recorded before anything else can supersede or fail, so the
      // box can never offer the purchase again.
      setState(() => _setSaleBoxNotice(
            buyPath,
            const ThreadSaleBoxNotice(
              '已购买，页面尚未更新，请刷新页面',
              canRetry: false,
            ),
          ));
      if (located == null || runId != _loadRunId) return;
      try {
        await _refreshPurchasedPage(
          located.source,
          runId,
          epoch: epoch,
          floorId: located.floorId,
          floorY: floorY,
          postKey: located.postKey,
          buyPath: buyPath,
        );
      } catch (error) {
        if (!sameSession()) return;
        _messenger.showSnackBar(
          SnackBar(content: Text('购买成功，页面刷新失败：$error')),
        );
      }
    } catch (error) {
      if (!sameSession()) return;
      // The request may have gone through: the box stays locked to buying.
      setState(() => _setSaleBoxNotice(
            buyPath,
            ThreadSaleBoxNotice(
              '购买结果未确认：$error，请刷新页面核对',
              canRetry: false,
              unconfirmed: true,
            ),
          ));
      _messenger.showSnackBar(
        SnackBar(content: Text('购买失败：$error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _buyingSaleBoxes.remove(buyPath);
        });
      }
    }
  }

  ThreadFavorite _effectiveFavorite(ThreadFavorite favorite) {
    return favorite.copyWith(
      state: _favoriteOverrides[favorite.tid] ?? favorite.state,
    );
  }

  Future<void> _handleFavorite(ThreadFavorite favorite) async {
    if (_favoriteBusy) return;
    final effective = _effectiveFavorite(favorite);
    final repository = widget.repository;
    final flow = _favoriteFlow.value;
    final epoch = repository.sessionEpoch.value;
    // Still the same screen state, session and thread as when it started.
    bool current() =>
        mounted &&
        flow == _favoriteFlow.value &&
        epoch == repository.sessionEpoch.value;
    setState(() {
      _favoriteBusy = true;
    });

    try {
      final FavoriteResult result;
      if (effective.canRemove) {
        result = await repository.removeFavorite(effective);
      } else {
        // Cancelling sends nothing and leaves the favorite as it was.
        final added = await _addToCollection(effective, flow, current);
        if (added == null) return;
        result = added;
      }
      if (!current()) return;
      _messenger.showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      if (result.success) {
        setState(() {
          _favoriteOverrides[effective.tid] = result.state;
        });
      }
    } catch (error) {
      if (!current()) return;
      _messenger.showSnackBar(
        SnackBar(content: Text('收藏操作失败：$error')),
      );
    } finally {
      // An obsolete call never clears the busy flag of a newer one.
      if (current()) {
        setState(() {
          _favoriteBusy = false;
        });
      }
    }
  }

  /// Reads the categories without writing, lets the user pick one (or add
  /// one first), then favorites into it with one request. Null when cancelled
  /// or when the screen moved on meanwhile.
  Future<FavoriteResult?> _addToCollection(
    ThreadFavorite favorite,
    int flow,
    bool Function() current,
  ) async {
    final repository = widget.repository;
    var snapshot = await repository.fetchFavoriteCollections();
    FavoriteCategory? category;
    // The forum's list always holds the default category; none means the
    // page was not read properly, so nothing is written.
    if (snapshot.categories.isEmpty) {
      if (current()) {
        _messenger.showSnackBar(
          const SnackBar(content: Text('没有读到收藏分类，请稍后重试')),
        );
      }
      return null;
    }
    while (category == null) {
      if (!current()) return null;
      final choice = await _chooseFavoriteCategory(snapshot, flow);
      if (!current() || choice == null) return null;
      if (choice is FavoriteCategory) {
        category = choice;
        break;
      }
      // 新建分类 only adds the category; the thread is not favorited by it.
      final name = await showNewCategoryDialog(
        context,
        session: repository.sessionEpoch,
        maxLength: snapshot.nameMaxLength,
      );
      if (!current()) return null;
      if (name == null || name.trim().isEmpty) continue;
      final made =
          await repository.createFavoriteCategory(snapshot, name.trim());
      if (!current()) return null;
      _messenger.showSnackBar(SnackBar(
        content: Text(made.status == FavoriteMutationStatus.confirmed
            ? '已新建分类「${name.trim()}」，请选择分类'
            : made.message.isEmpty
                ? '新建分类的结果未确认'
                : made.message),
      ));
      snapshot =
          made.collections ?? await repository.fetchFavoriteCollections();
    }
    if (!current()) return null;
    final mutation = await repository.addFavoriteToCollection(
        snapshot, favorite, category.id);
    final ok = mutation.status == FavoriteMutationStatus.confirmed;
    return FavoriteResult(
      success: ok,
      message: ok
          ? (mutation.message.isEmpty
              ? '已收藏到「${category.label}」'
              : mutation.message)
          : mutation.status == FavoriteMutationStatus.unknown
              ? '收藏的结果未确认，请刷新核对'
              : mutation.message,
      state: ok ? ThreadFavoriteState.favorite : favorite.state,
    );
  }

  /// A [FavoriteCategory], or [_NewCategory] when the user wants to add one.
  Future<Object?> _chooseFavoriteCategory(
          FavoriteCollections snapshot, int flow) =>
      showModalBottomSheet<Object>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _FavoriteCategorySheet(
          categories: snapshot.categories,
          canCreate: snapshot.canCreate,
          invalidated: _favoriteFlow,
          generation: flow,
        ),
      );

  void _openThreadLink(ThreadActionLink link) {
    final current = _detail?.thread ?? _thread;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThreadDetailScreen(
          thread: ForumThread(
            title: link.label,
            url: link.url,
            replies: 0,
            section: current.section,
          ),
          repository: widget.repository,
        ),
      ),
    );
  }

  Future<void> _openContentLink(String url, String label) async {
    if (!widget.repository.isAttachmentUrl(url)) {
      await openForumLink(context, widget.repository, url, label: label);
      return;
    }
    if (_savingAttachment) return;
    _savingAttachment = true;
    final messenger = _messenger;
    messenger.clearSnackBars();
    messenger.removeCurrentSnackBar();
    final progress = messenger.showSnackBar(const SnackBar(
      content: Text('正在下载附件…'),
      duration: Duration(days: 1),
    ));
    var progressClosed = false;
    progress.closed.then((_) => progressClosed = true);
    try {
      final saved = await AttachmentSaver.save(
        widget.repository,
        url,
        suggestedName: label,
      );
      if (!mounted) return;
      if (saved) {
        messenger.showSnackBar(const SnackBar(content: Text('附件已保存')));
      }
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('附件下载失败：$error')));
    } finally {
      if (messenger.mounted && !progressClosed) progress.close();
      _savingAttachment = false;
    }
  }

  Future<void> _openExternalLink(ThreadActionLink link) async {
    try {
      await ExternalLinkLauncher.open(link.url);
    } catch (error) {
      if (!mounted) return;
      _messenger.showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  /// The page of the post at the top of the screen, once scrolling has
  /// shown one; the loaded page before that.
  int get _shownPage => _visiblePage ?? _page;

  Future<void> _openJumpSheet() async {
    final last = _lastLoaded;
    if (last == null) return;
    final page = await showForumPagePicker(
      context,
      current: _shownPage,
      total: last.pagination.totalPages,
      shortcuts: [
        ('首楼', Icons.first_page, _jumpToFirst),
        ('回到顶部', Icons.vertical_align_top, () => _scrollToEdge(top: true)),
        ('到底部', Icons.vertical_align_bottom, () => _scrollToEdge(top: false)),
        ('最新回复', Icons.last_page, _jumpToLatest),
      ],
    );
    if (page != null && mounted) await _goToPage(page);
  }

  Future<void> _share() async {
    final thread = _detail?.thread;
    final url =
        thread == null ? null : widget.repository.threadShareUrl(thread);
    if (thread == null || url == null) return;
    try {
      final opened =
          await ThreadShareService.share(title: thread.title, url: url);
      if (!opened && mounted) {
        _messenger.showSnackBar(const SnackBar(content: Text('已复制链接')));
      }
    } catch (_) {
      if (!mounted) return;
      _messenger.showSnackBar(const SnackBar(content: Text('分享失败')));
    }
  }

  Widget _threadList(ThreadDetail detail) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Listener(
        onPointerSignal: _onPointerSignal,
        child: _ThreadDetailContent(
          detail: detail,
          onPostMounted: _postMounted,
          onRetryLoadMore: _retryLoadMore,
          rules: widget.repository.blocking.notifier.value,
          revealedPosts: _revealedPosts,
          onReveal: (post) => setState(() => _revealedPosts.add(post)),
          entries: _detailEntries,
          loading: _loading,
          onlyOriginalPosterActive: _onlyOriginalPosterActive,
          authorFilterName:
              _authorFilterActive ? _authorFilterName ?? '该作者' : null,
          visibleFloorCount: _visibleFloorCount,
          favorite: detail.favorite == null
              ? null
              : _effectiveFavorite(detail.favorite!),
          favoriteBusy: _favoriteBusy,
          buyingSaleBoxes: _buyingSaleBoxes,
          saleBoxNotices: _saleBoxNotices,
          purchaseReveals: _purchaseReveals,
          revealPlayed: _revealPlayed,
          noteFor: _notes.noteFor,
          loadingQuoteDrafts: _loadingQuoteDrafts,
          scrollController: _scrollController,
          onRefresh: _refresh,
          onAuthorTap: _openUserProfile,
          onFavorite: _handleFavorite,
          onShowOriginalPosterPosts: _showOriginalPosterPosts,
          onFloorMore: _showFloorActions,
          onClearAuthorFilter: _clearAuthorFilter,
          onQuoteReply: _quoteReply,
          onBuySaleBox: _handleBuySaleBox,
          onRefreshSaleBox: _refreshSaleBoxPage,
          onReplyToFloor: _replyToFloor,
          onPageSelected: _goToPage,
          autoLoadNextPage: _autoLoadNextPage,
          onThreadLink: _openThreadLink,
          onOpenLink: _openContentLink,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    PerfTrace.markScreen('ThreadDetailScreen');
    final detail = _detail;
    return PerfTrace.span(
      'ThreadDetailScreen.build',
      () {
        return ScaffoldMessenger(
          key: _messengerKey,
          child: Scaffold(
            appBar: AppBar(
              title: _BoardTitle(
                name: detail?.board?.name ??
                    detail?.thread.section ??
                    widget.thread.section,
                onTap: detail?.board == null
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => BoardThreadListScreen(
                              category: detail!.board!,
                              repository: widget.repository,
                            ),
                          ),
                        ),
              ),
              actions: [
                IconButton(
                  tooltip: '分享',
                  onPressed: detail == null ? null : _share,
                  icon: const Icon(Icons.share_outlined),
                ),
                _ThreadMoreMenu(
                  // Loaded title only; the pre-load title can be a placeholder.
                  onSearchTitle:
                      detail == null || detail.thread.title.trim().isEmpty
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => SearchScreen(
                                    repository: widget.repository,
                                    initialKeyword: detail.thread.title.trim(),
                                  ),
                                ),
                              ),
                  onRss: detail?.rssFeed == null
                      ? null
                      : () => _openExternalLink(detail!.rssFeed!),
                ),
              ],
            ),
            floatingActionButton: _composerOpen || detail == null
                ? null
                : FloatingActionButton.small(
                    tooltip: '写回复',
                    onPressed: _openComposer,
                    child: const Icon(Icons.edit_outlined),
                  ),
            // Floor navigation in its own strip, so it never covers a post;
            // the open composer takes its place.
            bottomNavigationBar: detail == null || _composerOpen
                ? null
                : _ThreadPageBar(
                    current: _shownPage,
                    total: _lastLoaded!.pagination.totalPages,
                    onSelected: _loading ? null : _goToPage,
                    onJump: _openJumpSheet,
                  ),
            body: detail == null
                ? _InitialThreadState(
                    error: _loadError,
                    onRetry: _refresh,
                  )
                : PopScope(
                    // Back folds an open composer before leaving the thread.
                    canPop: !_composerOpen,
                    onPopInvokedWithResult: (didPop, _) {
                      if (!didPop) _closeComposer();
                    },
                    // Sized from the body actually left, after the app bar,
                    // keyboard and any short landscape window.
                    child: LayoutBuilder(
                      builder: (context, constraints) => Column(
                        children: [
                          Expanded(child: _threadList(detail)),
                          _ComposerDock(
                            open: _composerOpen,
                            // A cramped body (landscape + keyboard) goes
                            // to the composer whole.
                            maxHeight: constraints.maxHeight < 240
                                ? constraints.maxHeight
                                : constraints.maxHeight * 0.6,
                            child: ReplyComposer(
                              key: _replyKey,
                              thread: detail.thread,
                              repository: widget.repository,
                              onSubmitted: _handleReplySubmitted,
                              onCollapse: _closeComposer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        );
      },
      arguments: {
        'loading': _loading,
        'hasDetail': detail != null,
        'page': _page,
      },
    );
  }
}

/// The reply box docked under the list; it stays mounted while folded so
/// the draft survives.
class _ComposerDock extends StatelessWidget {
  const _ComposerDock({
    required this.open,
    required this.maxHeight,
    required this.child,
  });

  final bool open;
  final double maxHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: Offstage(
        offstage: !open,
        // The dock shares the posts' reading width.
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: maxHeight,
              maxWidth: AppWidths.reading,
            ),
            // Raised (DESIGN §5 level 1); in dark a border, not a shadow,
            // lifts it, and its fields keep the surfaceTint contrast.
            child: Material(
              color: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              elevation: dark ? 0 : 3,
              shape: RoundedRectangleBorder(
                side: dark
                    ? BorderSide(color: AppColors.border)
                    : BorderSide.none,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.xl),
                ),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InitialThreadState extends StatelessWidget {
  const _InitialThreadState({
    required this.error,
    required this.onRetry,
  });

  final Object? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return AsyncErrorView(
        title: '帖子加载失败',
        message: '$error',
        onRetry: onRetry,
      );
    }
    return const ThreadDetailSkeleton();
  }
}

class _ThreadDetailContent extends StatelessWidget {
  const _ThreadDetailContent({
    required this.detail,
    required this.onPostMounted,
    required this.onRetryLoadMore,
    required this.rules,
    required this.revealedPosts,
    required this.onReveal,
    required this.entries,
    required this.loading,
    required this.onlyOriginalPosterActive,
    required this.authorFilterName,
    required this.visibleFloorCount,
    required this.favorite,
    required this.favoriteBusy,
    required this.buyingSaleBoxes,
    required this.saleBoxNotices,
    required this.purchaseReveals,
    required this.revealPlayed,
    required this.noteFor,
    required this.loadingQuoteDrafts,
    required this.scrollController,
    required this.onRefresh,
    required this.onAuthorTap,
    required this.onFavorite,
    required this.onShowOriginalPosterPosts,
    required this.onClearAuthorFilter,
    required this.onQuoteReply,
    required this.onBuySaleBox,
    required this.onRefreshSaleBox,
    required this.onReplyToFloor,
    required this.onFloorMore,
    required this.onPageSelected,
    required this.autoLoadNextPage,
    required this.onThreadLink,
    required this.onOpenLink,
  });

  final ThreadDetail detail;

  /// Reports each post's mount and unmount, for read positions.
  final void Function(Object post, BuildContext context, bool mounted)
      onPostMounted;
  final VoidCallback onRetryLoadMore;
  final BlockingRules rules;
  final Set<Object> revealedPosts;
  final ValueChanged<Object> onReveal;
  final List<ThreadDetailListEntry> entries;
  final bool loading;
  final bool onlyOriginalPosterActive;
  final String? authorFilterName;
  final int visibleFloorCount;
  final ThreadFavorite? favorite;
  final bool favoriteBusy;
  final Set<String> buyingSaleBoxes;
  final Map<String, ThreadSaleBoxNotice> saleBoxNotices;
  final Map<String, Set<String>> purchaseReveals;
  final Set<String> revealPlayed;
  final String? Function(String? uid) noteFor;
  final Set<String> loadingQuoteDrafts;
  final ScrollController scrollController;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onAuthorTap;
  final ValueChanged<ThreadFavorite> onFavorite;
  final ValueChanged<ForumThread> onShowOriginalPosterPosts;
  final VoidCallback onClearAuthorFilter;
  final Future<void> Function(ThreadReply) onQuoteReply;
  final ValueChanged<ThreadSaleBox> onBuySaleBox;
  final Future<void> Function(String buyPath) onRefreshSaleBox;
  final ValueChanged<String> onReplyToFloor;
  final void Function(ThreadReply post, bool openingPost) onFloorMore;
  final ValueChanged<int> onPageSelected;
  final bool autoLoadNextPage;
  final ValueChanged<ThreadActionLink> onThreadLink;
  final Future<void> Function(String url, String label) onOpenLink;

  @override
  Widget build(BuildContext context) {
    return PerfTrace.span(
      'ThreadDetailContent.build',
      () {
        final originalAuthor = detail.thread.author;
        final width = MediaQuery.sizeOf(context).width;
        // Page gutter, widening to centre a 760 reading column.
        final side = appGutter(width, AppWidths.reading);
        bool isReply(int i) =>
            i >= 0 &&
            i < entries.length &&
            entries[i].type == ThreadDetailListEntryType.reply;
        return Stack(
          children: [
            RefreshIndicator(
              color: AppColors.brand,
              onRefresh: onRefresh,
              child: ListView.builder(
                controller: scrollController,
                // Room below the end for the floating reply button.
                // and a comfortable reading width on wide windows.
                padding: EdgeInsets.fromLTRB(side, 0, side, 88),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final child = _buildEntry(
                    context,
                    entries[index],
                    originalAuthor: originalAuthor,
                  );
                  if (!isReply(index)) return child;
                  // Consecutive floors share one surface, split by hairlines.
                  return _ReplyGroupSlot(
                    first: !isReply(index - 1),
                    last: !isReply(index + 1),
                    child: child,
                  );
                },
              ),
            ),
            if (loading)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        );
      },
      arguments: {
        'page': detail.pagination.currentPage,
        'entries': entries.length,
        'loading': loading,
      },
    );
  }

  Widget _purchaseScope(String postKey, Widget child) => ThreadPurchaseScope(
        postKey: postKey,
        revealPaths: purchaseReveals[postKey] ?? const <String>{},
        played: revealPlayed,
        notices: saleBoxNotices,
        onRefreshBox: onRefreshSaleBox,
        child: child,
      );

  Widget _buildEntry(
    BuildContext context,
    ThreadDetailListEntry entry, {
    required String? originalAuthor,
  }) {
    switch (entry.type) {
      case ThreadDetailListEntryType.topSpacing:
        return _entryWithKey(
          key: entry.key,
          child:
              SizedBox(height: (entry as ThreadDetailTopSpacingEntry).height),
        );
      case ThreadDetailListEntryType.pagination:
        // Only explicit paging ends a page with a card; the page bar under
        // the list is the page control in both modes.
        if (autoLoadNextPage) return const SizedBox.shrink();
        return _entryWithKey(
          key: entry.key,
          child: ThreadPageEndCard(
            pagination: (entry as ThreadDetailPaginationEntry).pagination ??
                detail.pagination,
            onPageSelected: loading ? null : onPageSelected,
            onRefresh: loading ? null : onRefresh,
          ),
        );
      case ThreadDetailListEntryType.openingPost:
        final openingEntry = entry as ThreadDetailOpeningPostEntry;
        final actions = _ThreadHeaderActions(
          favorite: favorite,
          favoriteBusy: favoriteBusy,
          onFavorite: favorite == null ? null : () => onFavorite(favorite!),
          onlyOriginalPoster: onlyOriginalPosterActive,
          originalAuthor: originalAuthor,
          onOnlyOriginalPosterChanged: originalAuthor == null
              ? null
              : (selected) => selected
                  ? onShowOriginalPosterPosts(detail.thread)
                  : onClearAuthorFilter(),
          previousThread: detail.previousThread,
          nextThread: detail.nextThread,
          onThreadLink: onThreadLink,
        );
        if (!openingEntry.hasBody) {
          return _entryWithKey(
            key: entry.key,
            child: _ThreadHeaderCard(
              title: detail.thread.title,
              author: detail.thread.author,
              avatarUrl: rules.isAvatarBlocked(detail.thread.authorUid)
                  ? null
                  : detail.thread.authorAvatarUrl,
              onAuthorTap: detail.thread.authorUrl == null
                  ? null
                  : () => onAuthorTap(detail.thread.authorUrl!),
              actions: actions,
            ),
          );
        }
        final openingPost = _openingPostAsReply();
        final opHidden = !revealedPosts.contains(detail) &&
            rules.floorBlock(
                  uid: detail.thread.authorUid,
                  contentKey: null,
                  isOpeningPost: true,
                ) !=
                FloorBlock.none;
        if (opHidden) {
          // The title and thread actions stay; only the post body hides.
          return _entryWithKey(
            key: entry.key,
            post: detail,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ThreadHeaderCard(
                  title: detail.thread.title,
                  actions: actions,
                ),
                const SizedBox(height: 12),
                ThreadBlockedFloor(
                  label: _hiddenLabel('楼主', FloorBlock.user),
                  onReveal: () => onReveal(detail),
                ),
              ],
            ),
          );
        }
        return _entryWithKey(
          key: entry.key,
          post: detail,
          child: _FloorCard(
            title: detail.thread.title,
            author: detail.thread.author ?? '楼主',
            avatarUrl: rules.isAvatarBlocked(detail.thread.authorUid)
                ? null
                : detail.thread.authorAvatarUrl,
            onAuthorTap: detail.thread.authorUrl == null
                ? null
                : () => onAuthorTap(detail.thread.authorUrl!),
            // Never the list's last-reply time: empty beats a wrong time.
            postedAt: detail.bodyPostedAt,
            personalSignature: detail.personalSignature,
            note: noteFor(detail.thread.authorUid),
            floor: '楼主',
            onReply: () => onReplyToFloor(
              detail.bodyReplyTitle ?? 'Re:${detail.thread.title}',
            ),
            quoteLoading: detail.bodyQuoteUrl != null &&
                loadingQuoteDrafts.contains(detail.bodyQuoteUrl),
            onQuote: () => onQuoteReply(openingPost),
            onMore: () => onFloorMore(openingPost, true),
            threadActions: actions,
            child: _purchaseScope(
                'opening:${detail.pagination.currentPage}',
                ThreadPostBody(
                  content: detail.body,
                  segments: detail.bodySegments,
                  renderModel: openingEntry.renderModel,
                  quote: null,
                  images: detail.bodyImages,
                  links: detail.bodyLinks,
                  saleBoxes: detail.bodySaleBoxes,
                  saleBoxesFirst: detail.bodySaleBoxesFirst,
                  buyingSaleBoxes: buyingSaleBoxes,
                  onBuySaleBox: onBuySaleBox,
                  onOpenLink: onOpenLink,
                )),
          ),
        );
      case ThreadDetailListEntryType.authorFilterChip:
        final chipEntry = entry as ThreadDetailAuthorFilterChipEntry;
        return _entryWithKey(
          key: entry.key,
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _ActiveAuthorFilterChip(
              author: authorFilterName!,
              loading: loading,
              pagination: detail.pagination,
              visibleFloorCount: chipEntry.visibleFloorCount,
              onClear: onClearAuthorFilter,
            ),
          ),
        );
      case ThreadDetailListEntryType.emptyState:
        final emptyEntry = entry as ThreadDetailEmptyStateEntry;
        return _entryWithKey(
          key: entry.key,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: EmptyStateView(
              title: emptyEntry.title,
              message: emptyEntry.message,
            ),
          ),
        );
      case ThreadDetailListEntryType.reply:
        final replyEntry = entry as ThreadDetailReplyEntry;
        final reply = replyEntry.reply;
        final hidden = revealedPosts.contains(reply)
            ? FloorBlock.none
            : rules.floorBlock(
                uid: reply.authorUid,
                contentKey: reply.blockContentKey,
              );
        if (hidden != FloorBlock.none) {
          return _entryWithKey(
            key: entry.key,
            post: reply,
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: ThreadBlockedFloor(
                label: _hiddenLabel(reply.floor, hidden),
                onReveal: () => onReveal(reply),
              ),
            ),
          );
        }
        return _entryWithKey(
          key: entry.key,
          post: reply,
          child: _FloorCard(
            grouped: true,
            author: reply.author,
            avatarUrl: rules.isAvatarBlocked(reply.authorUid)
                ? null
                : reply.authorAvatarUrl,
            onAuthorTap: reply.authorUrl == null
                ? null
                : () => onAuthorTap(reply.authorUrl!),
            postedAt: reply.postedAt,
            personalSignature: reply.personalSignature,
            note: noteFor(reply.authorUid),
            floor: reply.floor,
            onReply: () => onReplyToFloor(
              reply.replyTitle ?? 'Re:${detail.thread.title}',
            ),
            onMore: () => onFloorMore(reply, false),
            // By account, never by display name; no uid, no tag.
            byOriginalPoster: detail.thread.authorUid != null &&
                reply.authorUid == detail.thread.authorUid,
            quoteLoading: reply.quoteUrl != null &&
                loadingQuoteDrafts.contains(reply.quoteUrl),
            onQuote: () => onQuoteReply(reply),
            child: _purchaseScope(
                replyEntry.stableId,
                ThreadPostBody(
                  content: reply.content,
                  segments: reply.segments,
                  renderModel: replyEntry.renderModel,
                  quote: reply.quote,
                  images: reply.images,
                  links: reply.links,
                  saleBoxes: reply.saleBoxes,
                  saleBoxesFirst: reply.saleBoxesFirst,
                  buyingSaleBoxes: buyingSaleBoxes,
                  onBuySaleBox: onBuySaleBox,
                  onOpenLink: onOpenLink,
                )),
          ),
        );
      case ThreadDetailListEntryType.pageDivider:
        final page = (entry as ThreadDetailPageDividerEntry).page;
        return _entryWithKey(
          key: entry.key,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '第 $page 页',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
          ),
        );
      case ThreadDetailListEntryType.loadMore:
        final state = entry as ThreadDetailLoadMoreEntry;
        return _entryWithKey(
          key: entry.key,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Center(
              child: state.failed
                  ? TextButton.icon(
                      onPressed: onRetryLoadMore,
                      icon: const Icon(Icons.refresh),
                      label: const Text('下一页加载失败，点按重试'),
                    )
                  : state.loading
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : state.hasMore
                          ? TextButton(
                              onPressed: onRetryLoadMore,
                              child: const Text('加载下一页'),
                            )
                          : Text(
                              '已到最后一页',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
            ),
          ),
        );
    }
  }

  static String _hiddenLabel(String? floor, FloorBlock reason) {
    final what = reason == FloorBlock.user ? '已屏蔽此人的发言' : '已屏蔽相同内容';
    return floor == null || floor.isEmpty ? what : '$floor · $what';
  }

  /// The opening post in the shape the floor actions take.
  ThreadReply _openingPostAsReply() => ThreadReply(
        author: detail.thread.author ?? '楼主',
        content: detail.body,
        authorUrl: detail.thread.authorUrl,
        authorAvatarUrl: detail.thread.authorAvatarUrl,
        authorPostsUrl: detail.thread.authorPostsUrl,
        floor: '楼主',
        quoteUrl: detail.bodyQuoteUrl,
        replyTitle: detail.bodyReplyTitle,
      );

  Widget _entryWithKey({
    required Widget child,
    Key? key,
    Object? post,
  }) {
    if (post != null) {
      child = _PostMountReporter(
        post: post,
        onMounted: onPostMounted,
        child: child,
      );
    }
    if (key == null) return child;
    return KeyedSubtree(key: key, child: child);
  }
}

class _PostMountReporter extends StatefulWidget {
  const _PostMountReporter({
    required this.post,
    required this.onMounted,
    required this.child,
  });

  final Object post;
  final void Function(Object post, BuildContext context, bool mounted)
      onMounted;
  final Widget child;

  @override
  State<_PostMountReporter> createState() => _PostMountReporterState();
}

class _PostMountReporterState extends State<_PostMountReporter> {
  @override
  void initState() {
    super.initState();
    widget.onMounted(widget.post, context, true);
  }

  @override
  void didUpdateWidget(covariant _PostMountReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.post, widget.post)) return;
    widget.onMounted(oldWidget.post, context, false);
    widget.onMounted(widget.post, context, true);
  }

  @override
  void dispose() {
    widget.onMounted(widget.post, context, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ThreadHeaderCard extends StatelessWidget {
  const _ThreadHeaderCard({
    required this.title,
    required this.actions,
    this.author,
    this.avatarUrl,
    this.onAuthorTap,
  });

  final String title;
  final String? author;
  final String? avatarUrl;
  final VoidCallback? onAuthorTap;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final authorName = author;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ThreadTitle(title),
            const SizedBox(height: AppSpace.lg),
            if (authorName != null && authorName.isNotEmpty) ...[
              _AuthorTapArea(
                onTap: onAuthorTap,
                child: Row(
                  children: [
                    _AuthorAvatar(
                      author: authorName,
                      avatarUrl: avatarUrl,
                    ),
                    const SizedBox(width: AppSpace.md),
                    Flexible(child: _FloorAuthorName(author: authorName)),
                    const SizedBox(width: AppSpace.sm),
                    const AppTag('楼主', accent: true),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.lg),
            ],
            actions,
          ],
        ),
      ),
    );
  }
}

class _ActiveAuthorFilterChip extends StatelessWidget {
  const _ActiveAuthorFilterChip({
    required this.author,
    required this.loading,
    required this.pagination,
    required this.visibleFloorCount,
    required this.onClear,
  });

  final String author;
  final bool loading;
  final ThreadPagination pagination;
  final int visibleFloorCount;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.xs,
        AppSpace.xs,
        AppSpace.xs,
      ),
      decoration: appSurface(context),
      child: Row(
        children: [
          Icon(
            Icons.person_search_outlined,
            size: 20,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '只看 $author',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  '第 ${pagination.currentPage} / ${pagination.totalPages} 页 · 本页 $visibleFloorCount 楼',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '取消只看该作者',
            onPressed: loading ? null : onClear,
            icon: Icon(Icons.close, size: 18),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
        ],
      ),
    );
  }
}

class _FloorCard extends StatelessWidget {
  const _FloorCard({
    required this.author,
    required this.child,
    this.title,
    this.avatarUrl,
    this.onAuthorTap,
    this.postedAt,
    this.personalSignature,
    this.note,
    this.floor,
    this.onReply,
    this.quoteLoading = false,
    this.onQuote,
    this.onMore,
    this.threadActions,
    this.byOriginalPoster = false,
    this.grouped = false,
  });

  final String author;
  final bool byOriginalPoster;

  /// A row inside the shared replies surface instead of its own card.
  final bool grouped;
  final String? title;
  final String? avatarUrl;
  final VoidCallback? onAuthorTap;
  final String? postedAt;

  /// The author's short signature from the post header (never a footer).
  final String? personalSignature;

  /// The reader's local note on the author.
  final String? note;
  final String? floor;
  final VoidCallback? onReply;
  final bool quoteLoading;
  final VoidCallback? onQuote;
  final VoidCallback? onMore;

  /// The opening post's thread controls, sharing the footer's row.
  final _ThreadHeaderActions? threadActions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The opening post's "floor" is its author: a badge, not a number.
    final isOpeningPost = floor == '楼主';
    final footer = ThreadFloorFooter(
      moreKey: ValueKey('floor-actions-$author-$floor'),
      onReply: onReply,
      onQuote: onQuote,
      onMore: onMore,
      quoteLoading: quoteLoading,
    );
    final trimmedSignature = personalSignature?.trim();
    final signature = trimmedSignature == null || trimmedSignature.isEmpty
        ? null
        : trimmedSignature;
    final meta = [
      if (postedAt != null && postedAt!.isNotEmpty) postedAt!,
      if (floor != null && floor!.isNotEmpty && !isOpeningPost) floor!,
    ].join(' · ');
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.only(right: AppSpace.sm),
              child: _ThreadTitle(title!),
            ),
            const SizedBox(height: AppSpace.lg),
          ],
          _AuthorTapArea(
            onTap: onAuthorTap,
            child: Row(
              children: [
                _AuthorAvatar(
                  author: author,
                  avatarUrl: avatarUrl,
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: _FloorAuthorName(author: author, note: note),
                          ),
                          if (isOpeningPost || byOriginalPoster) ...[
                            const SizedBox(width: AppSpace.sm),
                            const AppTag('楼主', accent: true),
                          ],
                        ],
                      ),
                      if (meta.isNotEmpty || signature != null) ...[
                        const SizedBox(height: AppSpace.xs),
                        _FloorMeta(meta: meta, signature: signature),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.sm),
            child: RepaintBoundary(child: child),
          ),
          if (threadActions case final actions?) ...[
            const SizedBox(height: AppSpace.sm),
            actions.withFooter(footer),
          ] else if (onReply != null || onQuote != null || onMore != null)
            footer,
        ],
      ),
    );
    return grouped ? content : Card(child: content);
  }
}

/// One floor's slot in the replies surface: rounded at the run's ends,
/// a hairline above every floor but the first.
class _ReplyGroupSlot extends StatelessWidget {
  const _ReplyGroupSlot({
    required this.first,
    required this.last,
    required this.child,
  });

  final bool first;
  final bool last;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const radius = Radius.circular(AppRadius.lg);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? AppSpace.md : 0),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
          top: first ? radius : Radius.zero,
          bottom: last ? radius : Radius.zero,
        ),
        clipBehavior: first || last ? Clip.antiAlias : Clip.none,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!first)
              Divider(
                height: 1,
                thickness: 1,
                indent: 16,
                endIndent: 16,
                color: AppColors.border,
              ),
            child,
          ],
        ),
      ),
    );
  }
}

/// The author row as one tap target (avatar, name and meta), at least
/// 48 px high, opening the author's profile.
class _AuthorTapArea extends StatelessWidget {
  const _AuthorTapArea({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final target = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: child,
    );
    if (onTap == null) return target;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: target,
    );
  }
}

class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({
    required this.author,
    required this.avatarUrl,
  });

  final String author;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final imageUrl = avatarUrl;
    return Semantics(
      label: '$author 的头像',
      image: true,
      child: SizedBox.square(
        dimension: 40,
        child: ClipOval(
          child: imageUrl == null || imageUrl.isEmpty
              ? _AvatarFallback(author: author)
              : CachedForumImage(
                  url: imageUrl,
                  bypassLoadPolicy: true,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorWidget: (context) => _AvatarFallback(author: author),
                ),
        ),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.author});

  final String author;

  @override
  Widget build(BuildContext context) {
    final trimmed = author.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.substring(0, 1);
    return DecoratedBox(
      key: const ValueKey('thread-author-avatar-fallback'),
      decoration: BoxDecoration(
        color: AppColors.inkSoft,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initial,
          // The circle is a fixed 40 px; its letter must fit it at any scale.
          textScaler: TextScaler.noScaling,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: AppColors.textMuted),
        ),
      ),
    );
  }
}

class _FloorAuthorName extends StatelessWidget {
  const _FloorAuthorName({required this.author, this.note});

  final String author;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return UserNoteLabel(
      name: author,
      note: note,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

/// Time and floor, whole at any text scale, then the signature: on the same
/// line when it fits, else on its own line, ellipsized there. The signature
/// never truncates or pushes the time.
class _FloorMeta extends StatelessWidget {
  const _FloorMeta({required this.meta, required this.signature});

  final String meta;
  final String? signature;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final signature = this.signature;
    return LayoutBuilder(
      builder: (context, box) => Wrap(
        spacing: AppSpace.sm,
        runSpacing: 2,
        children: [
          if (meta.isNotEmpty) Text(meta, style: style),
          if (signature != null && signature.isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth),
              child: Semantics(
                label: '签名 $signature',
                excludeSemantics: true,
                child: Text(
                  signature,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ThreadTitle extends StatelessWidget {
  const _ThreadTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge,
    );
  }
}

/// The opening post's thread controls: the 收藏 and 只看楼主 toggles, and
/// the row to the neighbouring threads. A control the thread lacks is left
/// out.
class _ThreadHeaderActions extends StatelessWidget {
  const _ThreadHeaderActions({
    required this.favorite,
    required this.favoriteBusy,
    required this.onFavorite,
    required this.onlyOriginalPoster,
    required this.originalAuthor,
    required this.onOnlyOriginalPosterChanged,
    required this.previousThread,
    required this.nextThread,
    required this.onThreadLink,
  });

  final ThreadFavorite? favorite;
  final bool favoriteBusy;
  final VoidCallback? onFavorite;
  final bool onlyOriginalPoster;
  final String? originalAuthor;
  final ValueChanged<bool>? onOnlyOriginalPosterChanged;
  final ThreadActionLink? previousThread;
  final ThreadActionLink? nextThread;
  final ValueChanged<ThreadActionLink> onThreadLink;

  /// The toggles, or null when the thread offers neither.
  Widget? toggles() {
    final fav = favorite;
    final onlyOp = onOnlyOriginalPosterChanged;
    final items = [
      if (fav != null)
        _ThreadToggle(
          icon: Icons.star_outline,
          selectedIcon: Icons.star,
          label: fav.canRemove ? '已收藏' : '收藏',
          selected: fav.canRemove,
          busy: favoriteBusy,
          onPressed: onFavorite,
        ),
      if (originalAuthor != null && onlyOp != null)
        _ThreadToggle(
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
          label: '只看楼主',
          selected: onlyOriginalPoster,
          onPressed: () => onlyOp(!onlyOriginalPoster),
        ),
    ];
    if (items.isEmpty) return null;
    return Wrap(spacing: AppSpace.sm, children: items);
  }

  /// ‹ 上一主题 at the start and 下一主题 › at the end; a missing neighbour
  /// leaves its side empty. Null when there is neither.
  Widget? neighbours() {
    final previous = previousThread;
    final next = nextThread;
    final style = TextButton.styleFrom(
      foregroundColor: AppColors.textMuted,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
    );
    final back = previous == null
        ? null
        : TextButton.icon(
            style: style,
            onPressed: () => onThreadLink(previous),
            icon: const Icon(Icons.chevron_left),
            label: const Text('上一主题'),
          );
    final forward = next == null
        ? null
        : TextButton.icon(
            style: style,
            iconAlignment: IconAlignment.end,
            onPressed: () => onThreadLink(next),
            icon: const Icon(Icons.chevron_right),
            label: const Text('下一主题'),
          );
    if (back != null && forward != null) {
      // Too narrow for one line, 下一主题 goes under 上一主题, still at the end.
      return _SplitRow(leading: back, trailing: forward);
    }
    if (back != null) {
      return Align(alignment: AlignmentDirectional.centerStart, child: back);
    }
    if (forward != null) {
      return Align(alignment: AlignmentDirectional.centerEnd, child: forward);
    }
    return null;
  }

  /// Under a post: the toggles at the start of the row ending in [footer],
  /// then the neighbour row below a divider.
  Widget withFooter(Widget footer) {
    final row = toggles();
    final nav = neighbours();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (row == null)
          footer
        else
          _SplitRow(leading: row, trailing: IntrinsicWidth(child: footer)),
        if (nav != null) ...[
          const Divider(height: 1, endIndent: AppSpace.sm),
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpace.xs,
              right: AppSpace.sm,
              bottom: AppSpace.xs,
            ),
            child: nav,
          ),
        ],
      ],
    );
  }

  /// Without a post body: the toggles, then the neighbour row.
  @override
  Widget build(BuildContext context) {
    final row = toggles();
    final nav = neighbours();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (row != null) Align(alignment: Alignment.centerLeft, child: row),
        if (row != null && nav != null) const Divider(height: AppSpace.lg),
        if (nav != null) nav,
      ],
    );
  }
}

/// [leading] at the start and [trailing] at the end of one line; when both
/// don't fit, [leading] takes its own line above.
class _SplitRow extends MultiChildRenderObjectWidget {
  _SplitRow({required Widget leading, required Widget trailing})
      : super(children: [leading, trailing]);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSplitRow();
}

class _RenderSplitRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, MultiChildLayoutParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, MultiChildLayoutParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! MultiChildLayoutParentData) {
      child.parentData = MultiChildLayoutParentData();
    }
  }

  @override
  void performLayout() {
    final leading = firstChild!;
    final trailing = lastChild!;
    final loose = constraints.loosen();
    leading.layout(loose, parentUsesSize: true);
    trailing.layout(loose, parentUsesSize: true);
    final a = leading.size;
    final b = trailing.size;
    final width = constraints.maxWidth;
    final at = leading.parentData! as MultiChildLayoutParentData;
    final bt = trailing.parentData! as MultiChildLayoutParentData;
    if (a.width + b.width <= width) {
      final height = math.max(a.height, b.height);
      at.offset = Offset(0, (height - a.height) / 2);
      bt.offset = Offset(width - b.width, (height - b.height) / 2);
      size = constraints.constrain(Size(width, height));
    } else {
      at.offset = Offset.zero;
      bt.offset = Offset(width - b.width, a.height);
      size = constraints.constrain(Size(width, a.height + b.height));
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// A small tonal toggle (DESIGN.md §6): brand on brandSoft with a filled
/// icon when selected; busy swaps the icon for a spinner and disables it.
class _ThreadToggle extends StatelessWidget {
  const _ThreadToggle({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.busy = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final brand = selected ? AppColors.brand : null;
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        child: FilledButton.tonalIcon(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            iconSize: 16,
            // Drawn 32 high, tapped across 48.
            tapTargetSize: MaterialTapTargetSize.padded,
            visualDensity: VisualDensity.standard,
            // The small button's 13 px label (DESIGN.md §6).
            textStyle: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontWeight: FontWeight.w600),
            backgroundColor: selected ? AppColors.brandSoft : null,
            foregroundColor: brand,
            disabledBackgroundColor: selected ? AppColors.brandSoft : null,
            disabledForegroundColor: brand,
          ),
          icon: busy
              ? SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: brand ?? AppColors.textMuted,
                  ),
                )
              : Icon(selected ? selectedIcon : icon),
          label: Text(label),
        ),
      ),
    );
  }
}

/// The board name as the app bar title; opens the board when it is known.
class _BoardTitle extends StatelessWidget {
  const _BoardTitle({required this.name, required this.onTap});

  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Text(name, maxLines: 1, overflow: TextOverflow.ellipsis);
    final tap = onTap;
    if (tap == null) return text;
    return Tooltip(
      message: '打开版块',
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        // A full 48 px target, however short the title line is.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: text),
              Icon(Icons.chevron_right, size: 20, color: AppColors.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rare thread actions behind ⋮; an action without a target is omitted.
class _ThreadMoreMenu extends StatelessWidget {
  const _ThreadMoreMenu({required this.onSearchTitle, required this.onRss});

  final VoidCallback? onSearchTitle;
  final VoidCallback? onRss;

  @override
  Widget build(BuildContext context) {
    final items = [
      if (onSearchTitle != null)
        ('搜索同名主题', Icons.manage_search, onSearchTitle!),
      if (onRss != null) ('RSS 订阅', Icons.rss_feed_outlined, onRss!),
    ];
    return PopupMenuButton<VoidCallback>(
      tooltip: '更多',
      enabled: items.isNotEmpty,
      icon: const Icon(Icons.more_vert),
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        for (final (label, icon, action) in items)
          PopupMenuItem(
            value: action,
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppColors.textMuted),
                const SizedBox(width: AppSpace.md),
                Text(label),
              ],
            ),
          ),
      ],
    );
  }
}

/// Paging strip under the thread, in the app bar's colour: previous page,
/// the shown page (opens the 跳转 sheet), next page.
class _ThreadPageBar extends StatelessWidget {
  const _ThreadPageBar({
    required this.current,
    required this.total,
    required this.onSelected,
    required this.onJump,
  });

  final int current;
  final int total;

  /// Null while a page loads.
  final ValueChanged<int>? onSelected;
  final VoidCallback onJump;

  @override
  Widget build(BuildContext context) {
    final select = onSelected;
    Widget arrow(String tooltip, IconData icon, int page, bool enabled) =>
        IconButton(
          tooltip: tooltip,
          onPressed: enabled && select != null ? () => select(page) : null,
          icon: Icon(icon),
        );
    return Material(
      color: AppColors.surfaceTint,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppWidths.dialog,
                minHeight: 52,
              ),
              child: Row(
                children: [
                  arrow('上一页', Icons.chevron_left, current - 1, current > 1),
                  Expanded(
                    child: Tooltip(
                      message: '跳转',
                      child: InkWell(
                        onTap: onJump,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: AppSpace.md),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  '第 $current / $total 页',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(color: AppColors.text),
                                ),
                              ),
                              const SizedBox(width: AppSpace.xs),
                              Icon(
                                Icons.expand_less,
                                size: 18,
                                color: AppColors.textFaint,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  arrow(
                      '下一页', Icons.chevron_right, current + 1, current < total),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the sheet returns for 新建分类.
class _NewCategory {
  const _NewCategory();
}

const _newCategory = _NewCategory();

/// The forum's own favorite categories. Choosing one is the only way to
/// favorite from here; leaving the sheet any other way favorites nothing. It
/// closes itself when the session or the thread changes underneath it.
class _FavoriteCategorySheet extends StatefulWidget {
  const _FavoriteCategorySheet({
    required this.categories,
    required this.canCreate,
    required this.invalidated,
    required this.generation,
  });

  final List<FavoriteCategory> categories;
  final bool canCreate;

  /// Moves when the session or thread changes; [generation] is its value
  /// when the menu was asked for.
  final ValueListenable<int> invalidated;
  final int generation;

  @override
  State<_FavoriteCategorySheet> createState() => _FavoriteCategorySheetState();
}

class _FavoriteCategorySheetState extends State<_FavoriteCategorySheet> {
  bool get _stale => widget.invalidated.value != widget.generation;

  @override
  void initState() {
    super.initState();
    // A change before this first frame is closed once it is mounted.
    if (_stale) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
    } else {
      widget.invalidated.addListener(_check);
    }
  }

  @override
  void dispose() {
    widget.invalidated.removeListener(_check);
    super.dispose();
  }

  // Raised while the thread screen may be mid-build.
  void _check() => scheduleMicrotask(() {
        if (!mounted || !_stale) return;
        setState(() {});
        _close();
      });

  // Removes this sheet's own route, never one that lies above it.
  void _close() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_stale) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg, 0, AppSpace.lg, AppSpace.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text('选择收藏分类', style: theme.textTheme.titleMedium),
                  ),
                  Text('选好分类后才会收藏这个主题', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            for (final category in widget.categories)
              ListTile(
                key: ValueKey('favorite-category:${category.id}'),
                leading: const Icon(Icons.star_outline),
                title: Text(category.label),
                onTap: () => Navigator.of(context).pop(category),
              ),
            if (widget.canCreate)
              ListTile(
                key: const ValueKey('favorite-category-new'),
                leading: const Icon(Icons.add),
                title: const Text('新建分类'),
                onTap: () => Navigator.of(context).pop(_newCategory),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.sm),
              child: TextButton(
                key: const ValueKey('favorite-category-cancel'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
