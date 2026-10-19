import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/favorite_threads_page.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_network_setup_store.dart';
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final output = Platform.environment['SPP_ARTIFACT_DIR'] ?? '/output';
  final frames = <Map<String, Object>>[];
  late ForumRepository repository;
  var dark = true;
  var scale = 2.0;
  var reduced = true;

  Future<List<int>> fixture(String path, {bool reset = false}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = _config.baseUri.resolve(path);
      expect(uri.host, '127.0.0.1');
      final request = await client.openUrl(reset ? 'POST' : 'GET', uri);
      request.headers.set('Cookie', 'appendfix_winduser=synthetic-local-only');
      if (reset) {
        final body = utf8.encode('fixture-only');
        request.contentLength = body.length;
        request.add(body);
      }
      final response = await request.close();
      expect(response.statusCode, 200, reason: path);
      return await response
          .fold<List<int>>([], (all, bytes) => all..addAll(bytes));
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> stats() async =>
      jsonDecode(utf8.decode(await fixture('appendfix/stats')))
          as Map<String, dynamic>;

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {ForumNetworkSetupStore.completedKey: true});
    await fixture('profile-board-tree/reset', reset: true);
    await ForumSessionStore().saveCookies({
      'appendfix_winduser': ForumStoredCookie.session(
        name: 'appendfix_winduser',
        value: 'synthetic-local-only',
        origin: _config.baseUri,
      ),
    });
    dark = true;
    scale = 2;
    reduced = true;
    await AppThemeController.setMode(ThemeMode.dark);
    repository = ForumRepository(config: _config);
    expect(await repository.restoreSession(), isTrue);
    expect(repository.accountIdentity.value?.uid, '930001');
  });

  Widget app(Widget home) => MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduced,
          ),
          child: child!,
        ),
        home: home,
      );

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsWidgets);
    expect(tester.takeException(), isNull);
  }

  Future<String> window(WidgetTester tester) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump();
      final result = await Process.run('xdotool',
          ['search', '--onlyvisible', '--name', r'^south_plus_rewrite$']);
      final ids = '${result.stdout}'.trim();
      if (result.exitCode == 0 && ids.isNotEmpty) return ids.split('\n').first;
      await tester.pump(const Duration(milliseconds: 100));
    }
    throw StateError('Native fixture window was not mapped');
  }

  Future<void> resize(WidgetTester tester, Size size) async {
    final result = await Process.run('xdotool', [
      'windowsize',
      await window(tester),
      '${size.width.toInt()}',
      '${size.height.toInt()}',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    await tester.pumpAndSettle();
    expect(tester.view.physicalSize / tester.view.devicePixelRatio, size);
  }

  Future<void> mount(WidgetTester tester, Widget home,
      {bool wide = false}) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app(home));
    await resize(tester, wide ? const Size(1100, 800) : const Size(400, 800));
  }

  Future<void> reveal(WidgetTester tester, Finder finder,
      {double alignment = 0.35}) async {
    await waitFor(tester, finder);
    for (var attempt = 0; attempt < 30; attempt++) {
      await Scrollable.ensureVisible(tester.element(finder.first),
          alignment: alignment);
      await tester.pump();
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      if ((Offset.zero & size).contains(tester.getCenter(finder.first)) &&
          finder.first.hitTestable().evaluate().isNotEmpty) return;
      await tester.pump(const Duration(milliseconds: 100));
    }
    fail('$finder did not become laid out and hit-testable');
  }

  Future<void> tap(WidgetTester tester, Finder finder,
      {bool settle = true}) async {
    await reveal(tester, finder);
    await tester.tap(finder.first);
    if (settle) await tester.pumpAndSettle();
    await tester.pump();
  }

  Future<void> dismissTransient(WidgetTester tester) async {
    final snackbar = find.byType(SnackBar);
    if (snackbar.evaluate().isEmpty) return;
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
        .hideCurrentSnackBar();
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (
        snackbar.evaluate().isNotEmpty && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(snackbar, findsNothing);
  }

  Future<void> modalReady(WidgetTester tester, Finder finder) async {
    await reveal(tester, finder);
    final route = ModalRoute.of(tester.element(finder.first))!;
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (route.animation?.isCompleted == false &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(route.animation?.isCompleted ?? true, isTrue);
    expect(finder.first.hitTestable(), findsOneWidget);
  }

  Future<void> enter(WidgetTester tester, Finder field, String text,
      {bool settle = true}) async {
    await dismissTransient(tester);
    await reveal(tester, field);
    await tester.tap(field);
    await tester.pump();
    await tester.showKeyboard(field);
    final editable =
        find.descendant(of: field, matching: find.byType(EditableText));
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!tester.widget<EditableText>(editable).focusNode.hasFocus &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
    await tester.enterText(field, text);
    if (settle) await tester.pumpAndSettle();
    await tester.pump();
    expect(tester.widget<TextField>(field).controller?.text, text,
        reason:
            'native input must reach the intended field, focus=${FocusManager.instance.primaryFocus}');
  }

  void fullyVisible(WidgetTester tester, Finder finder) {
    final bounds = tester.getRect(finder.first);
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final bars = find.byType(AppBar);
    final top =
        bars.evaluate().isEmpty ? 0.0 : tester.getBottomLeft(bars.first).dy;
    expect(
        bounds.left >= 0 &&
            bounds.right <= size.width &&
            bounds.top >= top &&
            bounds.bottom <= size.height,
        isTrue,
        reason: '$finder must be completely visible: $bounds in $size');
    expect(finder.first.hitTestable(), findsOneWidget);
  }

  Future<void> screenshot(WidgetTester tester, String name,
      {bool settle = true}) async {
    if (settle) await tester.pumpAndSettle();
    await tester.pump();
    expect(tester.takeException(), isNull, reason: name);
    final path = '$output/$name.png';
    final result =
        await Process.run('import', ['-window', await window(tester), path]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(File(path).lengthSync(), greaterThan(1000));
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    frames.add({
      'name': name,
      'path': path,
      'width': size.width.toInt(),
      'height': size.height.toInt(),
      'theme': dark ? 'dark' : 'light',
      'textScale': scale,
      'reducedMotion': reduced,
    });
    File('$output/collections-profile-frames.json')
        .writeAsStringSync(jsonEncode({
      'scope':
          'Synthetic loopback native app only; raw fixture attempts and fresh HTTP readback are separate assertions',
      'frames': frames,
    }));
  }

  Future<void> openBoardFilter(WidgetTester tester, String label) async {
    // The selectors sit folded behind the toolbar until opened once.
    if (find.text(label).evaluate().isEmpty) {
      await tap(tester, find.byTooltip('展开筛选'));
    }
    await tap(tester, find.text(label));
    await waitFor(tester, find.byKey(const ValueKey('board-filter:all')));
    final loading = find.text('正在加载版块层级…');
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (loading.evaluate().isNotEmpty && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(loading, findsNothing,
        reason:
            'the real homepage hierarchy must finish before choosing a board');
  }

  Future<void> dismissBoardSheet(WidgetTester tester) async {
    final top = tester.getTopLeft(find.byType(BottomSheet).last).dy;
    expect(top, greaterThan(0));
    await tester.tapAt(Offset(20, top / 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('board-filter:all')), findsNothing);
  }

  int contentReads(Map<String, dynamic> value) => (value['reads'] as List)
      .where((read) =>
          read['path'] == '/u.php' &&
          ('${read['query']}'.contains('action-topic-') ||
              '${read['query']}'.contains('action-post-')))
      .length;

  testWidgets(
      'native profile board tree folds without selecting and keeps topic reply filters independent',
      (tester) async {
    debugPrint('COLLECTIONS_PROFILE board tree start');
    final profile = UserProfileScreen(
      userUrl: 'http://127.0.0.1:8765/u.php?action-show-uid-930002.html',
      repository: repository,
      initialTab: UserProfileTab.topics,
    );
    await tester.pumpWidget(app(profile));
    await resize(tester, const Size(400, 800));
    await waitFor(tester, find.text('CM108 父版主题'));
    expect(find.text('CM108 子版主题'), findsOneWidget);
    expect(find.text('CM107 子版主题'), findsOneWidget);
    final beforeFold = contentReads(await stats());
    await openBoardFilter(tester, '版块：全部');
    final section = find.widgetWithText(ListTile, '同人展会');
    await waitFor(tester, section);
    expect(find.byKey(const ValueKey('board-filter-group:229')), findsNothing);
    await tap(tester, section);
    expect(find.byKey(const ValueKey('board-filter:230')), findsNothing);
    await tap(tester, find.byKey(const ValueKey('board-filter-group:229')));
    expect(find.text('仅筛选 CM108'), findsOneWidget);
    expect(find.text('不含子版块'), findsOneWidget);
    expect(find.byKey(const ValueKey('board-filter:230')), findsOneWidget);
    expect(find.byKey(const ValueKey('board-filter:227')), findsNothing);
    expect(find.text('未授权子版'), findsNothing,
        reason:
            'homepage hierarchy must not grant an unavailable search scope');
    await reveal(tester, find.byKey(const ValueKey('board-filter-group:229')),
        alignment: 0.15);
    for (final key in [
      'board-filter-group:229',
      'board-filter:229',
      'board-filter:230',
      'board-filter-group:226'
    ]) {
      fullyVisible(tester, find.byKey(ValueKey(key)));
    }
    await screenshot(tester, 'profile_boards_phone-dark2_nested-tree');
    await dismissBoardSheet(tester);
    expect(find.text('版块：全部'), findsOneWidget);
    expect(contentReads(await stats()), beforeFold,
        reason: 'folding and cancelling do not start a content query');
    expect((await stats())['attempts'], isEmpty);

    await openBoardFilter(tester, '版块：全部');
    await tap(tester, section);
    await tap(tester, find.byKey(const ValueKey('board-filter-group:229')));
    await tap(tester, find.byKey(const ValueKey('board-filter:229')));
    await waitFor(tester, find.text('版块：CM108'));
    await waitFor(tester, find.text('CM108 父版主题'));
    for (final excluded in ['CM108 子版主题', 'CM107 父版主题', 'CM107 子版主题']) {
      expect(find.text(excluded), findsNothing,
          reason:
              'parent FID229 selects only that board, not descendant FID230');
    }

    await openBoardFilter(tester, '版块：CM108');
    await waitFor(tester, find.byKey(const ValueKey('board-filter-group:229')));
    await tap(tester, find.byKey(const ValueKey('board-filter-group:229')));
    final search = find.byWidgetPredicate((widget) =>
        widget is TextField && widget.decoration?.labelText == '筛选版块');
    await enter(tester, search, '同人志');
    for (final (id, parent) in [('230', 'CM108'), ('227', 'CM107')]) {
      final row = find.byKey(ValueKey('board-filter:$id'));
      expect(find.descendant(of: row, matching: find.text('同人志&CG')),
          findsOneWidget);
      expect(find.descendant(of: row, matching: find.text(parent)),
          findsOneWidget);
      fullyVisible(tester, row);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await screenshot(tester, 'profile_boards_phone-dark2_search-context');
    await enter(tester, search, '');
    expect(find.byKey(const ValueKey('board-filter:230')), findsOneWidget);
    expect(find.byKey(const ValueKey('board-filter:227')), findsNothing,
        reason: 'clearing search restores the local fold state');
    await enter(tester, search, '同人志');
    await tap(tester, find.byKey(const ValueKey('board-filter:230')));
    await waitFor(tester, find.text('版块：CM108 / 同人志&CG'));
    await waitFor(tester, find.text('CM108 子版主题'));
    expect(find.text('CM108 父版主题'), findsNothing);
    expect(find.text('CM107 子版主题'), findsNothing);
    await openBoardFilter(tester, '版块：CM108 / 同人志&CG');
    await waitFor(tester, find.byKey(const ValueKey('board-filter:230')));
    expect(find.byKey(const ValueKey('board-filter:227')), findsNothing,
        reason: 'only the selected child ancestors reopen automatically');
    await dismissBoardSheet(tester);

    await tap(tester, find.widgetWithText(Tab, '回复'));
    await waitFor(tester, find.text('版块：全部'));
    await waitFor(tester, find.text('CM108 子版回复'));
    await openBoardFilter(tester, '版块：全部');
    await tap(tester, section);
    await tap(tester, find.byKey(const ValueKey('board-filter-group:226')));
    await tap(tester, find.byKey(const ValueKey('board-filter:227')));
    await waitFor(tester, find.text('版块：CM107 / 同人志&CG'));
    await waitFor(tester, find.text('CM107 子版回复'));
    expect(find.text('CM108 子版回复'), findsNothing);
    expect(find.text('CM107 父版回复'), findsNothing);
    await tap(tester, find.widgetWithText(Tab, '主题'));
    await waitFor(tester, find.text('版块：CM108 / 同人志&CG'));
    expect(find.text('CM108 子版主题'), findsOneWidget);
    await tap(tester, find.widgetWithText(Tab, '回复'));
    await waitFor(tester, find.text('版块：CM107 / 同人志&CG'));
    await openBoardFilter(tester, '版块：CM107 / 同人志&CG');
    await tap(tester, find.byKey(const ValueKey('board-filter:all')));
    await waitFor(tester, find.text('版块：全部'));
    expect(find.text('CM108 子版回复'), findsOneWidget);
    expect(find.text('CM107 子版回复'), findsOneWidget);
    await tap(tester, find.widgetWithText(Tab, '主题'));
    await waitFor(tester, find.text('版块：CM108 / 同人志&CG'));

    final profileState = tester.state(find.byType(UserProfileScreen));
    dark = false;
    scale = 1;
    reduced = false;
    await AppThemeController.setMode(ThemeMode.light);
    try {
      await tester.pumpWidget(app(UserProfileScreen(
        key: profile.key,
        userUrl: profile.userUrl,
        repository: profile.repository,
        initialTab: profile.initialTab,
      )));
      await resize(tester, const Size(1100, 800));
      expect(
          identical(tester.state(find.byType(UserProfileScreen)), profileState),
          isTrue,
          reason:
              'the fresh root must rebuild without replacing the profile filter state');
      expect(AppThemeController.themeMode, ThemeMode.light);
      expect(
          Theme.of(tester.element(find.byType(UserProfileScreen))).brightness,
          Brightness.light);
      final profileScaffold = find
          .descendant(
              of: find.byType(UserProfileScreen),
              matching: find.byType(Scaffold))
          .first;
      expect(tester.widget<Scaffold>(profileScaffold).backgroundColor,
          AppColors.lightPalette.background);
      expect(find.text('版块：CM108 / 同人志&CG'), findsOneWidget);
      expect(find.text('CM108 子版主题'), findsOneWidget);
      expect(find.text('CM108 父版主题'), findsNothing);
      expect(find.text('CM107 子版主题'), findsNothing);
      await reveal(tester, find.text('版块：CM108 / 同人志&CG'), alignment: 0.3);
      fullyVisible(tester, find.text('版块：CM108 / 同人志&CG'));
      fullyVisible(tester, find.text('CM108 子版主题'));
      await screenshot(tester, 'profile_boards_wide-light_independent-filters');
      final after = await stats();
      expect(after['writes'], isEmpty);
      expect(after['attempts'], isEmpty,
          reason: 'all profile filters are read-only');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await AppThemeController.setMode(ThemeMode.dark);
    }
    debugPrint('COLLECTIONS_PROFILE board tree complete');
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets(
      'native collections browse create cancel move by fresh name and delete without losing favorites',
      (tester) async {
    debugPrint('COLLECTIONS_PROFILE collection CRUD start');
    await fixture('favorite-collections/reset', reset: true);
    const createdName = '下次继续阅读的收藏分类';
    const thread = ForumThread(
      title: '本地阅读笔记',
      url: 'http://127.0.0.1:8765/read.php?tid-930002.html',
      replies: 0,
      section: '本地阅读版块',
    );
    try {
      await mount(
          tester, ThreadDetailScreen(repository: repository, thread: thread));
      await tap(tester, find.text('收藏'), settle: false);
      final newCategory = find.byKey(const ValueKey('favorite-category-new'));
      await modalReady(tester, newCategory);
      expect((await stats())['attempts'], isEmpty,
          reason: 'browsing categories is not a favorite write');
      fullyVisible(tester, find.byKey(const ValueKey('favorite-category:0')));
      fullyVisible(tester, find.byKey(const ValueKey('favorite-category:2')));
      await screenshot(tester, 'collections_phone-dark2_read-only-chooser',
          settle: false);
      await tap(tester, newCategory, settle: false);
      final nameField = find.byKey(const ValueKey('favorite-category-name'));
      await modalReady(tester, nameField);
      expect(tester.widget<TextField>(nameField).maxLength, isNull,
          reason: 'native size=6 is not maxlength');
      await enter(tester, nameField, createdName, settle: false);
      await tap(tester, find.widgetWithText(TextButton, '取消'), settle: false);
      await modalReady(tester, newCategory);
      expect((await stats())['attempts'], isEmpty,
          reason: 'cancelling the name dialog sends nothing');
      await tap(tester, newCategory, settle: false);
      await modalReady(tester, nameField);
      await enter(tester, nameField, createdName, settle: false);
      await tap(tester, find.byKey(const ValueKey('favorite-category-create')),
          settle: false);
      await modalReady(
          tester, find.byKey(const ValueKey('favorite-category:3')));
      final created = await stats();
      expect(created['writes'], ['addtype']);
      expect(
          created['favorites'], {'940001': '0', '940002': '0', '940003': '1'});
      final createAttempts = created['attempts'] as List;
      expect(createAttempts, hasLength(1));
      expect(createAttempts.single['method'], 'POST');
      expect(createAttempts.single['fields'], {
        'verify': ['fixture-only'],
        'job': ['addtype'],
        'type': [createdName]
      });
      await dismissTransient(tester);
      await tap(tester, find.byKey(const ValueKey('favorite-category-cancel')),
          settle: false);
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (find
              .byKey(const ValueKey('favorite-category-cancel'))
              .evaluate()
              .isNotEmpty &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
          find.byKey(const ValueKey('favorite-category-cancel')), findsNothing);
      expect((await stats())['attempts'], hasLength(1),
          reason: 'category creation survives cancel, but no favorite is sent');
      expect(find.text('已收藏'), findsNothing);
      await tap(tester, find.text('收藏'), settle: false);
      await modalReady(
          tester, find.byKey(const ValueKey('favorite-category:3')));
      await tap(tester, find.byKey(const ValueKey('favorite-category:3')),
          settle: false);
      await waitFor(tester, find.text('已收藏'));
      final favorited = await stats();
      expect(favorited['writes'], ['addtype', 'favor']);
      final addAttempts = favorited['attempts'] as List;
      expect(addAttempts, hasLength(2));
      expect(addAttempts.last['path'], '/pw_ajax.php');
      expect(addAttempts.last['query']['type'], ['3']);
      expect((addAttempts.last['query'] as Map).keys,
          unorderedEquals(['action', 'tid', 'type', 'nowtime', 'verify']));
      expect(utf8.decode(await fixture('u.php?action=favor&type=3')),
          contains('value="930002"'));
      expect(utf8.decode(await fixture('u.php?action=favor&type=0')),
          isNot(contains('value="930002"')));

      await mount(
          tester, Scaffold(body: FavoriteThreadsPage(repository: repository)));
      final first = find.byKey(const ValueKey('favorite-row:940001'));
      await waitFor(tester, first);
      await tap(
          tester, find.descendant(of: first, matching: find.byTooltip('更多')));
      await tap(tester, find.text('移动到…'));
      final staleDestination = find.byKey(const ValueKey('favorite-move-to:2'));
      await modalReady(tester, staleDestination);
      expect(find.descendant(of: staleDestination, matching: find.text('长期收藏')),
          findsOneWidget);
      await fixture('favorite-collections/external-delete-first', reset: true);
      final shifted = await stats();
      expect(shifted['categories'], [
        {'id': '0', 'label': '默认分类'},
        {'id': '1', 'label': '长期收藏'},
        {'id': '2', 'label': createdName},
      ]);
      fullyVisible(tester, staleDestination);
      await screenshot(
          tester, 'collections_phone-dark2_stale-destination-intent');
      await tap(tester, staleDestination);
      await waitFor(tester, find.textContaining('已移动 1 个'));
      final moved = await stats();
      final moves = (moved['attempts'] as List)
          .where((attempt) =>
              attempt['method'] == 'POST' &&
              attempt['path'] == '/u.php' &&
              (attempt['fields']['job'] as List).single == 'change')
          .toList();
      expect(moves, hasLength(1));
      expect(moves.single['fields']['type'], ['1'],
          reason:
              'old id2 now names another category and must never be dispatched');
      expect(moves.single['fields']['selid[]'], ['940001']);
      expect(utf8.decode(await fixture('u.php?action=favor&type=1')),
          contains('value="940001"'));
      expect(utf8.decode(await fixture('u.php?action=favor&type=2')),
          isNot(contains('value="940001"')));
      expect(moved['favorites']['940003'], '0',
          reason: 'external nonempty deletion keeps favorites in default');
      await dismissTransient(tester);
      await tap(tester, find.byKey(const ValueKey('favorite-manage')));
      expect(
          find.byKey(const ValueKey('favorite-folder-delete:0')), findsNothing);
      await tap(tester, find.byKey(const ValueKey('favorite-folder-delete:2')));
      final effect = find.text('其中的主题会移到默认分类。');
      await modalReady(tester, effect);
      fullyVisible(tester, effect);
      fullyVisible(tester, find.text('删除分类「$createdName」？'));
      await screenshot(
          tester, 'collections_phone-dark2_delete-nonempty-confirm');
      await tap(tester, find.widgetWithText(TextButton, '保留'));
      expect((await stats())['attempts'], hasLength(3),
          reason: 'keeping a category must send no delete request');
      expect((await stats())['favorites']['930002'], '2');
      await tap(tester, find.byKey(const ValueKey('favorite-manage')));
      await tap(tester, find.byKey(const ValueKey('favorite-folder-delete:2')));
      await tap(tester, find.widgetWithText(FilledButton, '删除'));
      await waitFor(tester, find.textContaining('已删除分类'));
      final deleted = await stats();
      expect(deleted['categories'], [
        {'id': '0', 'label': '默认分类'},
        {'id': '1', 'label': '长期收藏'}
      ]);
      expect(deleted['favorites'],
          {'930002': '0', '940001': '1', '940002': '0', '940003': '0'});
      expect(deleted['writes'], ['addtype', 'favor', 'change', 'deltype']);
      expect(deleted['attempts'], hasLength(4));
      expect(utf8.decode(await fixture('u.php?action=favor&type=0')),
          contains('value="930002"'));
      expect(utf8.decode(await fixture('u.php?action=favor&type=1')),
          contains('value="940001"'));
      expect(find.byKey(const ValueKey('favorite-folder:2')), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
    debugPrint('COLLECTIONS_PROFILE collection CRUD complete');
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets(
      'native collection batch keeps only unfinished selection and never selects an unloaded page',
      (tester) async {
    debugPrint('COLLECTIONS_PROFILE batch start');
    await fixture('favorite-collections/reset', reset: true);
    try {
      await mount(
          tester, Scaffold(body: FavoriteThreadsPage(repository: repository)));
      await waitFor(tester, find.byKey(const ValueKey('favorite-row:940001')));
      await tap(tester, find.byKey(const ValueKey('favorite-select-start')));
      expect(
          tester
              .widget<OutlinedButton>(
                  find.byKey(const ValueKey('favorite-move')))
              .onPressed,
          isNull);
      for (final id in ['940001', '940002']) {
        await tap(tester, find.byKey(ValueKey('favorite-select:$id')));
      }
      await waitFor(tester, find.text('已选 2 个'));
      await reveal(tester, find.text('已选 2 个'), alignment: 0.1);
      for (final key in [
        'favorite-select:940001',
        'favorite-select:940002',
        'favorite-move',
        'favorite-remove-selected'
      ]) {
        fullyVisible(tester, find.byKey(ValueKey(key)));
      }
      await screenshot(tester, 'collections_phone-dark2_multi-select');
      await tap(tester, find.byKey(const ValueKey('favorite-move')));
      await tap(tester, find.byKey(const ValueKey('favorite-move-cancel')));
      expect((await stats())['attempts'], isEmpty);
      expect(
          tester
              .widget<Checkbox>(
                  find.byKey(const ValueKey('favorite-select:940001')))
              .value,
          isTrue);
      expect(
          tester
              .widget<Checkbox>(
                  find.byKey(const ValueKey('favorite-select:940002')))
              .value,
          isTrue);
      await fixture('favorite-collections/partial-next', reset: true);
      await tap(tester, find.byKey(const ValueKey('favorite-move')));
      await tap(tester, find.byKey(const ValueKey('favorite-move-to:2')));
      await waitFor(tester, find.text('已选 1 个'));
      expect(
          tester
              .widget<Checkbox>(
                  find.byKey(const ValueKey('favorite-select:940001')))
              .value,
          isFalse);
      expect(
          tester
              .widget<Checkbox>(
                  find.byKey(const ValueKey('favorite-select:940002')))
              .value,
          isTrue);
      final partial = await stats();
      expect(partial['favorites']['940001'], '2');
      expect(partial['favorites']['940002'], '0');
      expect(partial['attempts'], hasLength(1));
      expect(partial['attempts'][0]['fields']['selid[]'], ['940001', '940002']);
      await dismissTransient(tester);
      await fixture('favorite-collections/unknown-ack-next', reset: true);
      await tap(tester, find.byKey(const ValueKey('favorite-move')));
      await tap(tester, find.byKey(const ValueKey('favorite-move-to:2')));
      await waitFor(tester, find.textContaining('已移动 1 个'));
      final retried = await stats();
      expect(retried['attempts'], hasLength(2));
      expect(retried['attempts'][1]['fields']['selid[]'], ['940002'],
          reason: 'explicit retry must not repeat the already-moved row');
      expect(utf8.decode(await fixture('u.php?action=favor&type=2')),
          contains('value="940002"'));
      await dismissTransient(tester);
      await tap(tester, find.byKey(const ValueKey('favorite-folder:2')));
      await tap(tester, find.byKey(const ValueKey('favorite-select-start')));
      await tap(tester, find.byKey(const ValueKey('favorite-select-all')));
      await waitFor(tester, find.text('已选 2 个'));
      await tap(tester, find.byKey(const ValueKey('favorite-remove-selected')));
      await tap(tester, find.widgetWithText(TextButton, '保留'));
      expect((await stats())['attempts'], hasLength(2));
      await tap(tester, find.byKey(const ValueKey('favorite-remove-selected')));
      await tap(tester, find.widgetWithText(FilledButton, '取消收藏').last);
      await waitFor(tester, find.text('已取消收藏 2 个'));
      final removed = await stats();
      expect(removed['favorites'], {'940003': '1'});
      expect(removed['attempts'], hasLength(3));
      expect(removed['attempts'][2]['fields']['job'], ['clear']);
      expect(removed['attempts'][2]['fields']['selid[]'], ['940001', '940002']);
      expect(utf8.decode(await fixture('u.php?action=favor')),
          isNot(contains('value="940001"')));
      debugPrint('COLLECTIONS_PROFILE batch confirmed and partial complete');

      await tester.pumpWidget(const SizedBox.shrink());
      await fixture('favorite-collections/paged-reset', reset: true);
      dark = false;
      scale = 1;
      reduced = false;
      await AppThemeController.setMode(ThemeMode.light);
      await mount(
          tester, Scaffold(body: FavoriteThreadsPage(repository: repository)),
          wide: true);
      await waitFor(tester, find.byKey(const ValueKey('favorite-row:940001')));
      await tap(tester, find.byKey(const ValueKey('favorite-folder:0')));
      await waitFor(tester, find.byKey(const ValueKey('favorite-row:940001')));
      final selectStart = find.byKey(const ValueKey('favorite-select-start'));
      final loadedDeadline = DateTime.now().add(const Duration(seconds: 25));
      while ((selectStart.evaluate().isEmpty ||
              tester.widget<TextButton>(selectStart).onPressed == null) &&
          DateTime.now().isBefore(loadedDeadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.widget<TextButton>(selectStart).onPressed, isNotNull,
          reason:
              'the requested category must finish loading before its pager is checked');
      expect(
          tester
              .widget<ChoiceChip>(
                  find.byKey(const ValueKey('favorite-folder:0')))
              .selected,
          isTrue);
      if (find.textContaining('第 1/2 页').evaluate().isEmpty) {
        final page = utf8.decode(await fixture('u.php?action=favor&type=0'));
        debugPrint('PAGED_VIEW_DIAGNOSTIC ${jsonEncode({
              'text': tester
                  .widgetList<Text>(find.byType(Text))
                  .map((text) => text.data)
                  .take(30)
                  .toList(),
              'selectedFolders': [
                for (final chip in tester
                    .widgetList<ChoiceChip>(find.byType(ChoiceChip))
                    .take(8))
                  {
                    'key': '${chip.key}',
                    'selected': chip.selected,
                    'label':
                        chip.label is Text ? (chip.label as Text).data : null,
                  }
              ],
              'selectEnabled':
                  tester.widget<TextButton>(selectStart).onPressed != null,
              'fixturePager':
                  RegExp(r'<li class="pagesone">(.*?)</li>', dotAll: true)
                      .firstMatch(page)
                      ?.group(0),
            })}');
        final result = await Process.run('import', [
          '-window',
          await window(tester),
          '$output/failure_batch-pager.png',
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
      }
      expect(find.textContaining('第 1/2 页'), findsOneWidget);
      expect(find.byKey(const ValueKey('favorite-row:940005')), findsNothing);
      await tap(tester, find.byKey(const ValueKey('favorite-select-start')));
      await tap(tester, find.byKey(const ValueKey('favorite-select-all')));
      await waitFor(tester, find.text('已选 4 个'));
      await tap(tester, find.byKey(const ValueKey('favorite-move')));
      await tap(tester, find.byKey(const ValueKey('favorite-move-to:2')));
      await waitFor(tester, find.byKey(const ValueKey('favorite-row:940005')));
      final loadedOnly = await stats();
      expect(loadedOnly['attempts'], hasLength(1));
      expect(loadedOnly['attempts'][0]['fields']['selid[]'],
          ['940001', '940002', '940003', '940004']);
      expect(loadedOnly['favorites']['940005'], '0',
          reason: 'an off-page favorite was not selected or moved');
      await dismissTransient(tester);
      await tap(tester, find.byKey(const ValueKey('favorite-select-start')));
      await tap(tester, find.byKey(const ValueKey('favorite-select:940005')));
      await tap(tester, find.byKey(const ValueKey('favorite-remove-selected')));
      await tap(tester, find.widgetWithText(FilledButton, '取消收藏').last);
      final uncertain = find.byKey(const ValueKey('favorite-unconfirmed'));
      await waitFor(tester, uncertain);
      await dismissTransient(tester);
      expect(
          tester
              .widget<TextButton>(
                  find.byKey(const ValueKey('favorite-select-start')))
              .onPressed,
          isNull);
      expect(
          tester
              .widget<ActionChip>(find.byKey(const ValueKey('favorite-manage')))
              .onPressed,
          isNull);
      await reveal(tester, uncertain, alignment: 0.2);
      fullyVisible(tester, uncertain);
      fullyVisible(tester, find.byKey(const ValueKey('favorite-refresh')));
      await screenshot(tester, 'collections_wide-light_unknown-readback');
      final beforeRefresh = await stats();
      expect(beforeRefresh['attempts'], hasLength(2));
      expect(beforeRefresh['attempts'][1]['fields']['selid[]'], ['940005']);
      expect(beforeRefresh['favorites'].containsKey('940005'), isFalse);
      expect(utf8.decode(await fixture('u.php?action=favor')),
          contains('Pages: 1/2'),
          reason: 'incomplete ALL-page absence cannot prove removal');
      await tap(tester, find.byKey(const ValueKey('favorite-refresh')));
      final refreshedRow = find.byKey(const ValueKey('favorite-row:940001'));
      final refreshedDeadline = DateTime.now().add(const Duration(seconds: 25));
      while ((uncertain.evaluate().isNotEmpty ||
              refreshedRow.evaluate().isEmpty ||
              selectStart.evaluate().isEmpty ||
              tester.widget<TextButton>(selectStart).onPressed == null) &&
          DateTime.now().isBefore(refreshedDeadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(refreshedRow, findsOneWidget);
      expect(uncertain, findsNothing);
      expect(tester.widget<TextButton>(selectStart).onPressed, isNotNull);
      expect((await stats())['attempts'], hasLength(2),
          reason: 'refresh reconciles without replaying a write');
      await tap(tester, find.byKey(const ValueKey('favorite-folder:0')));
      await waitFor(tester, find.text('这个分类还没有主题'));
      expect(utf8.decode(await fixture('u.php?action=favor&page=2')),
          contains('value="940006"'));
      expect((await stats())['writes'], ['change', 'clear']);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await AppThemeController.setMode(ThemeMode.dark);
    }
    debugPrint('COLLECTIONS_PROFILE batch complete');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
