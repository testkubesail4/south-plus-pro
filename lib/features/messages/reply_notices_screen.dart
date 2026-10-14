import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../thread/thread_detail_screen.dart';

/// The site's 回复提醒 list: replies to the user's threads, each removable.
class ReplyNoticesScreen extends StatefulWidget {
  const ReplyNoticesScreen({super.key, required this.repository});

  final ForumRepository repository;

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

  void _open(ForumReplyNotice notice) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThreadDetailScreen(
          thread: ForumThread(
            title: notice.title,
            url: notice.threadUrl,
            replies: 0,
            section: notice.board,
          ),
          repository: widget.repository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notices = _notices;
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: const Text('回复提醒')),
      body: error != null && notices == null
          ? AsyncErrorView(
              title: '回复提醒加载失败',
              message: forumErrorText(error),
              onRetry: _load,
            )
          : notices == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  color: AppColors.brand,
                  onRefresh: _load,
                  child: notices.isEmpty
                      ? ListView(
                          children: const [
                            EmptyStateView(
                              title: '暂无回复提醒',
                              message: '你的主题有新回复时会显示在这里。',
                              icon: Icons.mark_chat_read_outlined,
                            ),
                          ],
                        )
                      : ListView.separated(
                          itemCount: notices.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: AppColors.border),
                          itemBuilder: (context, index) {
                            final notice = notices[index];
                            final deleting = _deleting.contains(notice.tid);
                            return ListTile(
                              contentPadding:
                                  const EdgeInsets.fromLTRB(16, 6, 4, 6),
                              title: Text(
                                notice.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.text,
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${notice.board} · ${notice.date}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              trailing: deleting
                                  ? const Padding(
                                      padding: EdgeInsets.all(14),
                                      child: SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : IconButton(
                                      tooltip: '删除提醒',
                                      icon: const Icon(Icons.close),
                                      onPressed: () => _delete(notice),
                                    ),
                              onTap: () => _open(notice),
                            );
                          },
                        ),
                ),
    );
  }
}
