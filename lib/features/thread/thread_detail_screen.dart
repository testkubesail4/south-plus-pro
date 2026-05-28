import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../reply/reply_sheet.dart';

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
        title: const Text('帖子详情'),
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
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '帖子加载失败',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final detail = snapshot.data!;
          final favorite = detail.favorite == null
              ? null
              : _effectiveFavorite(detail.favorite!);
          return RefreshIndicator(
            color: AppColors.brand,
            onRefresh: _refresh,
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail.thread.title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ThreadMetaChip(
                            icon: Icons.tag_outlined,
                            text: detail.thread.section,
                          ),
                          if (detail.thread.author != null)
                            _ThreadMetaChip(
                              icon: Icons.person_outline,
                              text: detail.thread.author!,
                              highlighted: true,
                            ),
                          if (detail.thread.lastPost != null)
                            _ThreadMetaChip(
                              icon: Icons.schedule_outlined,
                              text: detail.thread.lastPost!,
                            ),
                        ],
                      ),
                      if (favorite != null) ...[
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: _favoriteBusy
                              ? null
                              : () => _handleFavorite(favorite),
                          icon: _favoriteBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(
                                  favorite.canRemove
                                      ? Icons.star
                                      : Icons.star_border,
                                ),
                          label: Text(favorite.canRemove ? '取消收藏' : '收藏'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _ThreadPostBody(
                      content: detail.body,
                      quote: null,
                      images: detail.bodyImages,
                      links: detail.bodyLinks,
                      saleBoxes: detail.bodySaleBoxes,
                      saleBoxesFirst: detail.bodySaleBoxesFirst,
                      buyingSaleBoxes: _buyingSaleBoxes,
                      onBuySaleBox: _handleBuySaleBox,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ...detail.replies.map(
                  (reply) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: AppColors.brandSoft,
                                  child: Text(
                                    reply.author.characters.firstOrNull ?? '?',
                                    style: const TextStyle(
                                      color: AppColors.brand,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        reply.author,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                      if (reply.postedAt != null)
                                        Text(
                                          reply.postedAt!,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: '引用',
                                  onPressed: () => _quoteReply(reply),
                                  icon: const Icon(Icons.format_quote),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _ThreadPostBody(
                              content: reply.content,
                              quote: reply.quote,
                              images: reply.images,
                              links: reply.links,
                              saleBoxes: reply.saleBoxes,
                              saleBoxesFirst: reply.saleBoxesFirst,
                              buyingSaleBoxes: _buyingSaleBoxes,
                              onBuySaleBox: _handleBuySaleBox,
                            ),
                          ],
                        ),
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

class _ThreadMetaChip extends StatelessWidget {
  const _ThreadMetaChip({
    required this.icon,
    required this.text,
    this.highlighted = false,
  });

  final IconData icon;
  final String text;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: highlighted ? AppColors.brandSoft : AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: highlighted ? AppColors.brand : AppColors.textMuted,
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: highlighted ? AppColors.brand : AppColors.textMuted,
              fontSize: 12,
              fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadPostBody extends StatelessWidget {
  const _ThreadPostBody({
    required this.content,
    required this.quote,
    required this.images,
    required this.links,
    required this.saleBoxes,
    required this.saleBoxesFirst,
    required this.buyingSaleBoxes,
    required this.onBuySaleBox,
  });

  final String content;
  final String? quote;
  final List<ThreadImage> images;
  final List<ThreadLink> links;
  final List<ThreadSaleBox> saleBoxes;
  final bool saleBoxesFirst;
  final Set<String> buyingSaleBoxes;
  final ValueChanged<ThreadSaleBox> onBuySaleBox;

  @override
  Widget build(BuildContext context) {
    final saleBoxWidgets = saleBoxes
        .map(
          (saleBox) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SaleBoxView(
              saleBox: saleBox,
              isBuying: buyingSaleBoxes.contains(saleBox.buyPath),
              onBuy: () => onBuySaleBox(saleBox),
            ),
          ),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (saleBoxesFirst) ...saleBoxWidgets,
        if (quote != null) ...[
          _QuoteView(text: quote!),
          if (content.isNotEmpty) const SizedBox(height: 12),
        ],
        if (content.isNotEmpty)
          Text(content, style: Theme.of(context).textTheme.bodyMedium),
        if (images.isNotEmpty) ...[
          if (content.isNotEmpty || quote != null) const SizedBox(height: 12),
          ...images.map(
            (image) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ThreadImageView(image: image),
            ),
          ),
        ],
        if (links.isNotEmpty) ...[
          if (content.isNotEmpty || quote != null || images.isNotEmpty)
            const SizedBox(height: 8),
          _ThreadLinkList(links: links),
        ],
        if (!saleBoxesFirst && saleBoxes.isNotEmpty) ...[
          if (content.isNotEmpty || images.isNotEmpty || links.isNotEmpty)
            const SizedBox(height: 12),
          ...saleBoxWidgets,
        ],
      ],
    );
  }
}

class _ThreadImageView extends StatelessWidget {
  const _ThreadImageView({required this.image});

  final ThreadImage image;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: InteractiveViewer(
            child: Image.network(image.url, fit: BoxFit.contain),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 360),
          color: AppColors.surfaceTint,
          child: Image.network(
            image.url,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return const SizedBox(
                height: 96,
                child: Center(child: Text('图片加载失败')),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ThreadLinkList extends StatelessWidget {
  const _ThreadLinkList({required this.links});

  final List<ThreadLink> links;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxChipWidth =
            constraints.maxWidth < 280 ? constraints.maxWidth : 280.0;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: links
              .map(
                (link) => ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxChipWidth),
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: link.url));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('链接已复制')),
                      );
                    },
                    icon: const Icon(Icons.link, size: 16),
                    label: Text(
                      link.label,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _QuoteView extends StatelessWidget {
  const _QuoteView({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: AppColors.brand, width: 4),
        ),
        color: AppColors.surfaceTint,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _SaleBoxView extends StatelessWidget {
  const _SaleBoxView({
    required this.saleBox,
    required this.isBuying,
    required this.onBuy,
  });

  final ThreadSaleBox saleBox;
  final bool isBuying;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.brandSoft,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                saleBox.summary,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.brandDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isBuying ? null : onBuy,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: isBuying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('愿意购买,我买,我付钱'),
                ),
              ),
            ],
          ),
        ),
        if (saleBox.warning != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: AppColors.brand, width: 4),
              ),
              color: AppColors.surface,
            ),
            child: Text(
              saleBox.warning!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xff555555),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
