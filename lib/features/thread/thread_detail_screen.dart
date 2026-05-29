import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
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
  final Map<String, ThreadFavoriteState> _favoriteOverrides =
      <String, ThreadFavoriteState>{};
  bool _favoriteBusy = false;
  bool _onlyOriginalPoster = false;
  late Future<ThreadDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchThreadDetail(widget.thread);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.repository.fetchThreadDetail(widget.thread);
    });
    await _future;
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

  void _scrollToReply() {
    final context = _replyKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
      return;
    }
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  void _quoteReply(ThreadReply reply) {
    final content = reply.content.length > 300
        ? '${reply.content.substring(0, 300)}...'
        : reply.content;
    final floor = reply.floor == null ? '' : ' ${reply.floor}';
    _replyKey.currentState?.insertContent(
      '[quote]引用 ${reply.author}$floor：$content[/quote]\n',
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('southplus'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '回复',
            onPressed: _scrollToReply,
            icon: const Icon(Icons.reply_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        onPressed: _scrollToReply,
        child: const Icon(Icons.edit_outlined),
      ),
      body: FutureBuilder<ThreadDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AsyncErrorView(
              title: '帖子加载失败',
              message: '${snapshot.error}',
              onRetry: _refresh,
            );
          }
          if (!snapshot.hasData) {
            return const ThreadDetailSkeleton();
          }
          final detail = snapshot.data!;
          final favorite = detail.favorite == null
              ? null
              : _effectiveFavorite(detail.favorite!);
          final originalAuthor = detail.thread.author;
          final replies = _onlyOriginalPoster && originalAuthor != null
              ? detail.replies
                  .where((reply) => reply.author == originalAuthor)
                  .toList()
              : detail.replies;
          return RefreshIndicator(
            color: AppColors.brand,
            onRefresh: _refresh,
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                _ThreadCrumbs(section: detail.thread.section),
                const SizedBox(height: 12),
                _FloorCard(
                  title: detail.thread.title,
                  author: detail.thread.author ?? '楼主',
                  onAuthorTap: detail.thread.authorUrl == null
                      ? null
                      : () => _openUserProfile(detail.thread.authorUrl!),
                  postedAt: detail.thread.lastPost,
                  floor: '楼主',
                  onQuote: null,
                  headerActions: _ThreadHeaderActions(
                    favorite: favorite,
                    favoriteBusy: _favoriteBusy,
                    onFavorite: favorite == null
                        ? null
                        : () => _handleFavorite(favorite),
                    onlyOriginalPoster: _onlyOriginalPoster,
                    originalAuthor: originalAuthor,
                    onOnlyOriginalPosterChanged: originalAuthor == null
                        ? null
                        : (selected) {
                            setState(() {
                              _onlyOriginalPoster = selected;
                            });
                          },
                  ),
                  child: ThreadPostBody(
                    content: detail.body,
                    segments: detail.bodySegments,
                    quote: null,
                    images: detail.bodyImages,
                    links: detail.bodyLinks,
                    saleBoxes: detail.bodySaleBoxes,
                    saleBoxesFirst: detail.bodySaleBoxesFirst,
                    buyingSaleBoxes: _buyingSaleBoxes,
                    onBuySaleBox: _handleBuySaleBox,
                  ),
                ),
                const SizedBox(height: 16),
                if (_onlyOriginalPoster && replies.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: EmptyStateView(
                      title: '没有楼主回复',
                      message: '当前页只包含其他用户回复。',
                    ),
                  ),
                ...replies.map(
                  (reply) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _FloorCard(
                      author: reply.author,
                      onAuthorTap: reply.authorUrl == null
                          ? null
                          : () => _openUserProfile(reply.authorUrl!),
                      postedAt: reply.postedAt,
                      floor: reply.floor,
                      onQuote: () => _quoteReply(reply),
                      child: ThreadPostBody(
                        content: reply.content,
                        segments: reply.segments,
                        quote: reply.quote,
                        images: reply.images,
                        links: reply.links,
                        saleBoxes: reply.saleBoxes,
                        saleBoxesFirst: reply.saleBoxesFirst,
                        buyingSaleBoxes: _buyingSaleBoxes,
                        onBuySaleBox: _handleBuySaleBox,
                      ),
                    ),
                  ),
                ),
                ReplyComposer(
                  key: _replyKey,
                  thread: detail.thread,
                  repository: widget.repository,
                  onSubmitted: _handleReplySubmitted,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ThreadCrumbs extends StatelessWidget {
  const _ThreadCrumbs({required this.section});

  final String section;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 13, 20, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          const Text(
            '南+ South Plus',
            style: TextStyle(
              color: AppColors.brand,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: AppColors.textFaint),
          Text(
            section,
            style: const TextStyle(
              color: AppColors.brand,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
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
    this.onAuthorTap,
    this.postedAt,
    this.floor,
    this.onQuote,
    this.headerActions,
  });

  final String author;
  final String? title;
  final VoidCallback? onAuthorTap;
  final String? postedAt;
  final String? floor;
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
                          style: const TextStyle(
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
                    style: const TextStyle(
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
            if (onQuote != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onQuote,
                icon: const Icon(Icons.reply, size: 16),
                label: const Text('回复'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(64, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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
    const style = TextStyle(
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
  });

  final ThreadFavorite? favorite;
  final bool favoriteBusy;
  final VoidCallback? onFavorite;
  final bool onlyOriginalPoster;
  final String? originalAuthor;
  final ValueChanged<bool>? onOnlyOriginalPosterChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
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
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 11),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
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
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
      ],
    );
  }
}
