import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/common/grouped_list.dart';
import 'package:south_plus_rewrite/features/profile/account_switcher_sheet.dart';

// test-audit authoring gate:
// 1) Observable contracts: selected mark, needs-reauth CTA, empty/error chrome,
//    in-flight single-flight, dismiss locked while busy, no dead retry.
// 2) Credible regressions: double-tap reentry before adapter busy, dismiss via
//    back/barrier/drag while locked, noop retry button, active select, cancel.
// 3) Owns this sheet only; account_page_ui_test still owns 我的.
// 4) No production seam: UI view-model + callbacks / showAccountSwitcherSheet.

AccountSwitcherViewModel _vm(List<AccountSwitcherItem> accounts) {
  final vm = AccountSwitcherViewModel()..setAccounts(accounts);
  return vm;
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required AccountSwitcherViewModel viewModel,
  Future<void> Function(String id)? onSelect,
  Future<void> Function()? onAdd,
  Future<void> Function(String id)? onReauthenticate,
  Future<void> Function(String id)? onRemove,
  Future<void> Function()? onLogoutCurrent,
  Future<void> Function()? onRetry,
  double textScale = 1,
  Size size = const Size(400, 1200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: AccountSwitcherSheet(
          viewModel: viewModel,
          onSelect: onSelect ?? ((_) async {}),
          onAdd: onAdd ?? (() async {}),
          onReauthenticate: onReauthenticate ?? ((_) async {}),
          onRemove: onRemove ?? ((_) async {}),
          onLogoutCurrent: onLogoutCurrent ?? (() async {}),
          onRetry: onRetry,
        ),
      ),
    ),
  ));
  await tester.pump();
}

Future<void> _pumpModal(
  WidgetTester tester, {
  required AccountSwitcherViewModel viewModel,
  Future<void> Function(String id)? onSelect,
  Future<void> Function()? onAdd,
}) async {
  tester.view.physicalSize = const Size(400, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => showAccountSwitcherSheet(
              context,
              viewModel: viewModel,
              onSelect: onSelect ?? ((_) async {}),
              onAdd: onAdd ?? (() async {}),
              onReauthenticate: (_) async {},
              onRemove: (_) async {},
              onLogoutCurrent: () async {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('marks the active account and lists add', (tester) async {
    await _pumpSheet(
      tester,
      viewModel: _vm(const [
        AccountSwitcherItem(
          id: 'a',
          displayName: 'Alice',
          uid: '1',
          isActive: true,
        ),
        AccountSwitcherItem(
          id: 'b',
          displayName: 'Bob',
          uid: '2',
        ),
      ]),
    );
    expect(find.text('账号'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('添加账号'), findsOneWidget);
  });

  testWidgets('needs-reauth shows 重新登录 and invokes reauth', (tester) async {
    String? reauthId;
    await _pumpSheet(
      tester,
      viewModel: _vm(const [
        AccountSwitcherItem(
          id: 'a',
          displayName: 'Alice',
          isActive: true,
          status: AccountSwitcherStatus.needsReauth,
        ),
      ]),
      onReauthenticate: (id) async {
        reauthId = id;
      },
    );
    expect(find.text('需重新登录'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
    await tester.tap(find.text('重新登录'));
    await tester.pump();
    expect(reauthId, 'a');
  });

  testWidgets('compact large text preserves reauth identity and action',
      (tester) async {
    String? reauthId;
    await _pumpSheet(
      tester,
      size: const Size(320, 640),
      textScale: 2,
      viewModel: _vm(const [
        AccountSwitcherItem(
          id: 'c',
          displayName: '演示账号丙',
          status: AccountSwitcherStatus.needsReauth,
        ),
      ]),
      onReauthenticate: (id) async => reauthId = id,
    );

    for (final text in ['演示账号丙', '需重新登录']) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
      expect(paragraph.didExceedMaxLines, isFalse, reason: text);
    }
    expect(find.text('重新登录').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('重新登录'));
    await tester.pump();
    expect(reauthId, 'c');
  });

  testWidgets('empty state offers 添加账号', (tester) async {
    var added = 0;
    await _pumpSheet(
      tester,
      viewModel: AccountSwitcherViewModel(),
      onAdd: () async {
        added++;
      },
    );
    expect(find.text('添加账号'), findsOneWidget);
    await tester.tap(find.text('添加账号'));
    await tester.pump();
    expect(added, 1);
  });

  testWidgets('error with onRetry shows a working 重试', (tester) async {
    var retries = 0;
    final vm = AccountSwitcherViewModel()..setError('网络失败');
    await _pumpSheet(
      tester,
      viewModel: vm,
      onRetry: () async {
        retries++;
      },
    );
    expect(find.text('账号列表加载失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(retries, 1);
  });

  testWidgets('error without onRetry has no 重试 action', (tester) async {
    final vm = AccountSwitcherViewModel()..setError('网络失败');
    await _pumpSheet(tester, viewModel: vm);
    expect(find.text('账号列表加载失败'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('viewModel busy disables row actions with clear evidence',
      (tester) async {
    var selects = 0;
    var added = 0;
    final vm = _vm(const [
      AccountSwitcherItem(id: 'a', displayName: 'Alice', isActive: true),
      AccountSwitcherItem(id: 'b', displayName: 'Bob'),
    ])
      ..setBusy(true);
    await _pumpSheet(
      tester,
      viewModel: vm,
      onSelect: (_) async {
        selects++;
      },
      onAdd: () async {
        added++;
      },
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byTooltip('关闭'), findsNothing);
    final menus = find.byWidgetPredicate(
      (widget) => widget is PopupMenuButton && widget.tooltip == '账号操作',
    );
    expect(menus, findsWidgets);
    for (final element in menus.evaluate()) {
      expect((element.widget as PopupMenuButton).enabled, isFalse);
    }
    final addRow = tester.widget<AppRow>(
      find.ancestor(
        of: find.text('添加账号'),
        matching: find.byType(AppRow),
      ),
    );
    expect(addRow.onTap, isNull);
    expect(addRow.enabled, isFalse);
    expect(selects, 0);
    expect(added, 0);
  });

  testWidgets('idle double tap runs select only once', (tester) async {
    var selects = 0;
    final gate = Completer<void>();
    await _pumpSheet(
      tester,
      viewModel: _vm(const [
        AccountSwitcherItem(id: 'a', displayName: 'Alice', isActive: true),
        AccountSwitcherItem(id: 'b', displayName: 'Bob'),
      ]),
      onSelect: (_) async {
        selects++;
        await gate.future;
      },
    );
    await tester.tap(find.text('Bob'));
    await tester.pump();
    expect(selects, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Bob'));
    await tester.pump();
    expect(selects, 1);
    gate.complete();
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('active account tap does not select', (tester) async {
    var selects = 0;
    await _pumpSheet(
      tester,
      viewModel: _vm(const [
        AccountSwitcherItem(id: 'a', displayName: 'Alice', isActive: true),
        AccountSwitcherItem(id: 'b', displayName: 'Bob'),
      ]),
      onSelect: (_) async {
        selects++;
      },
    );
    await tester.tap(find.text('Alice'));
    await tester.pump();
    expect(selects, 0);
  });

  testWidgets('selects a ready non-active account', (tester) async {
    String? selected;
    await _pumpSheet(
      tester,
      viewModel: _vm(const [
        AccountSwitcherItem(id: 'a', displayName: 'Alice', isActive: true),
        AccountSwitcherItem(id: 'b', displayName: 'Bob'),
      ]),
      onSelect: (id) async {
        selected = id;
      },
    );
    await tester.tap(find.text('Bob'));
    await tester.pump();
    expect(selected, 'b');
  });

  testWidgets('remove requires confirm and uses 移除账号', (tester) async {
    String? removed;
    await _pumpSheet(
      tester,
      viewModel: _vm(const [
        AccountSwitcherItem(id: 'b', displayName: 'Bob'),
      ]),
      onRemove: (id) async {
        removed = id;
      },
    );
    await tester.tap(find.byTooltip('账号操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除账号').last);
    await tester.pumpAndSettle();
    expect(find.text('移除账号？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(removed, isNull);

    await tester.tap(find.byTooltip('账号操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除账号').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '移除账号'));
    await tester.pumpAndSettle();
    expect(removed, 'b');
  });

  testWidgets('logout cancel leaves callback unused', (tester) async {
    var loggedOut = 0;
    await _pumpSheet(
      tester,
      viewModel: _vm(const [
        AccountSwitcherItem(id: 'a', displayName: 'Alice', isActive: true),
      ]),
      onLogoutCurrent: () async {
        loggedOut++;
      },
    );
    await tester.tap(find.byTooltip('账号操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出当前账号'));
    await tester.pumpAndSettle();
    expect(find.text('退出当前账号？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(loggedOut, 0);
  });

  testWidgets('active menu offers 退出当前账号 after confirm', (tester) async {
    var loggedOut = 0;
    await _pumpSheet(
      tester,
      viewModel: _vm(const [
        AccountSwitcherItem(id: 'a', displayName: 'Alice', isActive: true),
      ]),
      onLogoutCurrent: () async {
        loggedOut++;
      },
    );
    await tester.tap(find.byTooltip('账号操作'));
    await tester.pumpAndSettle();
    expect(find.text('退出当前账号'), findsOneWidget);
    await tester.tap(find.text('退出当前账号'));
    await tester.pumpAndSettle();
    expect(find.text('退出当前账号？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '退出当前账号'));
    await tester.pumpAndSettle();
    expect(loggedOut, 1);
  });

  testWidgets('large text keeps the list scrollable without overflow',
      (tester) async {
    await _pumpSheet(
      tester,
      textScale: 1.6,
      viewModel: _vm([
        for (var i = 0; i < 12; i++)
          AccountSwitcherItem(
            id: 'user-$i',
            displayName: 'User $i',
            isActive: i == 0,
          ),
      ]),
    );
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.shrinkWrap, isTrue);
    final height = tester.getSize(find.byType(ListView)).height;
    expect(height, greaterThan(0));
    expect(height, lessThanOrEqualTo(1200 * 0.7 + 1));
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('User 11'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('locked modal blocks back barrier and drag; idle can close',
      (tester) async {
    final gate = Completer<void>();
    final vm = _vm(const [
      AccountSwitcherItem(id: 'a', displayName: 'Alice', isActive: true),
      AccountSwitcherItem(id: 'b', displayName: 'Bob'),
    ]);
    await _pumpModal(
      tester,
      viewModel: vm,
      onSelect: (_) async {
        await gate.future;
      },
    );
    expect(find.byType(AccountSwitcherSheet), findsOneWidget);

    await tester.tap(find.text('Bob'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byTooltip('关闭'), findsNothing);

    // System back uses maybePop. With PopScope(canPop: false) the pop is
    // handled without removing the route (handlePopRoute returns true).
    final lockedPop = await tester.binding.handlePopRoute();
    expect(lockedPop, isTrue);
    await tester.pump();
    expect(find.byType(AccountSwitcherSheet), findsOneWidget);

    // Barrier is not dismissible (isDismissible: false).
    await tester.tapAt(const Offset(200, 24));
    await tester.pump();
    expect(find.byType(AccountSwitcherSheet), findsOneWidget);

    // Drag-to-dismiss is disabled (enableDrag: false); a downward drag must
    // not close the route. Avoid pumpAndSettle while the indeterminate
    // progress bar is animating.
    await tester.drag(find.byType(AccountSwitcherSheet), const Offset(0, 400));
    await tester.pump();
    expect(find.byType(AccountSwitcherSheet), findsOneWidget);

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byTooltip('关闭'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AccountSwitcherSheet), findsNothing);
  });
}
