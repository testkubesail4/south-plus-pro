import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../common/grouped_list.dart';
import 'account_screen.dart' show AccountAvatar;

/// Credential state shown in the account picker.
enum AccountSwitcherStatus {
  /// Cookies are believed usable; tapping selects this account.
  ready,

  /// Credentials cleared or rejected; row offers 重新登录.
  needsReauth,
}

class AccountSwitcherItem {
  const AccountSwitcherItem({
    required this.id,
    required this.displayName,
    this.systemName,
    this.uid,
    this.avatarUrl,
    this.status = AccountSwitcherStatus.ready,
    this.isActive = false,
  });

  final String id;
  final String displayName;
  final String? systemName;
  final String? uid;
  final String? avatarUrl;
  final AccountSwitcherStatus status;
  final bool isActive;
}

/// Presentation state supplied by the account switcher binding.
class AccountSwitcherViewModel extends ChangeNotifier {
  List<AccountSwitcherItem> _accounts = const [];
  bool _loading = false;
  bool _busy = false;
  String? _error;

  List<AccountSwitcherItem> get accounts => _accounts;
  bool get loading => _loading;
  bool get busy => _busy;
  String? get error => _error;
  bool get isEmpty => !_loading && _error == null && _accounts.isEmpty;

  void setAccounts(List<AccountSwitcherItem> accounts) {
    _accounts = List.unmodifiable(accounts);
    notifyListeners();
  }

  void setLoading(bool loading) {
    if (_loading == loading) return;
    _loading = loading;
    notifyListeners();
  }

  void setBusy(bool busy) {
    if (_busy == busy) return;
    _busy = busy;
    notifyListeners();
  }

  void setError(String? error) {
    if (_error == error) return;
    _error = error;
    notifyListeners();
  }
}

/// Opens the account picker.
///
/// Dismiss while an action is in flight is blocked on every path Flutter
/// actually uses for this modal:
/// - Barrier tap and the Android back button go through [Navigator.maybePop],
///   gated by [PopScope] inside the sheet (`canPop: !locked`).
/// - Drag-to-dismiss calls [Navigator.pop] (not maybePop), so PopScope cannot
///   stop it. This entry point therefore sets `enableDrag: false` and
///   `isDismissible: false`, and offers an explicit close control while idle.
Future<void> showAccountSwitcherSheet(
  BuildContext context, {
  required AccountSwitcherViewModel viewModel,
  required Future<void> Function(String id) onSelect,
  required Future<void> Function() onAdd,
  required Future<void> Function(String id) onReauthenticate,
  required Future<void> Function(String id) onRemove,
  required Future<void> Function() onLogoutCurrent,
  Future<void> Function()? onRetry,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Drag uses Navigator.pop; PopScope cannot block it. Keep drag off and
    // close via the idle header control + maybePop (back) instead.
    enableDrag: false,
    showDragHandle: false,
    isDismissible: false,
    constraints: const BoxConstraints(maxWidth: AppWidths.sheet),
    builder: (sheetContext) => AccountSwitcherSheet(
      viewModel: viewModel,
      onSelect: onSelect,
      onAdd: onAdd,
      onReauthenticate: onReauthenticate,
      onRemove: onRemove,
      onLogoutCurrent: onLogoutCurrent,
      onRetry: onRetry,
    ),
  );
}

class AccountSwitcherSheet extends StatefulWidget {
  const AccountSwitcherSheet({
    super.key,
    required this.viewModel,
    required this.onSelect,
    required this.onAdd,
    required this.onReauthenticate,
    required this.onRemove,
    required this.onLogoutCurrent,
    this.onRetry,
  });

  final AccountSwitcherViewModel viewModel;
  final Future<void> Function(String id) onSelect;
  final Future<void> Function() onAdd;
  final Future<void> Function(String id) onReauthenticate;
  final Future<void> Function(String id) onRemove;
  final Future<void> Function() onLogoutCurrent;
  final Future<void> Function()? onRetry;

  @override
  State<AccountSwitcherSheet> createState() => _AccountSwitcherSheetState();
}

class _AccountSwitcherSheetState extends State<AccountSwitcherSheet> {
  /// Synchronous latch so a second tap before the adapter sets
  /// [AccountSwitcherViewModel.busy] cannot re-enter.
  bool _inFlight = false;

  bool get _locked => _inFlight || widget.viewModel.busy;

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_onViewModel);
  }

  @override
  void didUpdateWidget(covariant AccountSwitcherSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel == widget.viewModel) return;
    oldWidget.viewModel.removeListener(_onViewModel);
    widget.viewModel.addListener(_onViewModel);
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onViewModel);
    super.dispose();
  }

  void _onViewModel() {
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_locked) return;
    setState(() => _inFlight = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _inFlight = false);
      } else {
        _inFlight = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _locked;
    return PopScope(
      canPop: !locked,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                0,
                AppSpace.sm,
                AppSpace.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        '账号',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  if (!locked)
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            ),
            if (locked) const LinearProgressIndicator(minHeight: 2),
            Builder(
              builder: (context) {
                final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: 160,
                    maxHeight: maxHeight < 160 ? 160 : maxHeight,
                  ),
                  child: _body(context, locked: locked),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, {required bool locked}) {
    final viewModel = widget.viewModel;
    if (viewModel.loading && viewModel.accounts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppSpace.xxl),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      );
    }

    if (viewModel.error != null && viewModel.accounts.isEmpty) {
      final onRetry = widget.onRetry;
      if (onRetry == null) {
        return EmptyStateView(
          icon: Icons.cloud_off_outlined,
          iconColor: AppColors.textMuted,
          title: '账号列表加载失败',
          message: viewModel.error,
        );
      }
      return AsyncErrorView(
        title: '账号列表加载失败',
        message: viewModel.error,
        onRetry: onRetry,
      );
    }

    if (viewModel.isEmpty) {
      return EmptyStateView(
        icon: Icons.person_outline,
        action: FilledButton.icon(
          onPressed: locked ? null : () => _run(widget.onAdd),
          icon: const Icon(Icons.person_add_outlined),
          label: const Text('添加账号'),
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.lg,
        AppSpace.lg,
      ),
      children: [
        if (viewModel.error != null) ...[
          Text(
            viewModel.error!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        AppGroup(
          dividerIndent: 72,
          children: [
            for (final account in viewModel.accounts)
              _AccountSwitcherRow(
                account: account,
                enabled: !locked,
                onSelect: () => _run(() => widget.onSelect(account.id)),
                onReauthenticate: () =>
                    _run(() => widget.onReauthenticate(account.id)),
                onRemove: () => _confirmRemove(account),
                onLogoutCurrent: account.isActive ? _confirmLogout : null,
              ),
          ],
        ),
        const SizedBox(height: AppSpace.xl),
        AppGroup(
          children: [
            AppRow(
              icon: Icons.person_add_outlined,
              title: const Text('添加账号'),
              onTap: locked ? null : () => _run(widget.onAdd),
              enabled: !locked,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmLogout() async {
    if (_locked) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出当前账号？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('退出当前账号'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(widget.onLogoutCurrent);
    }
  }

  Future<void> _confirmRemove(AccountSwitcherItem account) async {
    if (_locked) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('移除账号？'),
        content: Text(account.displayName),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('移除账号'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(() => widget.onRemove(account.id));
    }
  }
}

class _AccountSwitcherRow extends StatelessWidget {
  const _AccountSwitcherRow({
    required this.account,
    required this.enabled,
    required this.onSelect,
    required this.onReauthenticate,
    required this.onRemove,
    required this.onLogoutCurrent,
  });

  final AccountSwitcherItem account;
  final bool enabled;
  final VoidCallback onSelect;
  final VoidCallback onReauthenticate;
  final VoidCallback onRemove;
  final VoidCallback? onLogoutCurrent;

  @override
  Widget build(BuildContext context) {
    final needsReauth = account.status == AccountSwitcherStatus.needsReauth;
    final subtitle = _subtitle();
    final tap = !enabled
        ? null
        : needsReauth
            ? onReauthenticate
            : account.isActive
                ? null
                : onSelect;

    return Semantics(
      button: tap != null,
      selected: account.isActive,
      label: _semanticsLabel(needsReauth: needsReauth),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: tap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.lg,
                vertical: AppSpace.md,
              ),
              child: Row(
                children: [
                  AccountAvatar(avatarUrl: account.avatarUrl, size: 40),
                  const SizedBox(width: AppSpace.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          account.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: enabled
                                        ? AppColors.text
                                        : AppColors.textFaint,
                                  ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: needsReauth
                                          ? Theme.of(context).colorScheme.error
                                          : enabled
                                              ? AppColors.textMuted
                                              : AppColors.textFaint,
                                    ),
                          ),
                        ],
                        if (needsReauth)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: enabled ? onReauthenticate : null,
                              child: const Text('重新登录'),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (account.isActive && !needsReauth)
                    Icon(Icons.check, color: AppColors.brand),
                  PopupMenuButton<_AccountMenuAction>(
                    enabled: enabled,
                    tooltip: '账号操作',
                    onSelected: (action) {
                      switch (action) {
                        case _AccountMenuAction.logoutCurrent:
                          onLogoutCurrent?.call();
                        case _AccountMenuAction.remove:
                          onRemove();
                      }
                    },
                    itemBuilder: (context) => [
                      if (onLogoutCurrent != null)
                        const PopupMenuItem(
                          value: _AccountMenuAction.logoutCurrent,
                          child: Text('退出当前账号'),
                        ),
                      const PopupMenuItem(
                        value: _AccountMenuAction.remove,
                        child: Text('移除账号'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _subtitle() {
    if (account.status == AccountSwitcherStatus.needsReauth) {
      return '需重新登录';
    }
    final system = account.systemName?.trim();
    if (system != null && system.isNotEmpty && system != account.displayName) {
      return system;
    }
    final uid = account.uid?.trim();
    if (uid != null && uid.isNotEmpty) return 'UID $uid';
    return null;
  }

  String _semanticsLabel({required bool needsReauth}) {
    final buffer = StringBuffer(account.displayName);
    if (account.isActive) buffer.write('，当前');
    if (needsReauth) buffer.write('，需重新登录');
    return buffer.toString();
  }
}

enum _AccountMenuAction { logoutCurrent, remove }
