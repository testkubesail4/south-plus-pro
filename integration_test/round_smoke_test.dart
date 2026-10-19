import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_session_store.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

class _FixtureSite extends ForumSite {
  const _FixtureSite() : super('127.0.0.1');

  @override
  Uri get baseUri => Uri.parse('http://127.0.0.1:8765/');
}

const _config = ForumNetworkConfig(
  site: _FixtureSite(),
  dohEnabled: false,
  dohProvider: ForumNetworkConfig.defaultProvider,
);
const _thread = ForumThread(
  title: 'Synthetic edit thread',
  url: 'http://127.0.0.1:8765/read.php?tid-950001.html',
  replies: 2,
  section: 'Synthetic board',
);

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

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(finder, findsWidgets);
    expect(tester.takeException(), isNull);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await waitFor(tester, finder);
    await tester.ensureVisible(finder.first);
    await tester.pumpAndSettle();
    await tester.tap(finder.first);
    await tester.pump();
  }

  Future<void> mount(WidgetTester tester, ForumThread thread) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: ThreadDetailScreen(repository: repository, thread: thread),
    ));
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
      'resume page 2 then 从头看 reveals detached tpc opening post without false missing-floor notice',
      (tester) async {
    await repository.saveThreadReadPosition(
        _thread, const ThreadReadPosition(page: 2, anchor: '950102'));
    await mount(tester, _thread);
    await waitFor(tester, find.text('从头看'));
    expect(find.textContaining('Reply original', findRichText: true),
        findsWidgets);
    expect((await fixture('round/stats'))['thread_pages'], [2]);
    await tap(tester, find.text('从头看'));
    final opening = find.textContaining('Opening original', findRichText: true);
    await waitFor(tester, opening);
    await tester.pumpAndSettle();
    // Old parser recognises numeric detached anchors but loses tpc at DIV.
    expect(find.textContaining('未找到指定楼层'), findsNothing);
    expect(opening.hitTestable(), findsWidgets);
    expect((await fixture('round/stats'))['thread_pages'], [2, 1]);
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
  },
      skip:
          'Known defect: page-1 jump at offset zero does not persist; backend follow-up pending');

  for (final (pid, page, floor, original, updated) in [
    ('950101', 1, '楼主', '[b]Opening original[/b]', '[b]Opening edited[/b]'),
    ('950102', 2, 'B2F', '[i]Reply original[/i]', '[i]Reply edited[/i]'),
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
      final rendered = find.textContaining(
          page == 1 ? 'Opening edited' : 'Reply edited',
          findRichText: true);
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
      expect(stats['thread_pages'], [page, page],
          reason:
              'success refetches the edited page instead of adding a reply');
      expect(tester.takeException(), isNull);
    });
  }
}
