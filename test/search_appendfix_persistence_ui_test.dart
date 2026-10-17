import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/search/search_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_search_preferences.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

// Synthetic boards only. The shared-preferences channel is the real storage
// boundary: a write the platform rejects must never read as saved.
const _boards = [
  ForumSearchBoard(id: 'all', name: '全部版块'),
  ForumSearchBoard(id: '12', name: 'Fixture board', depth: 1),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final persisted = <String, Object>{};
  var rejectWrites = false;
  var failReads = false;
  // The next write waits here and is then answered with the future's value.
  Completer<bool>? heldWrite;
  Completer<void>? writeStarted;

  setUp(() {
    SharedPreferences.resetStatic();
    persisted.clear();
    rejectWrites = false;
    failReads = false;
    heldWrite = null;
    writeStarted = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') {
        if (failReads) throw PlatformException(code: 'fixture-read-failure');
        return Map<String, Object>.of(persisted);
      }
      if (heldWrite case final held?) {
        heldWrite = null;
        writeStarted?.complete();
        if (!await held.future) return false;
      } else if (rejectWrites) {
        return false;
      }
      final args = call.arguments as Map;
      persisted[args['key'] as String] = args['value'] as Object;
      return true;
    });
  });

  tearDown(() {
    SharedPreferences.resetStatic();
    messenger.setMockMethodCallHandler(channel, null);
  });

  // Guests by default; the account is named only where the scope switches.
  Future<_Repo> pump(WidgetTester tester, {String? account}) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo()..account = account;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: SearchScreen(repository: repo),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('a rejected default write reports, keeps the button and retries',
      (tester) async {
    await pump(tester);
    await tapText(tester, '筛选条件');
    await tapText(tester, '完全匹配');
    expect(find.text('设为默认'), findsOneWidget);

    rejectWrites = true;
    await tapText(tester, '设为默认');
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(find.text('设为默认'), findsOneWidget,
        reason: 'the stored default did not change');
    expect(persisted, isEmpty);

    rejectWrites = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect((await ForumSearchPreferences.load()).defaultMatch,
        ForumSearchMatch.exact);
    expect(find.text('设为默认'), findsNothing);
  });

  // Boards sit in closed groups; filtering lists the match flat.
  Future<void> filterBoards(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).last, text);
    await tester.pumpAndSettle();
  }

  // The picker holds more than one 重试: the pin notice's and the board
  // hierarchy row's. This is the one inside the notice with [message].
  Finder retryIn(String message) => find.descendant(
        of: find.ancestor(
            of: find.textContaining(message), matching: find.byType(ListTile)),
        matching: find.widgetWithText(TextButton, '重试'),
      );

  testWidgets('a retry made for one account never writes for another',
      (tester) async {
    final repo = await pump(tester, account: 'fixture-account-a');
    await tapText(tester, '筛选条件');
    await tapText(tester, '完全匹配');
    rejectWrites = true;
    await tapText(tester, '设为默认');
    expect(find.textContaining('保存失败'), findsOneWidget);

    // The account changes while the error is still on screen.
    repo.account = 'fixture-account-b';
    rejectWrites = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(persisted, isEmpty, reason: 'neither account was written');
    for (final account in ['fixture-account-a', 'fixture-account-b']) {
      expect((await ForumSearchPreferences.load(account: account)).defaultMatch,
          const ForumSearchPreferences().defaultMatch);
    }
  });

  testWidgets('a pin retry after the account changed writes nothing',
      (tester) async {
    final repo = await pump(tester, account: 'fixture-account-a');
    await tapText(tester, '筛选条件');
    await tapText(tester, '版块');
    await filterBoards(tester, 'Fixture');
    rejectWrites = true;
    await tester.tap(find.byTooltip('存为捷径').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Mine');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('保存失败'), findsOneWidget);

    repo.account = 'fixture-account-b';
    rejectWrites = false;
    // The sheet has not noticed yet; the retry itself must refuse.
    await tester.tap(retryIn('保存失败'));
    await tester.pumpAndSettle();
    expect(persisted, isEmpty, reason: 'the stale retry wrote nothing');
    expect(find.text('Mine'), findsNothing);
  });

  testWidgets('a rejected pin write keeps the pins, reports inline and retries',
      (tester) async {
    await pump(tester);
    await tapText(tester, '筛选条件');
    await tapText(tester, '版块');
    await filterBoards(tester, 'Fixture');

    rejectWrites = true;
    await tester.tap(find.byTooltip('存为捷径').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Mine');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(find.text('版块捷径'), findsNothing,
        reason: 'no pin appears before the write is acknowledged');
    expect(persisted, isEmpty);

    rejectWrites = false;
    await tester.tap(retryIn('保存失败'));
    await tester.pumpAndSettle();
    expect(find.textContaining('保存失败'), findsNothing);
    await filterBoards(tester, '');
    expect(find.text('版块捷径'), findsOneWidget);
    expect(find.text('Mine'), findsOneWidget);
    expect(
      (await ForumSearchPreferences.load()).pinnedBoards.map((b) => b.label),
      ['Mine'],
    );
  });

  testWidgets(
      'a second pin edit waits while one save is pending, so a failed '
      'removal is never committed later', (tester) async {
    await ForumSearchPreferences.savePinnedBoards(const [
      ForumSearchPinnedBoard(id: '12', label: 'Pin one'),
      ForumSearchPinnedBoard(id: '99', label: 'Pin two'),
    ]);
    SharedPreferences.resetStatic();
    await pump(tester);
    await tapText(tester, '筛选条件');
    await tapText(tester, '版块');
    expect(find.text('Pin one'), findsOneWidget);
    expect(find.text('Pin two'), findsOneWidget);

    // The handler consumes heldWrite; this one releases it.
    final rejectedWrite = heldWrite = Completer<bool>();
    writeStarted = Completer<void>();
    await tester.tap(find.byTooltip('删除捷径').first);
    await tester.pump();
    await writeStarted!.future;
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // The second removal is refused while the first is unacknowledged.
    await tester.tap(find.byTooltip('删除捷径').at(1), warnIfMissed: false);
    await tester.pump();

    rejectedWrite.complete(false);
    await tester.pumpAndSettle();
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(find.text('Pin one'), findsOneWidget);
    expect(find.text('Pin two'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      (await ForumSearchPreferences.load()).pinnedBoards.map((b) => b.label),
      ['Pin one', 'Pin two'],
    );

    // Idle again: the second removal is its own edit of the stored list.
    await tester.tap(find.byTooltip('删除捷径').at(1));
    await tester.pumpAndSettle();
    expect(find.text('Pin two'), findsNothing);
    expect(
      (await ForumSearchPreferences.load()).pinnedBoards.map((b) => b.label),
      ['Pin one'],
    );
  });

  testWidgets(
      'a pin list that fails to load offers a retry; search still opens',
      (tester) async {
    await ForumSearchPreferences.savePinnedBoards(
      const [ForumSearchPinnedBoard(id: '12', label: 'Kept pin')],
    );
    SharedPreferences.resetStatic();

    await pump(tester);
    // The repository is built; only the picker's pin read is failing.
    SharedPreferences.resetStatic();
    failReads = true;
    await tapText(tester, '筛选条件');
    await tapText(tester, '版块');
    expect(find.text('常用版块加载失败'), findsOneWidget);
    await filterBoards(tester, 'Fixture');
    expect(find.text('Fixture board'), findsWidgets,
        reason: 'the board list does not depend on the pins');
    await filterBoards(tester, '');

    failReads = false;
    await tester.tap(retryIn('常用版块加载失败'));
    await tester.pumpAndSettle();
    expect(find.text('常用版块加载失败'), findsNothing);
    expect(find.text('Kept pin'), findsOneWidget);
  });
}

class _Repo extends ForumRepository {
  String? account;

  @override
  String? get currentUsername => account;

  @override
  Future<List<ForumSearchBoard>> fetchSearchBoards() async => _boards;

  @override
  Future<List<ForumSection>> fetchForumSections() async => const [];
}
