import 'package:flutter/material.dart';

import '../../models/forum_friend_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../common/app_switcher.dart';
import '../common/async_state_view.dart';
import '../common/cached_forum_image.dart';
import '../common/content_width.dart';
import '../common/forum_pager.dart';
import '../common/grouped_list.dart';
import 'forum_preferences_screen.dart';
import 'user_profile_screen.dart';

/// The signed-in user's 好友 and 待验证 lists, as the forum's 好友 tab.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({
    super.key,
    required this.repository,
    this.initialPending = false,
    this.initialPage = 1,
  });

  final ForumRepository repository;
  final bool initialPending;

  /// The page of the initial list (a forum link can name one).
  final int initialPage;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  late bool _pending = widget.initialPending;
  late final _pages = {
    false: widget.initialPending ? 1 : widget.initialPage,
    true: widget.initialPending ? widget.initialPage : 1,
  };
  late final _futures = {
    false: _fetch(false),
    true: _fetch(true),
  };
  // Rows with a request in flight; their actions stay disabled.
  final Set<String> _busy = {};
  // The session changed: the lists may be another account's, so they stay
  // hidden until the user reloads in the settled session.
  bool _sessionChanged = false;

  @override
  void initState() {
    super.initState();
    widget.repository.sessionEpoch.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    widget.repository.sessionEpoch.removeListener(_onSessionChanged);
    super.dispose();
  }

  Future<ForumFriendPage> _fetch(bool pending) =>
      widget.repository.fetchFriends(pending: pending, page: _pages[pending]!);

  // No automatic reload: the session may still be switching cookies.
  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {
      _sessionChanged = true;
      _busy.clear();
      _pages.updateAll((_, __) => 1);
    });
  }

  bool _current(int epoch) =>
      mounted && epoch == widget.repository.sessionEpoch.value;

  /// Reloads both lists: a reply to a request can change the friend list.
  Future<void> _reloadAll() async {
    setState(() {
      _sessionChanged = false;
      _futures.updateAll((pending, _) => _fetch(pending));
    });
    try {
      await _futures[_pending];
    } catch (_) {
      // The FutureBuilder shows the failure.
    }
  }

  void _openPage(int page) {
    setState(() {
      _pages[_pending] = page;
      _futures[_pending] = _fetch(_pending);
    });
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  /// Runs [run] unless the session moved on since [epoch], when the user
  /// started the action (a dialog may have stayed open across a switch).
  Future<void> _mutate(
    int epoch,
    ForumFriend friend,
    Future<ForumFriendMutationResult> Function() run,
    String done,
  ) async {
    if (!_current(epoch) || _sessionChanged) return;
    setState(() => _busy.add(friend.uid));
    try {
      final result = await run();
      if (!_current(epoch)) return;
      _toast(result.confirmed
          ? done
          : result.message.isEmpty
              ? '论坛没有确认这次操作'
              : result.message);
    } catch (error) {
      if (!_current(epoch)) return;
      _toast('操作失败：${forumErrorText(error)}');
    }
    if (!_current(epoch)) return;
    _busy.remove(friend.uid);
    await _reloadAll();
  }

  Future<void> _delete(ForumFriendPage page, ForumFriend friend) async {
    final epoch = widget.repository.sessionEpoch.value;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除好友'),
        content: Text('将 ${friend.name} 移出你的好友列表。你在对方列表中的状态不变。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _mutate(
      epoch,
      friend,
      () => widget.repository.deleteFriends(page, [friend]),
      '已删除好友',
    );
  }

  Future<void> _respond(
    ForumFriendPage page,
    ForumFriend friend,
    ForumFriendResponse response,
  ) async {
    final epoch = widget.repository.sessionEpoch.value;
    var refusal = '';
    if (response == ForumFriendResponse.refuse) {
      final text = await _askRefusal(friend);
      if (text == null) return;
      refusal = text;
    }
    await _mutate(
      epoch,
      friend,
      () => widget.repository.respondToFriendRequests(
        page,
        [friend],
        response,
        refusalMessage: refusal,
      ),
      switch (response) {
        ForumFriendResponse.acceptadd => '已互加好友',
        ForumFriendResponse.accept => '已接受请求',
        ForumFriendResponse.refuse => '已拒绝请求',
      },
    );
  }

  Future<String?> _askRefusal(ForumFriend friend) => showDialog<String>(
        context: context,
        builder: (context) => _RefusalDialog(name: friend.name),
      );

  void _openProfile(ForumFriend friend) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UserProfileScreen(
            userUrl: friend.url,
            repository: widget.repository,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('好友'),
        actions: [
          IconButton(
            tooltip: '加好友验证设置',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  ForumPreferencesScreen(repository: widget.repository),
            )),
            icon: const Icon(Icons.tune_outlined),
          ),
        ],
      ),
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
                  child: FutureBuilder<ForumFriendPage>(
                    future: _futures[true],
                    builder: (context, snapshot) {
                      // Only a settled answer from this session counts.
                      final waiting = _sessionChanged ||
                              snapshot.connectionState != ConnectionState.done
                          ? null
                          : snapshot.data;
                      final count = waiting == null || waiting.items.isEmpty
                          ? ''
                          : waiting.pageCount > 1
                              ? ' ${waiting.items.length}+'
                              : ' ${waiting.items.length}';
                      return SegmentedButton<bool>(
                        segments: [
                          const ButtonSegment(value: false, label: Text('好友')),
                          ButtonSegment(value: true, label: Text('待验证$count')),
                        ],
                        showSelectedIcon: false,
                        selected: {_pending},
                        onSelectionChanged: (values) =>
                            setState(() => _pending = values.single),
                      );
                    },
                  ),
                ),
              ),
              Divider(height: 1, color: AppColors.border),
              Expanded(
                  child: AppSwitcher(
                direction: _pending ? 1 : -1,
                scope: widget.repository.sessionEpoch.value,
                child: FutureBuilder<ForumFriendPage>(
                  key: ValueKey(_pending),
                  future: _futures[_pending],
                  // A session change hides the old account's rows at once.
                  builder: (context, snapshot) => _sessionChanged
                      ? AsyncErrorView(
                          title: '登录状态已变化',
                          message: '之前加载的好友已隐藏，重试将按当前账号重新加载。',
                          onRetry: _reloadAll,
                        )
                      : AppSwitcher(
                          scope: widget.repository.sessionEpoch.value,
                          id: snapshot.connectionState != ConnectionState.done
                              ? 'loading'
                              : snapshot.hasError
                                  ? 'error'
                                  : 'list',
                          child: Builder(builder: (context) {
                            // A replaced request never shows the previous answer.
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const ThreadListSkeleton(itemCount: 6);
                            }
                            if (snapshot.hasError) {
                              return AsyncErrorView(
                                title: _pending ? '待验证列表加载失败' : '好友列表加载失败',
                                message: forumErrorText(snapshot.error),
                                onRetry: _reloadAll,
                              );
                            }
                            final page = snapshot.data!;
                            return RefreshIndicator(
                              color: AppColors.brand,
                              onRefresh: _reloadAll,
                              child: ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(
                                    top: AppSpace.md, bottom: AppSpace.xxl),
                                children: [
                                  if (page.items.isEmpty)
                                    EmptyStateView(
                                      icon: _pending
                                          ? Icons.how_to_reg_outlined
                                          : Icons.people_outline,
                                      title: _pending ? '没有待验证的请求' : '还没有好友',
                                      message:
                                          _pending ? null : '在其他用户的资料页点「加为好友」',
                                    )
                                  else if (_pending)
                                    AppGroup(
                                      description: '仅接受：对方的好友列表加上你，你的列表不加对方。',
                                      dividerIndent: AppSpace.lg,
                                      children: [
                                        for (final friend in page.items)
                                          _RequestRow(
                                            friend: friend,
                                            busy: _busy.contains(friend.uid),
                                            onOpen: () => _openProfile(friend),
                                            onRespond: (response) => _respond(
                                                page, friend, response),
                                          ),
                                      ],
                                    )
                                  else
                                    AppGroup(
                                      dividerIndent: 72,
                                      children: [
                                        for (final friend in page.items)
                                          _FriendRow(
                                            friend: friend,
                                            busy: _busy.contains(friend.uid),
                                            onOpen: () => _openProfile(friend),
                                            onDelete: () =>
                                                _delete(page, friend),
                                          ),
                                      ],
                                    ),
                                  if (page.pageCount > 1)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          top: AppSpace.md),
                                      child: ForumPager(
                                        current: page.page,
                                        total: page.pageCount,
                                        onSelected: _openPage,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          })),
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }
}

class _FriendAvatar extends StatelessWidget {
  const _FriendAvatar({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const size = 40.0;
    Widget icon(BuildContext context) =>
        Icon(Icons.person_outline, color: AppColors.textMuted, size: 22);
    final avatar = url;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppColors.inkSoft,
      child: avatar == null
          ? icon(context)
          : ClipOval(
              child: CachedForumImage(
                url: avatar,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorWidget: icon,
              ),
            ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.friend,
    required this.busy,
    required this.onOpen,
    required this.onDelete,
  });

  final ForumFriend friend;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final joined = friend.joinedAt;
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.lg, AppSpace.md, AppSpace.xs, AppSpace.md),
        child: Row(
          children: [
            _FriendAvatar(url: friend.avatarUrl),
            const SizedBox(width: AppSpace.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(friend.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall),
                  if (joined != null && joined.isNotEmpty)
                    Text('加入于 $joined', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            busy
                ? const Padding(
                    padding: EdgeInsets.all(AppSpace.md),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: '删除好友 ${friend.name}',
                    onPressed: onDelete,
                    icon: Icon(Icons.person_remove_outlined,
                        color: AppColors.textMuted),
                  ),
          ],
        ),
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.friend,
    required this.busy,
    required this.onOpen,
    required this.onRespond,
  });

  final ForumFriend friend;
  final bool busy;
  final VoidCallback onOpen;
  final ValueChanged<ForumFriendResponse> onRespond;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = friend.verificationMessage?.trim() ?? '';
    final joined = friend.joinedAt;
    void Function()? respond(ForumFriendResponse r) =>
        busy ? null : () => onRespond(r);
    return Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Row(
              children: [
                _FriendAvatar(url: friend.avatarUrl),
                const SizedBox(width: AppSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(friend.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall),
                      if (joined != null && joined.isNotEmpty)
                        Text(joined, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.md, vertical: AppSpace.sm),
              decoration: BoxDecoration(
                color: AppColors.inkSoft,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(
                message,
                semanticsLabel: '验证信息：$message',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                onPressed: respond(ForumFriendResponse.acceptadd),
                child: const Text('接受并加好友'),
              ),
              OutlinedButton(
                onPressed: respond(ForumFriendResponse.accept),
                child: const Text('仅接受'),
              ),
              TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error),
                onPressed: respond(ForumFriendResponse.refuse),
                child: const Text('拒绝'),
              ),
              if (busy)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks for an optional refusal note; null when cancelled.
class _RefusalDialog extends StatefulWidget {
  const _RefusalDialog({required this.name});

  final String name;

  @override
  State<_RefusalDialog> createState() => _RefusalDialogState();
}

class _RefusalDialogState extends State<_RefusalDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Keeps 拒绝 reachable above the keyboard at large text.
      scrollable: true,
      title: Text('拒绝 ${widget.name}'),
      content: TextField(
        controller: _text,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: '拒绝理由（可选）',
          hintText: '对方会在通知中看到',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.of(context).pop(_text.text.trim()),
          child: const Text('拒绝'),
        ),
      ],
    );
  }
}

/// Asks for the optional note a user who verifies requests reads; null when
/// the sheet is dismissed.
Future<String?> showFriendRequestSheet(
  BuildContext context, {
  required String name,
  String? prompt,
  int? maxLength,
}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          _FriendRequestSheet(name: name, prompt: prompt, maxLength: maxLength),
    );

class _FriendRequestSheet extends StatefulWidget {
  const _FriendRequestSheet({required this.name, this.prompt, this.maxLength});

  final String name;
  final String? prompt;
  final int? maxLength;

  @override
  State<_FriendRequestSheet> createState() => _FriendRequestSheetState();
}

class _FriendRequestSheetState extends State<_FriendRequestSheet> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prompt = widget.prompt?.trim() ?? '';
    // Scrolls so 发送请求 stays reachable above the keyboard at large text.
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl,
          AppSpace.xl + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('向 ${widget.name} 发送好友请求', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpace.xs),
          Text(prompt.isEmpty ? '对方开启了好友验证，通过后才会成为好友。' : prompt,
              style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpace.lg),
          TextField(
            controller: _text,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            maxLength: widget.maxLength,
            decoration: const InputDecoration(labelText: '验证信息（可选）'),
          ),
          const SizedBox(height: AppSpace.lg),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_text.text.trim()),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('发送请求'),
          ),
        ],
      ),
    );
  }
}
