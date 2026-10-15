import 'package:flutter/material.dart';

import '../../models/forum_pm_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import 'pm_compose_screen.dart';
import 'pm_detail_screen.dart';

class PmBoxScreen extends StatefulWidget {
  const PmBoxScreen({super.key, required this.repository});

  final ForumRepository repository;

  @override
  State<PmBoxScreen> createState() => _PmBoxScreenState();
}

class _PmBoxScreenState extends State<PmBoxScreen> {
  ForumPmBox _box = ForumPmBox.inbox;
  String? _pagePath;
  late Future<ForumPmPage> _future = _fetch();

  Future<ForumPmPage> _fetch() =>
      widget.repository.fetchPmBox(_box, pagePath: _pagePath);

  Future<void> _refresh([ForumPmActionResult? result]) async {
    final path = result?.refreshPath;
    if (path != null) {
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
      appBar: AppBar(
        title: const Text('短消息'),
        actions: [
          IconButton(
            tooltip: '写消息',
            onPressed: _compose,
            icon: Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<ForumPmBox>(
                  segments: const [
                    ButtonSegment(
                      value: ForumPmBox.inbox,
                      icon: Icon(Icons.inbox_outlined),
                      label: Text('收件箱'),
                    ),
                    ButtonSegment(
                      value: ForumPmBox.sendbox,
                      icon: Icon(Icons.outbox_outlined),
                      label: Text('发件箱'),
                    ),
                    ButtonSegment(
                      value: ForumPmBox.scout,
                      icon: Icon(Icons.track_changes_outlined),
                      label: Text('消息跟踪'),
                    ),
                  ],
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
                  if (snapshot.hasError) {
                    return AsyncErrorView(
                      title: '短消息加载失败',
                      message: forumErrorText(snapshot.error),
                      onRetry: _refresh,
                    );
                  }
                  if (!snapshot.hasData) {
                    return const ThreadListSkeleton(itemCount: 6);
                  }
                  return RefreshIndicator(
                    color: AppColors.brand,
                    onRefresh: _refresh,
                    child: _PmList(
                      page: snapshot.data!,
                      onOpen: _openMessage,
                      onPage: _openPage,
                    ),
                  );
                },
              ),
            ),
          ],
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
    final children = <Widget>[];
    if (page.hasUnread == true) {
      children.add(const _UnreadBanner());
    }
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
        children.add(_GroupLabel(label));
        children.addAll(group.map(_tile));
      }
    } else {
      children.addAll(page.messages.map(_tile));
    }
    if (page.pageLinks.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 6),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: children,
    );
  }

  Widget _tile(ForumPmSummary message) =>
      _PmTile(message: message, onTap: () => onOpen(message));
}

class _UnreadBanner extends StatelessWidget {
  const _UnreadBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.brandSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.mark_email_unread_outlined,
              size: 18, color: AppColors.brandDark),
          const SizedBox(width: 8),
          Text(
            '有新消息',
            style: TextStyle(
              color: AppColors.brandDark,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.textMuted,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PmTile extends StatelessWidget {
  const _PmTile({required this.message, required this.onTap});

  final ForumPmSummary message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final recipientRead = message.recipientRead;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 10),
                  child: Icon(
                    Icons.circle,
                    size: 8,
                    color: message.unread
                        ? AppColors.noticeDot
                        : Colors.transparent,
                    semanticLabel: message.unread ? '未读' : null,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 15,
                          height: 1.35,
                          fontWeight: message.unread
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        [
                          message.peer,
                          message.time,
                          if (recipientRead != null)
                            recipientRead ? '对方已读' : '对方未读',
                        ].where((part) => part.isNotEmpty).join(' · '),
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
