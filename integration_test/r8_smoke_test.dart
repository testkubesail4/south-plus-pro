import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/board/board_thread_list_screen.dart';
import 'package:south_plus_rewrite/features/common/thread_row.dart';
import 'package:south_plus_rewrite/features/thread/thread_compose_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_rich_content.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_session_store.dart';
import 'package:south_plus_rewrite/services/user_note_store.dart';
import 'package:south_plus_rewrite/services/user_tag_store.dart';
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
const _category = ForumCategory(
  name: 'Synthetic requests',
  slug: 'f48',
  url: 'http://127.0.0.1:8765/thread.php?fid-48.html',
);
const _page2 = ForumThread(
  title: 'Synthetic bounty thread',
  url: 'http://127.0.0.1:8765/read.php?tid-960001-page-2.html',
  replies: 2,
  section: 'Synthetic requests',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late ForumRepository repository;

  Future<Map<String, dynamic>> fixture(String path,
      {bool reset = false}) async {
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
      return jsonDecode(await utf8.decoder.bind(response).join())
          as Map<String, dynamic>;
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

  Future<void> mount(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: screen));
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppThemeController.setMode(ThemeMode.light);
    await fixture('r8/reset', reset: true);
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

  testWidgets('cold page 2 keeps compact OP metadata without repeating body',
      (tester) async {
    await UserNoteStore.save('930001', 'Synthetic local note',
        account: repository.localPreferenceAccount);
    await UserTagStore.save('930001', ['Synthetic tag'],
        account: repository.localPreferenceAccount);
    await mount(
        tester, ThreadDetailScreen(repository: repository, thread: _page2));
    await waitFor(tester, find.text('Synthetic signature'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2026-01-03 09:20'), findsWidgets);
    expect(find.text('Synthetic tag'), findsOneWidget);
    expect(find.textContaining('Synthetic local note', findRichText: true),
        findsWidgets);
    expect(find.textContaining('Synthetic OP body', findRichText: true),
        findsNothing);
    final opImage = find.byWidgetPredicate((widget) =>
        widget is ThreadInlineImage && widget.image.url.endsWith('/r8-op.png'));
    expect(opImage, findsNothing);
    expect((await fixture('r8/stats'))['thread_pages'], [2, 1]);

    await tap(tester, find.text('第 2 / 2 页'));
    await tap(tester, find.text('首楼'));
    await waitFor(
        tester, find.textContaining('Synthetic OP body', findRichText: true));
    expect(opImage, findsOneWidget,
        reason: 'the same OP image renders only on the opening page');
    expect(find.text('SP币 +109'), findsOneWidget);
    expect(find.text('HP -10'), findsOneWidget);
    expect((await fixture('r8/stats'))['reward_attempts'], isEmpty);
  });

  testWidgets('request badges use native classic rows, not title-only wall',
      (tester) async {
    await mount(tester,
        BoardThreadListScreen(repository: repository, category: _category));
    await waitFor(tester, find.text('悬赏 30'));
    Finder row(String title) => find.ancestor(
        of: find.text(title), matching: find.byType(ForumThreadRow));
    expect(
        find.descendant(
            of: row('Synthetic bounty thread'), matching: find.text('悬赏 30')),
        findsOneWidget);
    expect(
        find.descendant(
            of: row('Synthetic ended bounty'),
            matching: find.textContaining('悬赏帖')),
        findsOneWidget);
    expect(
        find.descendant(
            of: row('Synthetic no amount'),
            matching: find.textContaining('悬赏')),
        findsNothing);
    expect(find.textContaining('已有答案'), findsNothing);
    expect(find.textContaining('悬赏已结束'), findsNothing,
        reason:
            'an amountless reward icon cannot distinguish expiry from settlement');
    expect((await fixture('r8/stats'))['thread_pages'], isEmpty,
        reason: 'list enrichment is one bounded classic GET, not thread reads');
  });

  testWidgets(
      'compose posts chosen classification and explicit confirmed costs',
      (tester) async {
    await mount(
        tester,
        Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => ThreadComposeScreen(
                                repository: repository, category: _category))),
                    child: const Text('Open composer')))));
    await tap(tester, find.text('Open composer'));
    await waitFor(tester, find.byKey(const ValueKey('compose-bounty-best')));
    await tap(tester, find.text('不分类'));
    await tap(tester, find.text('全年龄正常向').last);
    Finder field(String hint) => find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.hintText == hint);
    await tester.enterText(field('标题'), 'Synthetic compose');
    await tester.enterText(field('正文'), 'Synthetic body');
    await tester.enterText(
        find.byKey(const ValueKey('compose-bounty-best')), '25');
    await tester.enterText(
        find.byKey(const ValueKey('compose-bounty-helpful')), '12');
    await tester.pumpAndSettle();
    expect(find.textContaining('发布时预先扣除 62 SP币'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('compose-submit')));
    await waitFor(tester, find.text('发布悬赏帖？'));
    expect((await fixture('r8/stats'))['compose_attempts'], isEmpty,
        reason:
            'native defaults must not post before explicit cost confirmation');
    await tap(tester, find.text('取消'));
    expect((await fixture('r8/stats'))['compose_attempts'], isEmpty);
    await tap(tester, find.byKey(const ValueKey('compose-submit')));
    await tap(tester, find.text('确认发布并扣除 62 SP币'));
    await waitFor(tester, find.text('Open composer'));
    final attempts = (await fixture('r8/stats'))['compose_attempts'] as List;
    expect(attempts, hasLength(1));
    expect(attempts.single['p_type'], ['3']);
    expect(attempts.single['bonus[best]'], ['25']);
    expect(attempts.single['bonus[active]'], ['12']);
  });

  testWidgets('B2 helpful then B1 best stays uncertain until native readback',
      (tester) async {
    await mount(
        tester, ThreadDetailScreen(repository: repository, thread: _page2));
    const helpful = ValueKey('reward-helpful-960103');
    const best = ValueKey('reward-best-960102');
    await tap(tester, find.byKey(helpful));
    await waitFor(tester, find.text('给 B2F 热心助人？'));
    expect((await fixture('r8/stats'))['reward_attempts'], isEmpty);
    await tap(tester, find.text('取消'));
    expect((await fixture('r8/stats'))['reward_attempts'], isEmpty);
    await tap(tester, find.byKey(helpful));
    await tap(tester, find.text('确认，不可撤销'));
    await waitFor(tester, find.text('结果未确认'));
    expect((await fixture('r8/stats'))['reward_attempts'], hasLength(1));
    expect(find.text('已给出热心助人'), findsNothing,
        reason: 'unknown ACK must not be announced as success');
    await tap(tester, find.text('刷新'));
    await waitFor(tester, find.text('热心助人 +1 SP币'));
    expect(find.byKey(helpful), findsNothing);
    expect(find.byKey(const ValueKey('reward-best-960103')), findsNothing);
    expect(find.byKey(best), findsOneWidget);

    await tap(tester, find.byKey(best));
    await waitFor(tester, find.text('选 B1F 为最佳答案？'));
    await tap(tester, find.text('短消息通知对方'));
    await tap(tester, find.text('确认，不可撤销'));
    await waitFor(tester, find.text('结果未确认'));
    expect(find.text('已选为最佳答案'), findsNothing);
    await tap(tester, find.text('刷新'));
    await waitFor(tester, find.text('最佳答案 +20 SP币'));
    expect(find.text('热心助人 +1 SP币'), findsOneWidget);
    expect(find.byKey(best), findsNothing);
    expect(find.byKey(const ValueKey('reward-helpful-960102')), findsNothing);
    await tap(tester, find.text('第 2 / 2 页'));
    await tap(tester, find.text('首楼'));
    await waitFor(tester, find.text('悬赏已结束'));
    final stats = await fixture('r8/stats');
    expect(stats['awards'], {'960103': 'helpful', '960102': 'best'});
    final attempts = stats['reward_attempts'] as List;
    expect(attempts, hasLength(2), reason: 'unknown ACK never causes replay');
    expect(attempts[0]['pid'], ['960103']);
    expect(attempts[0]['type'], ['2']);
    expect(attempts[0]['ifmsg'], ['1']);
    expect(attempts[1]['pid'], ['960102']);
    expect(attempts[1]['type'], ['1']);
    expect(attempts[1]['ifmsg'], ['0']);
  });
}
