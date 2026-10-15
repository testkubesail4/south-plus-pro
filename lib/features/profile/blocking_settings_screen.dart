part of 'account_screen.dart';

/// 屏蔽配置: the site's own block list (synced with 南+) and this device's
/// extra rules, each edited where it is stored.
class BlockingSettingsScreen extends StatefulWidget {
  const BlockingSettingsScreen({super.key, required this.repository});

  final ForumRepository repository;

  @override
  State<BlockingSettingsScreen> createState() => _BlockingSettingsScreenState();
}

class _BlockingSettingsScreenState extends State<BlockingSettingsScreen> {
  ForumBlockingSettings get _blocking => widget.repository.blocking;

  /// Opening the page always reads the site's list afresh.
  late Future<void> _sync = _open();

  /// Rows waiting for a write, so they show progress and take no taps.
  final _busy = <String>{};

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

  /// Sign-in, sign-out and account switches show the new account's rules.
  void _onSessionChanged() {
    _busy.clear();
    _refresh();
  }

  Future<void> _open() async {
    if (!widget.repository.isLoggedIn) return;
    // A fresh session may not know whose list to read yet.
    await widget.repository.ensureAccountIdentity();
    await _blocking.load(refresh: true);
  }

  void _refresh() => setState(() {
        _sync = _open();
      });

  /// Runs [write] for [row], built while [epoch] was the session; a menu
  /// left open across an account switch must not edit the new account.
  Future<void> _edit(
      String row, int epoch, Future<void> Function() write) async {
    if (epoch != widget.repository.sessionEpoch.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('账号已变化，请重新选择')),
      );
      return;
    }
    setState(() => _busy.add(row));
    try {
      await write();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_blockingError(error))),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(row));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = widget.repository.isLoggedIn;
    return Scaffold(
      appBar: AppBar(
        title: const Text('屏蔽配置'),
        actions: [
          if (loggedIn)
            IconButton(
              tooltip: '从南+重新同步',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: !loggedIn
            ? EmptyStateView(
                icon: Icons.block_outlined,
                title: '登录后可配置屏蔽规则',
                message: '屏蔽名单跟随南+账号，本机规则也按账号分开保存',
                action: FilledButton(
                  onPressed: () => openLogin(context, widget.repository),
                  child: const Text('登录'),
                ),
              )
            : FutureBuilder<void>(
                future: _sync,
                builder: (context, snapshot) {
                  if (_blocking.canWriteNative) return _rules();
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return EmptyStateView(
                    icon: Icons.block_outlined,
                    title: '暂时无法识别当前账号',
                    message: snapshot.hasError
                        ? _blockingError(snapshot.error)
                        : '识别账号后才能读取屏蔽名单',
                    action: OutlinedButton(
                      onPressed: _refresh,
                      child: const Text('重试'),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _rules() => ValueListenableBuilder<BlockingRules>(
        valueListenable: _blocking.notifier,
        builder: (context, rules, _) => ListView(
          // A centred column at most 720 wide.
          padding: EdgeInsets.symmetric(
            horizontal:
                math.max(16, (MediaQuery.sizeOf(context).width - 720) / 2),
            vertical: 14,
          ).copyWith(bottom: 28),
          children: [
            _siteSection(rules),
            const SizedBox(height: 14),
            _localSection(rules),
          ],
        ),
      );

  Widget _siteSection(BlockingRules rules) {
    return _AccountSection(
      title: '南+ 屏蔽名单',
      subtitle: '与网页版同步。隐藏主题和回复：不显示 TA 的主题与所有楼层；替换头像：只换掉头像',
      children: [
        FutureBuilder<void>(
          future: _sync,
          builder: (context, snapshot) {
            final Widget status;
            if (snapshot.connectionState != ConnectionState.done) {
              status = const LinearProgressIndicator(minHeight: 2);
            } else if (snapshot.hasError) {
              status = Row(
                children: [
                  Expanded(
                    child: Text(
                      _blockingError(snapshot.error),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  TextButton(onPressed: _refresh, child: const Text('重试')),
                ],
              );
            } else {
              final synced = _blocking.nativeSyncedAt;
              status = Text(
                synced == null ? '' : '已同步 · ${_clock(synced)}',
                style: TextStyle(color: AppColors.textFaint, fontSize: 12),
              );
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: status,
            );
          },
        ),
        if (rules.users.isEmpty)
          _emptyRow('没有屏蔽任何人。在楼层的「⋯」里可以屏蔽此人或屏蔽头像。')
        else
          for (final user in rules.users) _siteUserRow(user),
      ],
    );
  }

  Widget _siteUserRow(BlockedUser user) {
    final row = 'site:${user.uid}';
    final epoch = widget.repository.sessionEpoch.value;
    void toggle(bool avatar) => _edit(
          row,
          epoch,
          () => _blocking.setUser(
            user.uid,
            user.name,
            blocked: !(avatar ? user.avatarBlocked : user.userBlocked),
            avatarOnly: avatar,
          ),
        );
    return _BaseAccountTile(
      active: true,
      icon: user.userBlocked
          ? Icons.person_off_outlined
          : Icons.hide_image_outlined,
      title: Text(user.name),
      subtitle: Text([
        if (user.userBlocked) '隐藏主题和回复',
        if (user.avatarBlocked) '替换头像',
      ].join(' · ')),
      trailing: _rowMenu(
        busy: _busy.contains(row),
        items: [
          CheckedPopupMenuItem(
            value: 0,
            checked: user.userBlocked,
            child: const Text('隐藏主题和回复'),
          ),
          CheckedPopupMenuItem(
            value: 1,
            checked: user.avatarBlocked,
            child: const Text('替换头像'),
          ),
        ],
        onSelected: (value) => toggle(value == 1),
      ),
    );
  }

  Widget _localSection(BlockingRules rules) {
    return _AccountSection(
      title: '本机规则',
      subtitle: '只保存在这台设备，按账号分开，不会同步到南+。'
          '屏蔽的回复内容只折叠与它完全相同的简短回复',
      children: [
        for (final user in rules.localUsers) _localUserRow(user),
        for (final key in rules.contentKeys) _contentRow(key),
        if (rules.localUsers.isEmpty && rules.contentKeys.isEmpty)
          _emptyRow('没有本机规则。在楼层的「⋯」里可以屏蔽内容：'
              '与它完全相同的简短回复都会被折叠。'),
      ],
    );
  }

  Widget _localUserRow(LocalBlockedUser user) {
    final row = 'local:${user.uid}';
    final epoch = widget.repository.sessionEpoch.value;
    String label(LocalBlockScope scope) => switch (scope) {
          LocalBlockScope.topics => '只屏蔽主题帖',
          LocalBlockScope.all => '屏蔽所有内容',
        };
    return _BaseAccountTile(
      active: true,
      icon: Icons.person_off_outlined,
      title: Text(user.name),
      subtitle: Text(label(user.scope)),
      trailing: _rowMenu(
        busy: _busy.contains(row),
        items: [
          for (final scope in LocalBlockScope.values)
            CheckedPopupMenuItem(
              value: scope.index,
              checked: user.scope == scope,
              child: Text(label(scope)),
            ),
          const PopupMenuDivider(),
          const PopupMenuItem(value: -1, child: Text('取消屏蔽')),
        ],
        onSelected: (value) => _edit(
          row,
          epoch,
          () => _blocking.setLocalUser(user.uid, user.name,
              scope: value < 0 ? null : LocalBlockScope.values[value]),
        ),
      ),
    );
  }

  Widget _contentRow(String key) {
    final row = 'content:$key';
    final epoch = widget.repository.sessionEpoch.value;
    return _BaseAccountTile(
      active: true,
      icon: Icons.chat_bubble_outline,
      title: Text(_readableContent(key)),
      subtitle: const Text('回复内容'),
      trailing: _busy.contains(row)
          ? const _RowProgress()
          : IconButton(
              tooltip: '取消屏蔽',
              onPressed: () => _edit(
                  row, epoch, () => _blocking.setContent(key, blocked: false)),
              icon: Icon(Icons.close, color: AppColors.textFaint),
            ),
    );
  }

  Widget _rowMenu({
    required bool busy,
    required List<PopupMenuEntry<int>> items,
    required ValueChanged<int> onSelected,
  }) {
    if (busy) return const _RowProgress();
    return PopupMenuButton<int>(
      tooltip: '更改',
      icon: Icon(Icons.more_horiz, color: AppColors.textMuted),
      itemBuilder: (_) => items,
      onSelected: onSelected,
    );
  }

  Widget _emptyRow(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
        child: Text(
          text,
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      );
}

class _RowProgress extends StatelessWidget {
  const _RowProgress();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
        dimension: 48,
        child: Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
}

String _clock(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}';
}

/// Stored content keeps the matcher's tokens; show them as words.
String _readableContent(String key) => key
    .replaceAll(RegExp(r'<EMOJI(:\d+)?>'), '〔表情〕')
    .replaceAll('<EXT_IMG>', '〔图片〕')
    .replaceAll('<IGNORABLE>', '〔折叠内容〕')
    .replaceAll('<EMPTY>', '〔空白〕');

/// The engine's own messages say what failed and that nothing was changed.
String _blockingError(Object? error) =>
    error is ForumRequestException ? error.message : forumErrorText(error);
