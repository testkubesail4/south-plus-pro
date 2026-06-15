import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/external_link_launcher.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../common/cached_forum_image.dart';
import '../profile/user_profile_screen.dart';
import '../reply/reply_sheet.dart';
import 'thread_post_body.dart';

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
  final Set<String> _loadingQuoteDrafts = <String>{};
  final Map<String, ThreadFavoriteState> _favoriteOverrides =
      <String, ThreadFavoriteState>{};
  bool _favoriteBusy = false;
  bool _onlyOriginalPoster = false;
  bool _loading = true;
  Object? _loadError;
  late ForumThread _thread;
  String? _authorFilterName;
  ThreadDetail? _detail;
  int _page = 1;
  int _loadRunId = 0;

  @override
  void initState() {
    super.initState();
    _thread = widget.thread;
    _loadPage(1);
  }

  @override
  void didUpdateWidget(covariant ThreadDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thread.url == widget.thread.url) return;
    _thread = widget.thread;
    _authorFilterName = null;
    _onlyOriginalPoster = false;
    _detail = null;
    _page = 1;
    _loadPage(1);
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
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final detail = await widget.repository.fetchThreadDetail(
        _thread,
        page: normalizedPage,
      );
      if (!mounted || runId != _loadRunId) return;
      setState(() {
        _detail = detail;
        _thread = detail.thread;
        _page = detail.pagination.currentPage;
        _loading = false;
      });
      if (scrollToTop && _scrollController.hasClients) {
        await _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    } catch (error) {
      if (!mounted || runId != _loadRunId) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
      if (_detail != null && showSnackBarOnError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('页面加载失败：$error')),
        );
      }
    }
  }

  Future<void> _goToPage(int page) async {
    final detail = _detail;
    if (detail != null) {
      final target = page.clamp(1, detail.pagination.totalPages).toInt();
      if (target == _page) return;
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

  Future<void> _showOriginalPosterPosts(ForumThread thread) async {
    final authorPostsUrl = thread.authorPostsUrl;
    if (authorPostsUrl == null || authorPostsUrl.isEmpty) {
      setState(() => _onlyOriginalPoster = true);
      return;
    }
    await _showAuthorFilter(authorPostsUrl, thread.author ?? '楼主');
  }

  Future<void> _showAuthorFilter(String authorPostsUrl, String author) async {
    final current = _detail?.thread ?? _thread;
    setState(() {
      _thread = current.copyWith(url: authorPostsUrl);
      _authorFilterName = author;
      _onlyOriginalPoster = false;
    });
    await _loadPage(1, scrollToTop: true);
  }

  Future<void> _clearAuthorFilter() async {
    if (_authorFilterName == null) return;
    setState(() {
      _thread = widget.thread;
      _authorFilterName = null;
      _onlyOriginalPoster = false;
    });
    await _loadPage(1, scrollToTop: true);
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
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _scrollToReply() async {
    final context = _replyKey.currentContext;
    if (context != null) {
      await Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
      _replyKey.currentState?.focusContent();
      return;
    }
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
    _replyKey.currentState?.focusContent();
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
      _scrollToReply();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('引用加载失败，已使用本地引用：$error')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingQuoteDrafts.remove(quoteUrl);
      });
    }
    _scrollToReply();
  }

  Future<void> _handleReplySubmitted(String result) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$result，已刷新当前页')),
    );
    await _refresh();
  }

  Future<void> _handleBuySaleBox(ThreadSaleBox saleBox) async {
    if (_buyingSaleBoxes.contains(saleBox.buyPath)) return;
    setState(() {
      _buyingSaleBoxes.add(saleBox.buyPath);
    });

    try {
      final result = await widget.repository.buySaleBox(saleBox);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.success ? '${result.message}，已刷新当前页' : result.message,
          ),
        ),
      );
      if (result.success) {
        await _refresh();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('购买失败：$error')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _buyingSaleBoxes.remove(saleBox.buyPath);
      });
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
    setState(() {
      _favoriteBusy = true;
    });

    try {
      final result = effective.canRemove
          ? await widget.repository.removeFavorite(effective)
          : await widget.repository.addFavorite(effective);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      if (result.success) {
        setState(() {
          _favoriteOverrides[effective.tid] = result.state;
        });
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('收藏操作失败：$error')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _favoriteBusy = false;
      });
    }
  }

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

  Future<void> _openExternalLink(ThreadActionLink link) async {
    try {
      await ExternalLinkLauncher.open(link.url);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '南+ / ${detail?.thread.section ?? widget.thread.section}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '回复',
            onPressed: () => _scrollToReply(),
            icon: Icon(Icons.reply_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        onPressed: () => _scrollToReply(),
        child: Icon(Icons.edit_outlined),
      ),
      body: detail == null
          ? _InitialThreadState(
              error: _loadError,
              onRetry: _refresh,
            )
          : _ThreadDetailContent(
              detail: detail,
              loading: _loading,
              onlyOriginalPoster: _onlyOriginalPoster,
              authorFilterName: _authorFilterName,
              favorite: detail.favorite == null
                  ? null
                  : _effectiveFavorite(detail.favorite!),
              favoriteBusy: _favoriteBusy,
              buyingSaleBoxes: _buyingSaleBoxes,
              loadingQuoteDrafts: _loadingQuoteDrafts,
              scrollController: _scrollController,
              replyKey: _replyKey,
              onRefresh: _refresh,
              onAuthorTap: _openUserProfile,
              onFavorite: _handleFavorite,
              onOnlyOriginalPosterChanged: (selected) {
                setState(() => _onlyOriginalPoster = selected);
              },
              onShowOriginalPosterPosts: _showOriginalPosterPosts,
              onShowAuthorPosts: _showAuthorPosts,
              onClearAuthorFilter: _clearAuthorFilter,
              onQuoteReply: _quoteReply,
              onBuySaleBox: _handleBuySaleBox,
              onReplySubmitted: _handleReplySubmitted,
              onPageSelected: _goToPage,
              onThreadLink: _openThreadLink,
              onExternalLink: _openExternalLink,
              repository: widget.repository,
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
    required this.loading,
    required this.onlyOriginalPoster,
    required this.authorFilterName,
    required this.favorite,
    required this.favoriteBusy,
    required this.buyingSaleBoxes,
    required this.loadingQuoteDrafts,
    required this.scrollController,
    required this.replyKey,
    required this.onRefresh,
    required this.onAuthorTap,
    required this.onFavorite,
    required this.onOnlyOriginalPosterChanged,
    required this.onShowOriginalPosterPosts,
    required this.onShowAuthorPosts,
    required this.onClearAuthorFilter,
    required this.onQuoteReply,
    required this.onBuySaleBox,
    required this.onReplySubmitted,
    required this.onPageSelected,
    required this.onThreadLink,
    required this.onExternalLink,
    required this.repository,
  });

  final ThreadDetail detail;
  final bool loading;
  final bool onlyOriginalPoster;
  final String? authorFilterName;
  final ThreadFavorite? favorite;
  final bool favoriteBusy;
  final Set<String> buyingSaleBoxes;
  final Set<String> loadingQuoteDrafts;
  final ScrollController scrollController;
  final GlobalKey<ReplyComposerState> replyKey;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onAuthorTap;
  final ValueChanged<ThreadFavorite> onFavorite;
  final ValueChanged<bool> onOnlyOriginalPosterChanged;
  final ValueChanged<ForumThread> onShowOriginalPosterPosts;
  final ValueChanged<ThreadReply> onShowAuthorPosts;
  final VoidCallback onClearAuthorFilter;
  final Future<void> Function(ThreadReply) onQuoteReply;
  final ValueChanged<ThreadSaleBox> onBuySaleBox;
  final ValueChanged<String> onReplySubmitted;
  final ValueChanged<int> onPageSelected;
  final ValueChanged<ThreadActionLink> onThreadLink;
  final ValueChanged<ThreadActionLink> onExternalLink;
  final ForumRepository repository;

  @override
  Widget build(BuildContext context) {
    final originalAuthor = detail.thread.author;
    final originalPosterFilterActive = authorFilterName != null &&
        originalAuthor != null &&
        authorFilterName == originalAuthor;
    final onlyOriginalPosterActive =
        onlyOriginalPoster || originalPosterFilterActive;
    final replies = onlyOriginalPosterActive && originalAuthor != null
        ? detail.replies
            .where((reply) => reply.author == originalAuthor)
            .toList()
        : detail.replies;
    final hasOpeningPost = detail.body.trim().isNotEmpty ||
        detail.bodySegments.isNotEmpty ||
        detail.bodyImages.isNotEmpty ||
        detail.bodyLinks.isNotEmpty ||
        detail.bodySaleBoxes.isNotEmpty;
    final visibleFloorCount = replies.length + (hasOpeningPost ? 1 : 0);

    return Stack(
      children: [
        RefreshIndicator(
          color: AppColors.brand,
          onRefresh: onRefresh,
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              const SizedBox(height: 12),
              _ThreadPaginationBar(
                pagination: detail.pagination,
                onPageSelected: loading ? null : onPageSelected,
              ),
              const SizedBox(height: 12),
              if (hasOpeningPost)
                _FloorCard(
                  title: detail.thread.title,
                  author: detail.thread.author ?? '楼主',
                  avatarUrl: detail.thread.authorAvatarUrl,
                  onAuthorTap: detail.thread.authorUrl == null
                      ? null
                      : () => onAuthorTap(detail.thread.authorUrl!),
                  postedAt: detail.thread.lastPost,
                  floor: '楼主',
                  onQuote: null,
                  headerActions: _ThreadHeaderActions(
                    favorite: favorite,
                    favoriteBusy: favoriteBusy,
                    onFavorite:
                        favorite == null ? null : () => onFavorite(favorite!),
                    onlyOriginalPoster: onlyOriginalPosterActive,
                    originalAuthor: originalAuthor,
                    onOnlyOriginalPosterChanged: originalAuthor == null
                        ? null
                        : (selected) {
                            if (selected) {
                              onShowOriginalPosterPosts(detail.thread);
                            } else if (authorFilterName != null) {
                              onClearAuthorFilter();
                            } else {
                              onOnlyOriginalPosterChanged(false);
                            }
                          },
                    previousThread: detail.previousThread,
                    nextThread: detail.nextThread,
                    rssFeed: detail.rssFeed,
                    onThreadLink: onThreadLink,
                    onExternalLink: onExternalLink,
                  ),
                  child: ThreadPostBody(
                    content: detail.body,
                    segments: detail.bodySegments,
                    quote: null,
                    images: detail.bodyImages,
                    links: detail.bodyLinks,
                    saleBoxes: detail.bodySaleBoxes,
                    saleBoxesFirst: detail.bodySaleBoxesFirst,
                    buyingSaleBoxes: buyingSaleBoxes,
                    onBuySaleBox: onBuySaleBox,
                  ),
                )
              else
                _ThreadHeaderCard(
                  title: detail.thread.title,
                  author: detail.thread.author,
                  avatarUrl: detail.thread.authorAvatarUrl,
                  onAuthorTap: detail.thread.authorUrl == null
                      ? null
                      : () => onAuthorTap(detail.thread.authorUrl!),
                  pagination: detail.pagination,
                  actions: _ThreadHeaderActions(
                    favorite: favorite,
                    favoriteBusy: favoriteBusy,
                    onFavorite:
                        favorite == null ? null : () => onFavorite(favorite!),
                    onlyOriginalPoster: onlyOriginalPosterActive,
                    originalAuthor: originalAuthor,
                    onOnlyOriginalPosterChanged: originalAuthor == null
                        ? null
                        : (selected) {
                            if (selected) {
                              onShowOriginalPosterPosts(detail.thread);
                            } else if (authorFilterName != null) {
                              onClearAuthorFilter();
                            } else {
                              onOnlyOriginalPosterChanged(false);
                            }
                          },
                    previousThread: detail.previousThread,
                    nextThread: detail.nextThread,
                    rssFeed: detail.rssFeed,
                    onThreadLink: onThreadLink,
                    onExternalLink: onExternalLink,
                  ),
                ),
              if (authorFilterName != null) ...[
                const SizedBox(height: 10),
                _ActiveAuthorFilterChip(
                  author: authorFilterName!,
                  loading: loading,
                  pagination: detail.pagination,
                  visibleFloorCount: visibleFloorCount,
                  onClear: onClearAuthorFilter,
                ),
              ],
              const SizedBox(height: 16),
              if (onlyOriginalPoster && replies.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: EmptyStateView(
                    title: '没有楼主回复',
                    message: '当前页只包含其他用户回复。',
                  ),
                ),
              if (authorFilterName != null && visibleFloorCount == 0)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: EmptyStateView(
                    title: '没有该作者内容',
                    message: '当前筛选结果没有可展示的楼层。',
                  ),
                ),
              ...replies.map(
                (reply) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _FloorCard(
                    author: reply.author,
                    avatarUrl: reply.authorAvatarUrl,
                    onAuthorTap: reply.authorUrl == null
                        ? null
                        : () => onAuthorTap(reply.authorUrl!),
                    postedAt: reply.postedAt,
                    floor: reply.floor,
                    onShowAuthorPosts: reply.authorPostsUrl == null
                        ? null
                        : () => onShowAuthorPosts(reply),
                    quoteLoading: reply.quoteUrl != null &&
                        loadingQuoteDrafts.contains(reply.quoteUrl),
                    onQuote: () => onQuoteReply(reply),
                    child: ThreadPostBody(
                      content: reply.content,
                      segments: reply.segments,
                      quote: reply.quote,
                      images: reply.images,
                      links: reply.links,
                      saleBoxes: reply.saleBoxes,
                      saleBoxesFirst: reply.saleBoxesFirst,
                      buyingSaleBoxes: buyingSaleBoxes,
                      onBuySaleBox: onBuySaleBox,
                    ),
                  ),
                ),
              ),
              _ThreadPaginationBar(
                pagination: detail.pagination,
                onPageSelected: loading ? null : onPageSelected,
              ),
              const SizedBox(height: 12),
              ReplyComposer(
                key: replyKey,
                thread: detail.thread,
                repository: repository,
                onSubmitted: onReplySubmitted,
              ),
            ],
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
  }
}

class _ThreadHeaderCard extends StatelessWidget {
  const _ThreadHeaderCard({
    required this.title,
    required this.pagination,
    required this.actions,
    this.author,
    this.avatarUrl,
    this.onAuthorTap,
  });

  final String title;
  final String? author;
  final String? avatarUrl;
  final VoidCallback? onAuthorTap;
  final ThreadPagination pagination;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final authorName = author;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (authorName != null && authorName.isNotEmpty) ...[
                  _AuthorAvatar(
                    author: authorName,
                    avatarUrl: avatarUrl,
                    onTap: onAuthorTap,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    authorName == null || authorName.isEmpty
                        ? '第 ${pagination.currentPage} 页'
                        : '$authorName · 第 ${pagination.currentPage} 页',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.inkSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.person_search_outlined,
            size: 18,
            color: AppColors.link,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '只看 $author',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '第 ${pagination.currentPage} / ${pagination.totalPages} 页 · 本页 $visibleFloorCount 楼',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
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
    this.floor,
    this.onShowAuthorPosts,
    this.quoteLoading = false,
    this.onQuote,
    this.headerActions,
  });

  final String author;
  final String? title;
  final String? avatarUrl;
  final VoidCallback? onAuthorTap;
  final String? postedAt;
  final String? floor;
  final VoidCallback? onShowAuthorPosts;
  final bool quoteLoading;
  final VoidCallback? onQuote;
  final Widget? headerActions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final floorText = floor == null || floor!.isEmpty ? null : '[$floor]';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(
                title!,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AuthorAvatar(
                  author: author,
                  avatarUrl: avatarUrl,
                  onTap: onAuthorTap,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 2,
                    children: [
                      _FloorAuthorName(
                        author: author,
                        onTap: onAuthorTap,
                      ),
                      if (postedAt != null)
                        Text(
                          '- $postedAt',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                if (floorText != null)
                  Text(
                    floorText,
                    style: TextStyle(
                      color: AppColors.link,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            if (headerActions != null) ...[
              const SizedBox(height: 12),
              headerActions!,
            ],
            const SizedBox(height: 12),
            child,
            if (onShowAuthorPosts != null || onQuote != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: PopupMenuButton<_FloorAction>(
                  key: ValueKey('floor-actions-$author-$floor'),
                  tooltip: '更多操作',
                  icon: Icon(Icons.more_horiz),
                  constraints: const BoxConstraints(minWidth: 180),
                  onSelected: (action) {
                    switch (action) {
                      case _FloorAction.showAuthorPosts:
                        onShowAuthorPosts?.call();
                        break;
                      case _FloorAction.quote:
                        onQuote?.call();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    if (onShowAuthorPosts != null)
                      const PopupMenuItem(
                        value: _FloorAction.showAuthorPosts,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.person_search_outlined),
                          title: Text('只看该作者'),
                          dense: true,
                        ),
                      ),
                    if (onQuote != null)
                      PopupMenuItem(
                        value: _FloorAction.quote,
                        enabled: !quoteLoading,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: quoteLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(Icons.format_quote),
                          title: Text(quoteLoading ? '引用中...' : '引用'),
                          dense: true,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _FloorAction {
  showAuthorPosts,
  quote,
}

class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({
    required this.author,
    required this.avatarUrl,
    required this.onTap,
  });

  final String author;
  final String? avatarUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl = avatarUrl;
    return Semantics(
      label: '$author 的头像',
      image: true,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: 44,
            child: ClipOval(
              child: imageUrl == null || imageUrl.isEmpty
                  ? _AvatarFallback(author: author)
                  : CachedNetworkImage(
                      imageUrl: imageUrl,
                      cacheManager: ForumImageCache.manager,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) =>
                          _AvatarFallback(author: author),
                    ),
            ),
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
          style: TextStyle(
            color: AppColors.link,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ThreadPaginationBar extends StatelessWidget {
  const _ThreadPaginationBar({
    required this.pagination,
    required this.onPageSelected,
  });

  final ThreadPagination pagination;
  final ValueChanged<int>? onPageSelected;

  @override
  Widget build(BuildContext context) {
    if (pagination.totalPages <= 1) {
      return const SizedBox.shrink();
    }
    final visiblePages = _visiblePages();

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 8,
      children: [
        _PageBox(
          label: '«',
          tooltip: '上一页',
          enabled: pagination.hasPrevious && onPageSelected != null,
          onPressed: () => onPageSelected?.call(pagination.currentPage - 1),
        ),
        for (final pageNumber in visiblePages)
          _PageBox(
            label: '$pageNumber',
            selected: pageNumber == pagination.currentPage,
            enabled: onPageSelected != null,
            onPressed: () => onPageSelected?.call(pageNumber),
          ),
        _PageBox(
          label: '跳转',
          tooltip: '跳转页码',
          wide: true,
          enabled: onPageSelected != null,
          onPressed: () => _showJumpDialog(context),
        ),
        _PageBox(
          label: '»',
          tooltip: '下一页',
          enabled: pagination.hasNext && onPageSelected != null,
          onPressed: () => onPageSelected?.call(pagination.currentPage + 1),
        ),
        Text(
          '${pagination.currentPage} / ${pagination.totalPages}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  List<int> _visiblePages() {
    const windowSize = 5;
    final total = pagination.totalPages < 1 ? 1 : pagination.totalPages;
    final current = pagination.currentPage.clamp(1, total);
    if (total <= windowSize) {
      return [for (var i = 1; i <= total; i++) i];
    }

    var start = current - 2;
    var end = current + 2;
    if (start < 1) {
      end += 1 - start;
      start = 1;
    }
    if (end > total) {
      start -= end - total;
      end = total;
    }
    if (start < 1) start = 1;
    return [for (var i = start; i <= end; i++) i];
  }

  Future<void> _showJumpDialog(BuildContext context) async {
    final controller = TextEditingController(text: '${pagination.currentPage}');
    final selected = await showDialog<int>(
      context: context,
      builder: (context) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('跳转页码'),
              content: TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '页码',
                  helperText: '1 - ${pagination.totalPages}',
                  errorText: errorText,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final input = int.tryParse(controller.text.trim());
                    if (input == null) {
                      setDialogState(() {
                        errorText = '请输入有效页码';
                      });
                      return;
                    }
                    Navigator.of(context).pop(
                      input.clamp(1, pagination.totalPages).toInt(),
                    );
                  },
                  child: const Text('跳转'),
                ),
              ],
            );
          },
        );
      },
    );
    if (selected != null) onPageSelected?.call(selected);
  }
}

class _PageBox extends StatelessWidget {
  const _PageBox({
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.tooltip,
    this.selected = false,
    this.wide = false,
  });

  final String label;
  final String? tooltip;
  final bool enabled;
  final VoidCallback onPressed;
  final bool selected;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? Colors.white
        : enabled
            ? AppColors.link
            : AppColors.textFaint;
    final background = selected ? AppColors.brand : AppColors.surface;
    final box = SizedBox(
      width: wide ? 58 : 44,
      height: 44,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? onPressed : null,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? AppColors.brand : AppColors.border,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
    if (tooltip == null) return box;
    return Tooltip(message: tooltip!, child: box);
  }
}

class _FloorAuthorName extends StatelessWidget {
  const _FloorAuthorName({
    required this.author,
    this.onTap,
  });

  final String author;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: AppColors.brand,
      fontSize: 15,
      fontWeight: FontWeight.w800,
    );

    if (onTap == null) {
      return Text(author, style: style);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Text(author, style: style),
    );
  }
}

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
    required this.rssFeed,
    required this.onThreadLink,
    required this.onExternalLink,
  });

  final ThreadFavorite? favorite;
  final bool favoriteBusy;
  final VoidCallback? onFavorite;
  final bool onlyOriginalPoster;
  final String? originalAuthor;
  final ValueChanged<bool>? onOnlyOriginalPosterChanged;
  final ThreadActionLink? previousThread;
  final ThreadActionLink? nextThread;
  final ThreadActionLink? rssFeed;
  final ValueChanged<ThreadActionLink> onThreadLink;
  final ValueChanged<ThreadActionLink> onExternalLink;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (previousThread != null)
          OutlinedButton.icon(
            onPressed: () => onThreadLink(previousThread!),
            icon: Icon(Icons.chevron_left, size: 18),
            label: Text(previousThread!.label),
            style: _compactActionStyle(),
          ),
        if (nextThread != null)
          OutlinedButton.icon(
            onPressed: () => onThreadLink(nextThread!),
            icon: Icon(Icons.chevron_right, size: 18),
            label: Text(nextThread!.label),
            style: _compactActionStyle(),
          ),
        if (rssFeed != null)
          OutlinedButton.icon(
            onPressed: () => onExternalLink(rssFeed!),
            icon: Icon(Icons.rss_feed, size: 18),
            label: const Text('RSS'),
            style: _compactActionStyle(),
          ),
        if (favorite != null)
          OutlinedButton.icon(
            onPressed: favoriteBusy ? null : onFavorite,
            icon: favoriteBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    favorite!.canRemove ? Icons.star : Icons.star_border,
                    size: 17,
                  ),
            label: Text(favorite!.canRemove ? '取消收藏' : '收藏'),
            style: _compactActionStyle(),
          ),
        FilterChip(
          selected: onlyOriginalPoster,
          showCheckmark: false,
          avatar: Icon(
            onlyOriginalPoster ? Icons.person : Icons.person_outline,
            size: 17,
          ),
          label: const Text('只看楼主'),
          onSelected:
              originalAuthor == null ? null : onOnlyOriginalPosterChanged,
          materialTapTargetSize: MaterialTapTargetSize.padded,
          labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
      ],
    );
  }

  ButtonStyle _compactActionStyle() {
    return OutlinedButton.styleFrom(
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      tapTargetSize: MaterialTapTargetSize.padded,
      textStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
