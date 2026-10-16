import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../models/forum_pm_models.dart';
import '../../services/forum_repository.dart';
import '../../services/forum_request_exception.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../common/forum_link_opener.dart';
import '../thread/thread_rich_content.dart';
import 'pm_compose_screen.dart';

/// Returns the server result so the box can follow its refresh destination.
class PmDetailScreen extends StatefulWidget {
  const PmDetailScreen({
    super.key,
    required this.repository,
    required this.message,
  });

  final ForumRepository repository;
  final ForumPmSummary message;

  @override
  State<PmDetailScreen> createState() => _PmDetailScreenState();
}

class _PmDetailScreenState extends State<PmDetailScreen> {
  late Future<ForumPmDetail> _future = _fetch();
  bool _busy = false;

  Future<ForumPmDetail> _fetch() =>
      widget.repository.fetchPmDetail(widget.message);

  void _retry() => setState(() {
    _future = _fetch();
  });

  Future<void> _openCompose(String path) async {
    final result = await Navigator.of(context).push<ForumPmActionResult>(
      MaterialPageRoute(
        builder: (_) =>
            PmComposeScreen(repository: widget.repository, path: path),
      ),
    );
    if (mounted && result != null) Navigator.of(context).pop(result);
  }

  Future<void> _openChatlog(String path) async {
    final result = await Navigator.of(context).push<ForumPmActionResult>(
      MaterialPageRoute(
        builder: (_) =>
            PmChatlogScreen(repository: widget.repository, path: path),
      ),
    );
    if (mounted && result != null) Navigator.of(context).pop(result);
  }

  Future<void> _confirmAndRun({
    required String title,
    required String message,
    required String confirmLabel,
    required Future<ForumPmActionResult> Function() action,
  }) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await action();
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
      if (mounted) Navigator.of(context).pop(result);
    } on ForumRequestException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(forumErrorText(error))));
    } on ForumRepositoryException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Everything but 回复, for the app bar's ⋯ menu (AUDIT M5).
  List<PopupMenuEntry<VoidCallback>> _moreActions(ForumPmDetail detail) {
    final editPath = detail.editPath ?? detail.summary.editPath;
    final canDelete = detail.deletePath != null || detail.summary.canDelete;
    PopupMenuItem<VoidCallback> item(
      IconData icon,
      String label,
      VoidCallback onTap, {
      Color? color,
    }) => PopupMenuItem(
      value: onTap,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpace.md),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );
    return [
      if (detail.forwardPath case final path?)
        item(Icons.forward_outlined, '转发', () => _openCompose(path)),
      if (editPath != null)
        item(Icons.edit_outlined, '编辑', () => _openCompose(editPath)),
      if (detail.chatlogPath case final path?)
        item(Icons.forum_outlined, '通信记录', () => _openChatlog(path)),
      if (detail.markUnreadPath != null)
        item(
          Icons.mark_email_unread_outlined,
          '标为未读',
          () => _confirmAndRun(
            title: '标为未读',
            message: '确定将这条消息标为未读？',
            confirmLabel: '标为未读',
            action: () => widget.repository.markPmUnread(detail),
          ),
        ),
      if (canDelete)
        item(
          Icons.delete_outline,
          '删除',
          () => _confirmAndRun(
            title: '删除消息',
            message: '删除后无法恢复，确定删除这条消息？',
            confirmLabel: '删除',
            action: () =>
                widget.repository.deletePm(detail.summary, detail: detail),
          ),
          color: Theme.of(context).colorScheme.error,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ForumPmDetail>(
      future: _future,
      builder: (context, snapshot) {
        final detail = snapshot.hasError ? null : snapshot.data;
        final more = detail == null
            ? const <PopupMenuEntry<VoidCallback>>[]
            : _moreActions(detail);
        return Scaffold(
          appBar: AppBar(
            title: const Text('短消息'),
            actions: [
              if (more.isNotEmpty)
                PopupMenuButton<VoidCallback>(
                  tooltip: '更多',
                  enabled: !_busy,
                  icon: const Icon(Icons.more_horiz),
                  itemBuilder: (_) => more,
                  onSelected: (action) => action(),
                ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: snapshot.hasError
                ? AsyncErrorView(
                    title: '短消息加载失败',
                    message: forumErrorText(snapshot.error),
                    onRetry: _retry,
                  )
                : detail == null
                ? const ThreadDetailSkeleton()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    children: [
                      _PmMessageCard(
                        repository: widget.repository,
                        sender: detail.sender,
                        title: detail.title,
                        time: detail.time,
                        content: detail.content,
                        segments: detail.segments,
                      ),
                      if (detail.replyPath case final path?) ...[
                        const SizedBox(height: AppSpace.md),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : () => _openCompose(path),
                            icon: const Icon(Icons.reply_outlined),
                            label: const Text('回复'),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class PmChatlogScreen extends StatefulWidget {
  const PmChatlogScreen({
    super.key,
    required this.repository,
    required this.path,
  });

  final ForumRepository repository;
  final String path;

  @override
  State<PmChatlogScreen> createState() => _PmChatlogScreenState();
}

class _PmChatlogScreenState extends State<PmChatlogScreen> {
  late String _path = widget.path;
  late Future<ForumPmChatlog> _future = _fetch();

  Future<ForumPmChatlog> _fetch() => widget.repository.fetchPmChatlog(_path);

  void _load([String? path]) {
    setState(() {
      if (path != null) _path = path;
      _future = _fetch();
    });
  }

  Future<void> _compose(String path) async {
    final result = await Navigator.of(context).push<ForumPmActionResult>(
      MaterialPageRoute(
        builder: (_) =>
            PmComposeScreen(repository: widget.repository, path: path),
      ),
    );
    if (mounted && result != null) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通信记录')),
      body: SafeArea(
        top: false,
        child: FutureBuilder<ForumPmChatlog>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return AsyncErrorView(
                title: '通信记录加载失败',
                message: forumErrorText(snapshot.error),
                onRetry: _load,
              );
            }
            if (!snapshot.hasData) return const ThreadDetailSkeleton();
            final chatlog = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                if (chatlog.records.isEmpty)
                  const EmptyStateView(
                    icon: Icons.forum_outlined,
                    title: '暂无通信记录',
                  ),
                for (final record in chatlog.records) ...[
                  _PmMessageCard(
                    repository: widget.repository,
                    sender: record.sender,
                    title: record.title,
                    time: record.time,
                    content: record.content,
                    segments: record.segments,
                  ),
                  const SizedBox(height: 10),
                ],
                if (chatlog.pageLinks.isNotEmpty || chatlog.composePath != null)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final link in chatlog.pageLinks)
                        OutlinedButton(
                          onPressed: () => _load(link.path),
                          child: Text(link.label),
                        ),
                      if (chatlog.composePath case final path?)
                        FilledButton.icon(
                          onPressed: () => _compose(path),
                          icon: Icon(Icons.reply_outlined, size: 18),
                          label: const Text('回复'),
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PmMessageCard extends StatelessWidget {
  const _PmMessageCard({
    required this.repository,
    required this.sender,
    required this.title,
    required this.time,
    required this.content,
    required this.segments,
  });

  final ForumRepository repository;
  final String sender;
  final String title;
  final String time;
  final String content;
  final List<ThreadContentSegment> segments;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            title,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 17,
              height: 1.35,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            [sender, time].where((part) => part.isNotEmpty).join(' · '),
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          Divider(height: 24, color: AppColors.border),
          if (segments.isEmpty)
            SelectableText(
              content,
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            SelectionArea(
              // Private media: memory-only images, no link-preview service,
              // no purchase actions.
              child: ThreadRichContent(
                segments: segments,
                privateMedia: true,
                onOpenLink: (url, _) =>
                    // Private captions must not become a thread title that
                    // browsing history could keep.
                    openForumLink(context, repository, url),
              ),
            ),
        ],
      ),
    );
  }
}
