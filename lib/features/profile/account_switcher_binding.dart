import 'package:flutter/material.dart';

import '../../services/forum_account_id.dart';
import '../../services/forum_account_registry.dart';
import '../../services/forum_repository.dart';
import '../auth/login_screen.dart';
import 'account_switcher_sheet.dart';

Iterable<AccountSummary> accountsForCurrentSite(ForumRepository repository) {
  final origin =
      ForumAccountId.normalizeOrigin(repository.networkConfig.baseUri);
  return repository.accounts.value.where(
    (account) => ForumAccountId.tryParse(account.id)?.origin == origin,
  );
}

AccountSwitcherItem accountSwitcherItemFromSummary(AccountSummary summary) {
  return AccountSwitcherItem(
    id: summary.id,
    displayName: summary.displayName,
    systemName: summary.systemName,
    uid: summary.uid,
    avatarUrl: summary.avatarUrl,
    status: summary.status == AccountReadyState.needsReauth
        ? AccountSwitcherStatus.needsReauth
        : AccountSwitcherStatus.ready,
    isActive: summary.isActive,
  );
}

void _syncSwitcherAccounts(
  AccountSwitcherViewModel viewModel,
  ForumRepository repository,
) {
  viewModel.setAccounts([
    for (final account in accountsForCurrentSite(repository))
      accountSwitcherItemFromSummary(account),
  ]);
}

Future<void> openAccountSwitcher(
  BuildContext context,
  ForumRepository repository,
) async {
  final navigator = Navigator.of(context);
  Route<dynamic>? sheetRoute;
  void closeSheet() {
    final route = sheetRoute;
    if (!navigator.mounted || route == null || !route.isActive) return;
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  final viewModel = AccountSwitcherViewModel();
  void sync() => _syncSwitcherAccounts(viewModel, repository);
  sync();
  repository.accounts.addListener(sync);
  repository.activeAccount.addListener(sync);
  repository.sessionEpoch.addListener(sync);

  try {
    final closed = showAccountSwitcherSheet(
      context,
      viewModel: viewModel,
      onSelect: (id) async {
        try {
          await repository.selectAccount(id);
          closeSheet();
        } catch (_) {
          viewModel.setError('切换失败');
        }
      },
      onAdd: () async {
        closeSheet();
        if (!context.mounted) return;
        await openAddAccount(context, repository);
      },
      onReauthenticate: (id) async {
        AccountSummary? summary;
        for (final account in repository.accounts.value) {
          if (account.id == id) {
            summary = account;
            break;
          }
        }
        closeSheet();
        if (!context.mounted) return;
        try {
          await openReauthAccount(
            context,
            repository,
            accountId: id,
            initialUsername: summary?.systemName,
          );
        } catch (_) {
          // Login route owns its errors; sheet already closed.
        }
      },
      onRemove: (id) async {
        try {
          await repository.removeAccount(id);
        } catch (_) {
          viewModel.setError('移除失败');
        }
      },
      onLogoutCurrent: () async {
        try {
          await repository.logoutCurrent();
          closeSheet();
        } catch (_) {
          viewModel.setError('退出失败');
        }
      },
    );
    // A late completion can close only this sheet's route.
    navigator.popUntil((route) {
      sheetRoute = route;
      return true;
    });
    await closed;
  } finally {
    repository.accounts.removeListener(sync);
    repository.activeAccount.removeListener(sync);
    repository.sessionEpoch.removeListener(sync);
  }
}
