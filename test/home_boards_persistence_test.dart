import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/home/home_shell.dart';
import 'package:south_plus_rewrite/features/profile/home_boards_settings_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/home_reading_preferences.dart';

class _Repo extends ForumRepository {
  @override
  String? get localPreferenceAccount => 'fixture';
  @override
  Future<List<ForumSection>> fetchForumSections() async => const [
    ForumSection(nativeId: '7', title: '交流', items: []),
    ForumSection(nativeId: '39', title: '漫区', items: []),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(480, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: HomeBoardsSettingsScreen(repository: _Repo())));
    await tester.pumpAndSettle();
  }

  testWidgets('rejected reorder rolls back and stays locked when recovery reads fail', (tester) async {
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final persisted = <String, Object>{};
    var rejectWrite = false;
    var rejectReads = false;
    var writes = 0;
    SharedPreferences.resetStatic();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') {
        if (rejectReads) throw PlatformException(code: 'read-unavailable');
        return Map<String, Object>.of(persisted);
      }
      writes++;
      if (rejectWrite) { rejectReads = true; return false; }
      final args = call.arguments as Map;
      if (call.method == 'remove') {
        persisted.remove(args['key']);
      } else {
        persisted[args['key'] as String] = args['value'] as Object;
      }
      return true;
    });
    addTearDown(() {
      SharedPreferences.resetStatic();
      messenger.setMockMethodCallHandler(channel, null);
    });
    await HomeReadingPreferences.saveSectionOrder(['section-id:7', 'section-id:39'], account: 'fixture');
    await pump(tester);
    final before = Map<String, Object>.of(persisted);
    rejectWrite = true;
    await tester.drag(find.byType(ReorderableDragStartListener).first, const Offset(0, 190));
    await tester.pumpAndSettle();
    expect(persisted, before);
    expect(find.text('加载失败'), findsOneWidget);
    expect(tester.getTopLeft(find.text('交流')).dy, lessThan(tester.getTopLeft(find.text('漫区')).dy));
    expect(tester.widgetList<ReorderableDragStartListener>(find.byType(ReorderableDragStartListener)).every((w) => !w.enabled), isTrue);
    expect(tester.widgetList<Switch>(find.byType(Switch)).every((w) => w.onChanged == null), isTrue);
    final attempted = writes;
    await tester.drag(find.byType(ReorderableDragStartListener).first, const Offset(0, 190));
    await tester.pumpAndSettle();
    expect(writes, attempted, reason: 'no second action can commit a rejected draft');
    rejectWrite = false;
    rejectReads = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    final prefs = await HomeReadingPreferences.load(account: 'fixture');
    expect(prefs.sectionOrder, ['section-id:7', 'section-id:39']);
    expect(prefs.hiddenSectionIds, {'section-id:7'});
  });

  testWidgets('failed home fold rolls back and locks folds until a read succeeds', (tester) async {
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final persisted = <String, Object>{};
    var rejectWrite = false;
    var rejectReads = false;
    var writes = 0;
    SharedPreferences.resetStatic();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') {
        if (rejectReads) throw PlatformException(code: 'read-unavailable');
        return Map<String, Object>.of(persisted);
      }
      writes++;
      if (rejectWrite) { rejectReads = true; return false; }
      final args = call.arguments as Map;
      if (call.method == 'remove') {
        persisted.remove(args['key']);
      } else {
        persisted[args['key'] as String] = args['value'] as Object;
      }
      return true;
    });
    addTearDown(() {
      SharedPreferences.resetStatic();
      messenger.setMockMethodCallHandler(channel, null);
    });
    tester.view.physicalSize = const Size(480, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: HomeShell(repository: _HomeRepo())));
    await tester.pumpAndSettle();
    expect(find.text('First board').hitTestable(), findsOneWidget);
    final before = Map<String, Object>.of(persisted);
    rejectWrite = true;
    await tester.tap(find.text('First section'));
    await tester.pumpAndSettle();
    expect(persisted, before, reason: 'no fold was acknowledged');
    expect(find.text('First board').hitTestable(), findsOneWidget,
        reason: 'the unacknowledged fold is rolled back');
    expect(find.text('首页设置未能读取'), findsOneWidget);
    final attempted = writes;
    await tester.tap(find.text('First section'));
    await tester.pumpAndSettle();
    expect(writes, attempted, reason: 'folds wait for a successful read');
    expect(find.text('First board').hitTestable(), findsOneWidget);
    expect(rowsButton(tester).onPressed, isNull,
        reason: 'no other layout write starts from an unread state');
    rejectWrite = false;
    rejectReads = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('首页设置未能读取'), findsNothing);
    await tester.tap(find.text('First section'));
    await tester.pumpAndSettle();
    expect(find.text('First board').hitTestable(), findsNothing);
    expect((await HomeReadingPreferences.load(account: 'fixture')).collapsedIds,
        {'section-id:7'});
  });

  testWidgets('failed quick-row save rolls back and locks 速览设置 until a read succeeds', (tester) async {
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final persisted = <String, Object>{};
    var rejectWrite = false;
    var rejectReads = false;
    var writes = 0;
    SharedPreferences.resetStatic();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') {
        if (rejectReads) throw PlatformException(code: 'read-unavailable');
        return Map<String, Object>.of(persisted);
      }
      writes++;
      if (rejectWrite) { rejectReads = true; return false; }
      final args = call.arguments as Map;
      if (call.method == 'remove') {
        persisted.remove(args['key']);
      } else {
        persisted[args['key'] as String] = args['value'] as Object;
      }
      return true;
    });
    addTearDown(() {
      SharedPreferences.resetStatic();
      messenger.setMockMethodCallHandler(channel, null);
    });
    tester.view.physicalSize = const Size(480, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final acknowledged = (await HomeReadingPreferences.load(account: 'fixture')).quickRowCount;
    await tester.pumpWidget(MaterialApp(home: HomeShell(repository: _HomeRepo())));
    await tester.pumpAndSettle();
    final pick = acknowledged == 3 ? 4 : 3;
    await tester.tap(find.byTooltip('速览设置'));
    await tester.pumpAndSettle();
    final writesBefore = writes;
    rejectWrite = true;
    await tester.tap(find.text('显示行数'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('$pick 行'));
    await tester.pumpAndSettle();
    expect(writes, writesBefore + 1);
    expect(find.text('速览设置加载失败'), findsOneWidget);
    // Nothing is offered while what is saved is unknown.
    expect(find.text('显示行数'), findsNothing);
    expect(find.text('栏目 1'), findsNothing);
    expect(writes, writesBefore + 1);
    rejectWrite = false;
    rejectReads = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('$acknowledged 行'), findsOneWidget,
        reason: 'the rejected count was rolled back');
    expect(writes, writesBefore + 1, reason: 'the retry only reads');
    await tester.tap(find.text('显示行数'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('$pick 行'));
    await tester.pumpAndSettle();
    expect(
        (await HomeReadingPreferences.load(account: 'fixture')).quickRowCount,
        pick);
  });
}

IconButton rowsButton(WidgetTester tester) => tester.widget<IconButton>(find
    .ancestor(of: find.byTooltip('速览设置'), matching: find.byType(IconButton))
    .first);

class _HomeRepo extends _Repo {
  @override
  Future<ForumHomeSnapshot> fetchHome() async => const ForumHomeSnapshot(
        latest: [],
        hot: [],
        sections: [
          ForumSection(nativeId: '7', title: 'First section', items: [
            ForumBoard(
                name: 'First board',
                url: 'https://south-plus.net/thread.php?fid-42.html',
                section: 'First section'),
          ]),
          ForumSection(nativeId: '39', title: 'Second section', items: []),
        ],
      );
  @override
  Future<ForumTaskSnapshot?> loadCachedForumTaskSnapshot() async => null;
  @override
  Future<ForumTaskQuickClaimResult?> autoClaimForumTaskRewardsIfDue() async =>
      null;
}
