import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/favorite_threads_page.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

import 'support/native_favorite_fixture.dart';

Future<void> _open(
    WidgetTester tester, NativeFavoriteClient client, LoadingMode mode) async {
  SharedPreferences.setMockInitialValues(
      {'settings.loading.favorites': mode.name});
  await LoadingPreferences.load();
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = ForumRepository(client: client);
  addTearDown(repository.clearSession);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: FavoriteThreadsPage(repository: repository)),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'a later-page move companion rebinds native selection and restores its category page',
      (tester) async {
    final client = NativeFavoriteClient()
      ..categories = ['资料']
      ..pageCount = 3
      ..rows = [
        (id: '101', tid: '701', category: '资料'),
        (id: '205', tid: '702', category: '资料'),
        (id: '305', tid: '703', category: '资料'),
      ];
    final reads = <(int, int, String?)>[];
    client.pageTransform = (_) {
      final uri = client.reads.last;
      final page = int.tryParse(uri.queryParameters['page'] ?? '') ?? 1;
      reads.add((page, client.writes.length, uri.queryParameters['type']));
      return nativeFavoriteHtml(
        categories: client.categories,
        rows: client.rows
            .where((row) => int.parse(row.id) ~/ 100 == page)
            .toList(),
        token: 'token-${client.tokenNumber}',
        filter: uri.queryParameters['type'],
        page: page,
        pageCount: 3,
      );
    };
    await _open(tester, client, LoadingMode.manual);
    Future<void> tap(String key) => _tap(tester, find.byKey(ValueKey(key)));

    await tap('favorite-folder:1');
    await tap('page-end-next');
    await tap('page-end-next');
    expect(find.text('Synthetic 703'), findsOneWidget);
    expect(find.textContaining('第 3/3 页'), findsWidgets);
    expect(reads.where((read) => read.$1 == 3 && read.$3 == '1'), isNotEmpty);
    await tap('favorite-select-start');
    await tap('favorite-select:305');
    await tap('favorite-move');
    await tap('favorite-move-new');
    await tester.enterText(
        find.byKey(const ValueKey('favorite-category-name')), '新目标');
    await tester.pump();
    await tap('favorite-category-create');

    expect(client.writes, hasLength(1));
    expect(Map.fromEntries(client.writes.single.$2)['job'], 'addtype');
    expect(find.text('部分所选主题不在当前页，请重新选择'), findsNothing);
    expect(find.byKey(const ValueKey('favorite-move-to:2')), findsOneWidget,
        reason: 'Creating a category must return to the pending move');
    expect(find.text('已选 1 个'), findsOneWidget);
    await tap('favorite-move-cancel');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Checkbox>(find.byKey(const ValueKey('favorite-select:305')))
            .value,
        isTrue);
    expect(
        reads.where((read) => read.$1 == 3 && read.$2 == 1 && read.$3 == '1'),
        isNotEmpty,
        reason:
            'The selection must be rebound from a new native category page');
    await tap('favorite-select-exit');
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('favorite-folder:1')))
            .selected,
        isTrue);
    expect(find.textContaining('第 3/3 页'), findsWidgets);
    await tap('favorite-select-start');
    await tap('favorite-select:305');
    await tap('favorite-move');
    await tap('favorite-move-to:2');
    expect(client.writes, hasLength(2));
    final fields = Map.fromEntries(client.writes.last.$2);
    expect(fields['job'], 'change');
    expect(fields['selid[]'], '305');
    expect(fields['type'], '2');
    expect(client.rows.singleWhere((row) => row.id == '305').category, '新目标');
    expect(tester.takeException(), isNull);
    debugPrint('FAVORITE_COMPANION nativeReads=$reads writes='
        '${client.writes.map((write) => write.$2).toList()}');
  });

  testWidgets(
      'a visible category name never changes intent across native pages',
      (tester) async {
    final client = NativeFavoriteClient()
      ..categories = ['A', 'B', 'C']
      ..pageCount = 3
      ..rows = [
        (id: '101', tid: '701', category: ''),
        (id: '205', tid: '702', category: ''),
        (id: '305', tid: '703', category: ''),
      ];
    var drifted = false;
    client.pageTransform = (_) {
      final uri = client.reads.last;
      final page = int.tryParse(uri.queryParameters['page'] ?? '') ?? 1;
      if (page == 3 && !drifted) {
        client.categories.remove('A');
        drifted = true;
      }
      return nativeFavoriteHtml(
        categories: client.categories,
        rows: client.rows
            .where((row) => int.parse(row.id) ~/ 100 == page)
            .toList(),
        token: 'token-${client.tokenNumber}',
        filter: uri.queryParameters['type'],
        page: page,
        pageCount: 3,
      );
    };
    await _open(tester, client, LoadingMode.continuous);
    var refreshed = false;
    for (var attempt = 0;
        attempt < 6 && find.text('Synthetic 703').evaluate().isEmpty;
        attempt++) {
      if (drifted && !refreshed) {
        // A safe refusal may require the user to refresh the changed map.
        await tester.drag(find.byType(ListView), const Offset(0, 400));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        refreshed = true;
      } else {
        final next = find.textContaining(RegExp(r'^加载第 [23] 页$'));
        expect(next, findsOneWidget);
        await _tap(tester, next);
      }
    }
    expect(drifted, isTrue);
    expect(find.text('Synthetic 703'), findsOneWidget);
    expect(client.categories, ['B', 'C']);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('favorite-select-start')));
    await _tap(tester, find.byKey(const ValueKey('favorite-select:305')));
    await _tap(tester, find.byKey(const ValueKey('favorite-move')));
    final visibleB = find.widgetWithText(ListTile, 'B');
    expect(visibleB, findsOneWidget);
    await _tap(tester, visibleB);
    expect(client.writes, hasLength(1));
    final fields = Map.fromEntries(client.writes.single.$2);
    expect(fields['job'], 'change');
    expect(fields['selid[]'], '305');
    final actual = client.rows.singleWhere((row) => row.id == '305').category;
    debugPrint('FAVORITE_CATEGORY_DRIFT refreshed=$refreshed '
        'fields=$fields actualCategory=$actual');
    expect(actual, 'B', reason: 'The user chose B, never positional target C');
    expect(tester.takeException(), isNull);
  });
}
