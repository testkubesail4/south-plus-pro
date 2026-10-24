import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/messages/pm_box_screen.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';

// Synthetic messages only: 12 a page; page 2 repeats one row of page 1.
const _next = 'message.php?action-receivebox-page-2.html';

ForumPmSummary _message(String id) => ForumPmSummary(
      box: ForumPmBox.inbox,
      type: ForumPmType.personal,
      id: id,
      peer: 'peer $id',
      title: 'Message $id',
      time: '2026-01-01',
      detailPath: 'message.php?action-read-mid-$id.html',
    );

class _Repo extends ForumRepository {
  final paths = <String?>[];
  // Each box read waits for the next queued gate, if any, and fails if the
  // gate is one of [failing].
  final gates = <Completer<void>>[];
  final failing = <Completer<void>>{};

  @override
  Future<ForumPmDetail> fetchPmDetail(ForumPmSummary message) async =>
      ForumPmDetail(
          summary: message,
          sender: message.peer,
          title: message.title,
          time: '',
          content: 'body',
          deletePath: 'message.php?action-del-delids-${message.id}.html');

  // Deleted on the site: no later page holds them.
  final deleted = <String>{};

  @override
  Future<ForumPmActionResult> deletePm(ForumPmSummary message,
      {ForumPmDetail? detail}) async {
    deleted.add(message.id);
    return const ForumPmActionResult(message: 'deleted');
  }

  // Page 1 holds no message, yet links page 2.
  bool emptyFirst = false;
  // Page 1 holds no message and links page 4 only, not page 2.
  bool sparse = false;
  // Whether page 1 names page 2 as next.
  bool firstHasNext = true;

  @override
  Future<ForumPmPage> fetchPmBox(ForumPmBox box, {String? pagePath}) async {
    paths.add(pagePath);
    if (gates.isNotEmpty) {
      final gate = gates.removeAt(0);
      await gate.future;
      if (failing.contains(gate)) {
        throw const ForumRequestException(
            ForumRequestKind.network, 'Fixture failure');
      }
    }
    if (sparse) {
      return ForumPmPage(box: box, messages: const [], pageLinks: const [
        ForumPmPageLink(
            label: '4', path: 'message.php?action-receivebox-page-4.html'),
      ]);
    }
    return pagePath == null
        ? ForumPmPage(
            box: box,
            pageLinks: const [ForumPmPageLink(label: '下一页', path: _next)],
            messages: [
              if (!emptyFirst)
                for (var i = 0; i < 12; i++) _message('${100 + i}'),
            ],
            nextPagePath: firstHasNext ? _next : null,
          )
        : ForumPmPage(
            box: box,
            currentPage: 2,
            pageLinks: const [
              ForumPmPageLink(
                  label: '上一页',
                  path: 'message.php?action-receivebox-page-1.html'),
            ],
            messages: [
              for (final id in ['111', '200'])
                if (!deleted.contains(id)) _message(id),
            ],
          );
  }
}

void main() {
  Future<_Repo> pump(WidgetTester tester, LoadingMode mode,
      {bool emptyFirst = false, bool sparse = false}) async {
    SharedPreferences.setMockInitialValues({});
    await LoadingPreferences.load();
    await LoadingPreferences.save(LoadingDomain.pm, mode);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo()
      ..emptyFirst = emptyFirst
      ..sparse = sparse;
    await tester.pumpWidget(MaterialApp(home: PmBoxScreen(repository: repo)));
    await tester.pumpAndSettle();
    return repo;
  }

  Future<void> toEnd(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, -20000));
    await tester.pumpAndSettle();
  }

  testWidgets('手动翻页: 下一页 turns to page 2 alone', (tester) async {
    final repo = await pump(tester, LoadingMode.manual);
    await toEnd(tester);
    expect(repo.paths, [null]);
    await tester.tap(find.byKey(const ValueKey('page-end-next')));
    await tester.pumpAndSettle();
    expect(repo.paths, [null, _next]);
    expect(find.text('Message 200'), findsOneWidget);
    expect(find.text('Message 100', skipOffstage: false), findsNothing);
  });

  testWidgets('an empty first page with a next one is not an empty box',
      (tester) async {
    final repo = await pump(tester, LoadingMode.continuous, emptyFirst: true);
    expect(find.text('暂无消息'), findsNothing);
    expect(find.text('本页没有消息'), findsOneWidget);
    await toEnd(tester);
    expect(repo.paths, [null, _next]);
    expect(find.text('Message 200'), findsOneWidget);
    expect(find.text('暂无消息'), findsNothing);
  });

  testWidgets('自动接续 appends the next page, a repeated message once',
      (tester) async {
    final repo = await pump(tester, LoadingMode.continuous);
    await toEnd(tester);
    await toEnd(tester);
    expect(repo.paths, [null, _next]);
    expect(find.text('第 2 页'), findsOneWidget);
    expect(find.text('Message 200'), findsOneWidget);
    expect(find.text('Message 111', skipOffstage: false), findsOneWidget);
    // No next page, but no page count either: the end is not claimed.
    expect(find.text('已到最后一页'), findsNothing);
    // The page links are page 2's: page 1's 下一页 would lead back to 2.
    expect(find.widgetWithText(OutlinedButton, '下一页'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '上一页'), findsOneWidget);
  });

  testWidgets('a message read on an appended page rereads only that page',
      (tester) async {
    final repo = await pump(tester, LoadingMode.continuous);
    await toEnd(tester);
    await toEnd(tester);
    expect(repo.paths, [null, _next]);
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).last).position;
    final offset = position.pixels;
    await tester.tap(find.text('Message 200'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(repo.paths, [null, _next, _next]);
    expect(find.text('Message 100', skipOffstage: false), findsOneWidget);
    expect(find.text('Message 200'), findsOneWidget);
    expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).last)
            .position
            .pixels,
        offset);
  });

  testWidgets('a reread of a page a delete since dropped lands nowhere',
      (tester) async {
    final repo = await pump(tester, LoadingMode.continuous);
    await toEnd(tester);
    await toEnd(tester);
    expect(repo.paths, [null, _next]);

    // A delete rereads the box; its answer is held.
    final action = Completer<void>();
    repo.gates.add(action);
    await tester.tap(find.text('Message 200'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    // Reading the appended row again starts its page's reread, held too.
    final read = Completer<void>();
    repo.gates.add(read);
    await tester.tap(find.text('Message 200'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(repo.paths, [null, _next, null, _next]);

    // The delete's answer drops page 2; reading it on again stays pending.
    // Its loading row spins, so only bounded frames from here.
    repo.gates.add(Completer<void>());
    action.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Message 200'), findsNothing);
    read.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.text('Message 200'), findsNothing);
  });

  for (final (readFirst, actionFails) in [
    (false, false),
    (true, false),
    (false, true),
    (true, true),
  ]) {
    testWidgets(
        'a delete drops the appended pages though a later reread wins '
        '(read answers first: $readFirst, reread fails: $actionFails)',
        (tester) async {
      final repo = await pump(tester, LoadingMode.continuous);
      await toEnd(tester);
      await toEnd(tester);

      final action = Completer<void>();
      repo.gates.add(action);
      if (actionFails) repo.failing.add(action);
      await tester.tap(find.text('Message 200'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      // A row of the first page is read meanwhile; its reread is held too.
      final read = Completer<void>();
      repo.gates.add(read);
      await tester.tap(find.text('Message 111'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(repo.paths, [null, _next, null, null]);

      for (final gate in readFirst ? [read, action] : [action, read]) {
        gate.complete();
        await tester.pumpAndSettle();
      }
      await toEnd(tester);
      expect(find.text('Message 200', skipOffstage: false), findsNothing);
      expect(find.text('Message 111', skipOffstage: false), findsOneWidget);
      // Past the delete's own confirmation.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.textContaining('短消息刷新失败'),
          actionFails ? findsOneWidget : findsNothing);
    });
  }

  for (final olderFails in [false, true]) {
    testWidgets(
        'an older delete settling last leaves the newer one\'s pages '
        '(its reread fails: $olderFails)', (tester) async {
      final repo = await pump(tester, LoadingMode.continuous);
      await toEnd(tester);
      await toEnd(tester);
      Future<void> delete(String title) async {
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('更多'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('删除'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '删除'));
        await tester.pumpAndSettle();
      }

      final older = Completer<void>();
      repo.gates.add(older);
      if (olderFails) repo.failing.add(older);
      await delete('Message 200');
      // The newer delete's reread answers at once and page 2 reads on afresh.
      await delete('Message 111');
      await toEnd(tester);
      expect(repo.paths, [null, _next, null, null, _next]);
      expect(find.text('第 2 页'), findsOneWidget);

      older.complete();
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(repo.paths, hasLength(5));
      expect(find.text('第 2 页'), findsOneWidget);
      expect(find.textContaining('短消息刷新失败'), findsNothing);
    });
  }

  testWidgets('an appended page whose path is gone is not reread as page 1',
      (tester) async {
    final repo = await pump(tester, LoadingMode.continuous);
    await toEnd(tester);
    await toEnd(tester);
    // Page 1, read again, no longer names page 2.
    repo.firstHasNext = false;
    await tester.tap(find.text('Message 111'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(repo.paths, [null, _next, null]);

    await tester.tap(find.text('Message 200'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(repo.paths, [null, _next, null]);
    expect(find.text('Message 200'), findsOneWidget);
  });

  testWidgets('an empty page linking only page 4 is neither empty nor the end',
      (tester) async {
    final repo = await pump(tester, LoadingMode.continuous, sparse: true);
    await toEnd(tester);
    expect(repo.paths, [null]);
    expect(find.text('暂无消息'), findsNothing);
    expect(find.text('本页没有消息'), findsOneWidget);
    expect(find.text('已到最后一页'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '4'), findsOneWidget);
  });
}
