import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/async_state_view.dart';
import 'package:south_plus_rewrite/features/common/user_tags_inline.dart';
import 'package:south_plus_rewrite/features/history/browsing_history_screen.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/models/user_content_query.dart';
import 'package:south_plus_rewrite/services/browsing_history_store.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:south_plus_rewrite/services/forum_session_store.dart';
import 'package:south_plus_rewrite/services/tag_color_store.dart';
import 'package:south_plus_rewrite/services/user_tag_store.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

class _FixtureSite extends ForumSite {
  const _FixtureSite() : super('127.0.0.1');

  @override
  Uri get baseUri => Uri.parse('http://127.0.0.1:8765/');
}

const _config = ForumNetworkConfig(
  site: _FixtureSite(),
  mode: ForumNetworkMode.native,
  dohProvider: ForumNetworkConfig.defaultProvider,
);
const _thread = ForumThread(
  title: 'Synthetic edit thread',
  url: 'http://127.0.0.1:8765/read.php?tid-950001.html',
  replies: 2,
  section: 'Synthetic board',
);

const _openingSource =
    '[b]Opening original[/b] [url=https://example.invalid/reference]source[/url]';
const _replySource = '[i]Reply original[/i] [s:716]';
const _lowTitle = 'Known low [1999-01-01] 浏览:999 回复:999';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late ForumRepository repository;

  Future<dynamic> fixture(String path, {bool reset = false}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.openUrl(
          reset ? 'POST' : 'GET', _config.baseUri.resolve(path));
      request.headers.set('Cookie', 'appendfix_winduser=synthetic-local-only');
      if (reset) {
        final body = utf8.encode('fixture-only');
        request.contentLength = body.length;
        request.add(body);
      }
      final response = await request.close();
      expect(response.statusCode, 200, reason: path);
      return jsonDecode(await utf8.decoder.bind(response).join());
    } finally {
      client.close(force: true);
    }
  }

  // EditableText also matches textContaining; wait for the actual floor route.
  Finder floorText(String text) => find.descendant(
        of: find.byType(ThreadDetailScreen),
        matching: find.textContaining(text, findRichText: true),
      );

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(finder, findsWidgets);
    expect(tester.takeException(), isNull);
  }

  Future<void> tap(WidgetTester tester, Finder finder,
      {bool settle = true}) async {
    await waitFor(tester, finder);
    await tester.ensureVisible(finder.first);
    if (settle) await tester.pumpAndSettle();
    await tester.tap(finder.first);
    await tester.pump();
  }

  Future<void> mountScreen(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: screen));
  }

  Future<void> mount(WidgetTester tester, ForumThread thread) => mountScreen(
      tester, ThreadDetailScreen(repository: repository, thread: thread));

  Future<void> waitForScanRequest(WidgetTester tester) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      if ((await fixture('round/stats'))['scan_waiting'] == true) return;
      await tester.pump(const Duration(milliseconds: 50));
    }
    fail('The fixture never received the held page-2 scan request');
  }

  void expectOrder(WidgetTester tester, List<String> titles) {
    final tops = [
      for (final title in titles) tester.getTopLeft(find.text(title)).dy
    ];
    for (var i = 1; i < tops.length; i++) {
      expect(tops[i], greaterThan(tops[i - 1]), reason: titles.join(' → '));
    }
  }

  Color tagFill(WidgetTester tester, String label) {
    final capsule = find.ancestor(
        of: find.text(label), matching: find.byType(UserTagCapsule));
    final boxes = tester.widgetList<DecoratedBox>(
        find.descendant(of: capsule, matching: find.byType(DecoratedBox)));
    return boxes
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.color)
        .whereType<Color>()
        .first;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppThemeController.setMode(ThemeMode.light);
    await fixture('round/reset', reset: true);
    await ForumSessionStore().saveCookies({
      'appendfix_winduser': ForumStoredCookie.session(
        name: 'appendfix_winduser',
        value: 'synthetic-local-only',
        origin: _config.baseUri,
      ),
    });
    repository = ForumRepository(config: _config);
    expect(await repository.restoreSession(), isTrue);
  });

  testWidgets(
      'truncated Favorites keeps valid Topics visible and shows a retriable error, never an empty success',
      (tester) async {
    await fixture('round/truncate-favorites', reset: true);
    await mountScreen(
        tester,
        UserProfileScreen(
          repository: repository,
          userUrl: 'http://127.0.0.1:8765/u.php?action-show-uid-950002.html',
          initialTab: UserProfileTab.topics,
        ));
    await waitFor(tester, find.text('Known high'));
    await tap(tester, find.text('收藏'));
    await waitFor(tester, find.byType(AsyncErrorView));
    expect(find.text('没有公开收藏'), findsNothing,
        reason: 'missing table is a failed tab, not an empty collection');
    final before = (await fixture('round/stats'))['list_reads'] as List;
    final favoriteReads =
        before.where((query) => '$query'.contains('favor')).length;
    await fixture('round/restore-favorites', reset: true);
    await tap(tester, find.text('重试'));
    await waitFor(tester, find.text('没有公开收藏'));
    final after = (await fixture('round/stats'))['list_reads'] as List;
    expect(after.where((query) => '$query'.contains('favor')).length,
        greaterThan(favoriteReads),
        reason: 'retry must refetch the failed tab');
    // Revealing the error's retry can scroll the profile's header tabs away.
    final outer = find
        .descendant(
            of: find.byType(NestedScrollView),
            matching: find.byType(Scrollable))
        .first;
    tester.state<ScrollableState>(outer).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tap(tester, find.text('主题'));
    await waitFor(tester, find.text('Known high'));
    for (final title in [_lowTitle, 'Unknown metrics..', 'Known high']) {
      expect(find.text(title), findsOneWidget);
    }
  });

  testWidgets(
      'HTTP 200 truncated list fails loud; native date and metrics never come from the title',
      (tester) async {
    const query = UserContentQuery(uid: '950002', tab: UserProfileTab.topics);
    await fixture('round/truncate-list-next', reset: true);
    await expectLater(repository.fetchUserContent(query),
        throwsA(isA<ForumRequestException>()));
    final result = await repository.fetchUserContent(query, refresh: true);
    expect(result.items, hasLength(3));
    final known = result.items.first;
    expect(known.title, contains('[1999-01-01] 浏览:999 回复:999'));
    expect(known.date, '2025-01-02');
    expect(known.views, 0);
    expect(known.replies, 0);
    expect(result.items[1].views, isNull);
    expect(result.items[1].replies, isNull);
    expect((await fixture('round/stats'))['thread_reads'], isEmpty);
  });

  testWidgets(
      'resume page 2 then 从头看 reveals detached tpc opening post without false missing-floor notice',
      (tester) async {
    await repository.saveThreadReadPosition(
        _thread, const ThreadReadPosition(page: 2, anchor: '950102'));
    await mount(tester, _thread);
    await waitFor(tester, find.text('从头看'));
    expect(find.textContaining('Reply original', findRichText: true),
        findsWidgets);
    expect((await fixture('round/stats'))['thread_pages'], [2, 1],
        reason: 'page 2 loads the OP metadata once');
    await tap(tester, find.text('从头看'));
    final opening = find.textContaining('Opening original', findRichText: true);
    await waitFor(tester, opening);
    await tester.pumpAndSettle();
    // Old parser recognises numeric detached anchors but loses tpc at DIV.
    expect(find.textContaining('未找到指定楼层'), findsNothing);
    expect(opening.hitTestable(), findsWidgets);
    expect((await fixture('round/stats'))['thread_pages'], [2, 1, 1]);
  });

  testWidgets('从头看 persists the OP so reopening does not resume the old page',
      (tester) async {
    await repository.saveThreadReadPosition(
        _thread, const ThreadReadPosition(page: 2, anchor: '950102'));
    await mount(tester, _thread);
    await tap(tester, find.text('从头看'));
    final opening = find.textContaining('Opening original', findRichText: true);
    await waitFor(tester, opening);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await mount(tester, _thread);
    await waitFor(tester, opening);
    expect(find.textContaining('未找到指定楼层'), findsNothing);
    expect(opening.hitTestable(), findsWidgets);
  });

  for (final (pid, page, floor, original, updated) in [
    ('950101', 1, '楼主', _openingSource, '[b]Opening edited[/b]'),
    ('950102', 2, 'B2F', _replySource, '[i]Reply edited[/i]'),
  ]) {
    testWidgets(
        '$floor server edit link opens original BBCode and modify refreshes same floor, never appends a reply',
        (tester) async {
      final thread = _thread.copyWith(
          url: 'http://127.0.0.1:8765/read.php?tid-950001-page-$page.html');
      await mount(tester, thread);
      await waitFor(
          tester, find.byKey(ValueKey('floor-actions-Synthetic self-$floor')));
      if (page == 2) {
        await tap(tester,
            find.byKey(const ValueKey('floor-actions-Synthetic other-B1F')));
        await tester.pumpAndSettle();
        expect(find.text('编辑'), findsNothing,
            reason: 'another author has no server edit link');
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      }
      await tap(
          tester, find.byKey(ValueKey('floor-actions-Synthetic self-$floor')));
      await tap(tester, find.text('编辑'));
      final content = find.byWidgetPredicate((widget) =>
          widget is TextField && widget.controller?.text == original);
      await waitFor(tester, content);
      await tester.enterText(content, updated);
      await tap(tester, find.text('保存修改'));
      final rendered = floorText(page == 1 ? 'Opening edited' : 'Reply edited');
      await waitFor(tester, rendered);
      await tester.pumpAndSettle();
      expect(rendered, findsOneWidget);
      expect(find.byKey(ValueKey('floor-actions-Synthetic self-$floor')),
          findsOneWidget);
      if (page == 2) {
        expect(find.byKey(const ValueKey('floor-actions-Synthetic other-B1F')),
            findsOneWidget);
      }
      final stats = await fixture('round/stats');
      final edits = stats['edits'] as List;
      expect(edits, hasLength(1));
      expect(edits.single['action'], ['modify']);
      expect(edits.single['pid'], [pid]);
      expect(edits.single['atc_content'], [updated]);
      expect(edits.single['atc_requiresell'], ['1']);
      expect(edits.single['atc_money'], ['7']);
      expect(edits.single['atc_hide'], ['1']);
      expect(edits.single['keep[attachment]'], ['synthetic-attachment']);
      expect(edits.single.containsKey('atc_anonymous'), isFalse);
      expect(stats['thread_pages'], page == 2 ? [2, 1, 2, 1] : [1, 1],
          reason:
              'success refetches the edited page and its bounded OP metadata instead of adding a reply');
      expect(tester.takeException(), isNull);
    });
  }

  for (final feedback in [
    'ambiguous',
    'rejected',
    'wrong-target',
    'external'
  ]) {
    testWidgets(
        '$feedback modify feedback keeps composer text and reopens a fresh draft only on explicit save',
        (tester) async {
      final thread = _thread.copyWith(
          url: 'http://127.0.0.1:8765/read.php?tid-950001-page-2.html');
      await mount(tester, thread);
      await tap(tester,
          find.byKey(const ValueKey('floor-actions-Synthetic self-B2F')));
      await tap(tester, find.text('编辑'));
      final content = find.byWidgetPredicate((widget) =>
          widget is TextField && widget.decoration?.labelText == '正文');
      await waitFor(tester, content);
      expect(tester.widget<TextField>(content).controller?.text, _replySource);
      final updated = '[i]Retained $feedback draft[/i]';
      await tester.enterText(content, updated);
      await fixture('round/edit-$feedback-next', reset: true);
      await tap(tester, find.byKey(const ValueKey('edit-save-button')));
      await waitFor(tester, find.textContaining('保存未确认'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(content).controller?.text, updated);
      expect(find.text('已保存修改'), findsNothing);
      if (feedback == 'rejected') {
        expect(find.textContaining('修改失败'), findsWidgets);
      }
      final uncertain = await fixture('round/stats');
      expect(uncertain['edit_attempts'], hasLength(1),
          reason: 'an uncertain write is never retried automatically');
      expect(uncertain['edits'], isEmpty);
      expect(uncertain['edit_form_reads'], ['950102']);
      expect(uncertain['post_bodies']['950102'], _replySource);
      // The fresh form still holds the original body, so resetting local text
      // while reopening would lose the user's edit and fail the readback below.
      await tap(tester, find.byKey(const ValueKey('edit-save-button')));
      final rendered = floorText('Retained $feedback draft');
      await waitFor(tester, rendered);
      await tester.pumpAndSettle();
      expect(rendered, findsOneWidget);
      expect(find.text('已保存修改'), findsOneWidget);
      final confirmed = await fixture('round/stats');
      expect(confirmed['edit_form_reads'], ['950102', '950102']);
      expect(confirmed['edit_attempts'], hasLength(2));
      expect(confirmed['edits'], hasLength(1));
      expect(confirmed['post_bodies']['950102'], updated);
      expect(confirmed['thread_pages'], [2, 1, 2, 1],
          reason: 'each page-2 read loads the OP metadata once');
      expect(find.byKey(const ValueKey('floor-actions-Synthetic self-B2F')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('floor-actions-Synthetic other-B1F')),
          findsOneWidget);
    });
  }

  testWidgets(
      'lazy sort never requests unloaded rows; eager progress is partial and unknown metrics stay last',
      (tester) async {
    await mountScreen(
        tester,
        UserProfileScreen(
          repository: repository,
          userUrl: 'http://127.0.0.1:8765/u.php?action-show-uid-950002.html',
          initialTab: UserProfileTab.topics,
        ));
    await waitFor(tester, find.text('Known high'));
    final beforeSort = await fixture('round/stats');
    await tap(tester, find.byTooltip('排序'));
    await tap(tester, find.text('发帖时间 从旧到新'));
    await tester.pumpAndSettle();
    expectOrder(tester, ['Unknown metrics..', _lowTitle, 'Known high']);
    for (final (choice, titles) in [
      ('浏览量 从少到多', [_lowTitle, 'Known high', 'Unknown metrics..']),
      ('浏览量 从多到少', ['Known high', _lowTitle, 'Unknown metrics..']),
    ]) {
      await tap(tester, find.byTooltip('排序'));
      await tap(tester, find.text(choice));
      await tester.pumpAndSettle();
      expectOrder(tester, titles);
    }
    expect(find.textContaining('已加载的 1 页'), findsWidgets);
    final loaded = await fixture('round/stats');
    expect(loaded['list_reads'], beforeSort['list_reads'],
        reason: 'picking a loaded-only sort must issue no list requests');
    expect((loaded['topic_pages'] as List).every((page) => page == 1), isTrue);
    expect(loaded['thread_reads'], isEmpty);
    expect(find.text('Unloaded maximum'), findsNothing);
    try {
      await tap(tester, find.text('排序全部页面'));
      await tap(tester, find.text('开始排序'), settle: false);
      await waitForScanRequest(tester);
      final stop = find.text('停止');
      await waitFor(tester, stop);
      await tester.ensureVisible(stop);
      await waitFor(tester, stop.hitTestable());
      expect(find.byType(LinearProgressIndicator), findsWidgets);
      expect(find.textContaining('结果不完整'), findsWidgets);
      await tap(tester, find.text('停止'), settle: false);
      await waitFor(tester, find.textContaining('已停止，结果不完整'));
      await fixture('round/release-scan', reset: true);
      await tester.pumpAndSettle();
      expect((await fixture('round/stats'))['topic_pages'], isNot(contains(3)));
      await tap(tester, find.text('继续'), settle: false);
      await waitFor(tester, find.textContaining('全部 3 页'));
      await tester.pumpAndSettle();
      expectOrder(tester, [
        'Unloaded maximum',
        'Known high',
        _lowTitle,
        'Unknown metrics..',
        'Unloaded unknown'
      ]);
      expect((await fixture('round/stats'))['thread_reads'], isEmpty,
          reason: 'empty-keyword sorting never enriches even truncated titles');
      await tap(tester, find.text('返回已加载'));
      await waitFor(tester, find.textContaining('已加载的 1 页'));
      expect(find.text('Unloaded maximum'), findsNothing);
    } finally {
      await fixture('round/release-scan', reset: true);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
      'tag colour persists after editor dismissal and repository reopen across profile and floor labels',
      (tester) async {
    await UserTagStore.save('950002', ['Library'],
        account: repository.localPreferenceAccount);
    await UserTagStore.save('930001', ['library'],
        account: repository.localPreferenceAccount);
    await mountScreen(
        tester,
        UserProfileScreen(
          repository: repository,
          userUrl: 'http://127.0.0.1:8765/u.php?action-show-uid-950002.html',
        ));
    await waitFor(tester, find.text('Library'));
    final neutral = tagFill(tester, 'Library');
    await tap(tester, find.text('Library'));
    await tap(tester, find.byKey(const ValueKey('user-tag-chip:Library')));
    await tap(tester, find.byKey(const ValueKey('tag-color:blue')));
    await tap(tester, find.text('取消'));
    await tester.pumpAndSettle();
    final selected = tagFill(tester, 'Library');
    expect(selected, isNot(neutral));
    expect(
        (await TagColorStore.load(
            account: repository.localPreferenceAccount))['library'],
        'blue');
    await tester.pumpWidget(const SizedBox.shrink());
    repository = ForumRepository(config: _config);
    expect(await repository.restoreSession(), isTrue);
    await mount(
        tester,
        _thread.copyWith(
          url: 'http://127.0.0.1:8765/read.php?tid-950001-page-2.html',
        ));
    await waitFor(tester, find.text('Library'));
    await waitFor(tester, find.text('library'));
    expect(tagFill(tester, 'Library'), selected);
    expect(tagFill(tester, 'library'), selected,
        reason:
            'one normalized label has one account-wide colour, not one per UID');
  });

  testWidgets(
      'history keyword composes with year month day; clearing filters restores retained records',
      (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final history = BrowsingHistoryStore();
    await history.clear();
    final records = [
      ('Needle January second', DateTime(2025, 1, 2, 12)),
      ('Needle January third', DateTime(2025, 1, 3, 12)),
      ('Other January second', DateTime(2025, 1, 2, 12)),
      ('Needle previous year', DateTime(2024, 1, 2, 12)),
      ('Needle February second', DateTime(2025, 2, 2, 12)),
    ];
    try {
      for (final (index, record) in records.indexed) {
        await history.recordThread(
            _thread.copyWith(
              title: record.$1,
              url: 'http://127.0.0.1:8765/read.php?tid-${950301 + index}.html',
            ),
            viewedAt: record.$2);
      }
      await mountScreen(tester, BrowsingHistoryScreen(repository: repository));
      await waitFor(tester, find.text(records.first.$1));
      await tap(tester, find.byTooltip('搜索浏览历史'));
      final search = find.byType(TextField);
      await tester.enterText(search, 'Needle');
      await tester.pumpAndSettle();
      expect(find.text('Other January second'), findsNothing);
      for (final (dateKey, kept) in [
        (
          '年2025',
          {
            'Needle January second',
            'Needle January third',
            'Needle February second'
          }
        ),
        ('月1', {'Needle January second', 'Needle January third'}),
        ('日2', {'Needle January second'}),
      ]) {
        await tap(tester, find.byTooltip('按日期筛选'));
        await tap(tester, find.byKey(ValueKey('history-date:$dateKey')));
        await tap(tester, find.text('完成'));
        await tester.pumpAndSettle();
        for (final (title, _) in records) {
          expect(find.text(title),
              kept.contains(title) ? findsOneWidget : findsNothing,
              reason: '$dateKey with keyword must retain only $kept');
        }
      }
      await tap(tester, find.byTooltip('清除日期筛选'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller?.text, 'Needle');
      for (final (title, _) in records) {
        expect(find.text(title),
            title.startsWith('Needle') ? findsOneWidget : findsNothing);
      }
      await tester.enterText(search, '');
      await tester.pumpAndSettle();
      for (final (title, _) in records) {
        expect(find.text(title), findsOneWidget);
      }
      expect(await history.recent(), hasLength(5),
          reason: 'filtering reads retained records; it never deletes them');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await history.clear();
    }
  });
}
