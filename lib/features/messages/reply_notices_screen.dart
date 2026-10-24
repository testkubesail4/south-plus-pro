import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../common/content_width.dart';
import '../common/grouped_list.dart';
import '../common/thread_row.dart';
import '../thread/thread_detail_screen.dart';

/// The site's 回复提醒 list: replies to the user's threads, each removable.
class ReplyNoticesScreen extends StatefulWidget {
  const ReplyNoticesScreen({
    super.key,
    required this.repository,
    this.embedded = false,
  });

  final ForumRepository repository;

  /// Inside the 消息 tab, which supplies the app bar.
  final bool embedded;

  @override
  State<ReplyNoticesScreen> createState() => _ReplyNoticesScreenState();
}

class _ReplyNoticesScreenState extends State<ReplyNoticesScreen> {
  List<ForumReplyNotice>? _notices;
  Object? _error;
  final _deleting = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final notices = await widget.repository.fetchReplyNotices();
      if (mounted) setState(() => _notices = notices);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
      // A failed refresh keeps the rows already shown.
      if (_notices != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('刷新失败：${forumErrorText(error)}')),
        );
      }
    }
  }

  Future<void> _delete(ForumReplyNotice notice) async {
    setState(() => _deleting.add(notice.tid));
    try {
      await widget.repository.deleteReplyNotice(notice);
      if (!mounted) return;
      setState(() => _notices?.removeWhere((item) => item.tid == notice.tid));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：${forumErrorText(error)}')),
      );
    } finally {
      if (mounted) setState(() => _deleting.remove(notice.tid));
    }
  }

  // A notice names a thread, not a floor: a bare link opens the latest page,
  // where the new replies are; a link with its own page or floor keeps it.
  void _open(ForumReplyNotice notice) {
    var thread = ForumThread(
      title: notice.title,
      url: notice.threadUrl,
      replies: 0,
      section: notice.board,
    );
    final url = notice.threadUrl;
    final located = (Uri.tryParse(url)?.fragment.isNotEmpty ?? false) ||
        RegExp(r'[-&?]page[-=]').hasMatch(url);
    if (!located) {
      if (widget.repository.latestThreadPageUrl(thread) case final latest?) {
        thread = thread.copyWith(url: latest);
      }
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThreadDetailScreen(
          thread: thread,
          repository: widget.repository,
        ),
      ),
    );
  }

  Widget _noticeRow(ForumReplyNotice notice) => ForumThreadRow(
        title: notice.title,
        meta: [notice.board, notice.date],
        trailing: _deleting.contains(notice.tid)
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                tooltip: '删除提醒',
                icon: const Icon(Icons.close),
                onPressed: () => _delete(notice),
              ),
        onTap: () => _open(notice),
      );

  @override
  Widget build(BuildContext context) {
    final notices = _notices;
    final error = _error;
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('回复提醒')),
      body: error != null && notices == null
          ? AsyncErrorView(
              title: '回复提醒加载失败',
              message: forumErrorText(error),
              onRetry: _load,
            )
          : notices == null
              ? const ThreadListSkeleton(itemCount: 6)
              : RefreshIndicator(
                  color: AppColors.brand,
                  onRefresh: _load,
                  child: notices.isEmpty
                      ? ListView(
                          children: const [
                            EmptyStateView(
                              title: '暂无回复提醒',
                              icon: Icons.mark_chat_read_outlined,
                            ),
                          ],
                        )
                      // One grouped surface, as wide as any list (D§4, D§8).
                      : ListView(
                          padding:
                              const EdgeInsets.symmetric(vertical: AppSpace.md),
                          children: [
                            AppContentWidth(
                              maxWidth: AppWidths.list,
                              child: AppGroup(
                                dividerIndent: AppSpace.lg,
                                children: [
                                  for (final notice in notices)
                                    _noticeRow(notice),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
    );
  }
}
