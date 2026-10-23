import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/thread_row.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';

import 'profile_appendfix_support.dart';

UserListItem _row(String title, {int? views, String? date}) => UserListItem(
      title: title,
      url: 'read.php?tid-${title.hashCode.abs()}.html',
      views: views,
      date: date,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<FakeProfileRepository> open(
      WidgetTester tester, String tab, FakeProfileRepository repository) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: UserProfileScreen(
          userUrl: profileFixture.url, repository: repository),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tab));
    await tester.pumpAndSettle();
    return repository;
  }

  List<String> titles(WidgetTester tester) => [
        for (final row
            in tester.widgetList<ForumThreadRow>(find.byType(ForumThreadRow)))
          row.title,
      ];

  Future<void> pickSort(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('排序'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'topics sort the loaded rows by views both ways, unknown last, and say so',
      (tester) async {
    final repository = await open(
        tester,
        '主题',
        FakeProfileRepository(
          topics: [
            _row('少', views: 5),
            _row('未知'),
            _row('多', views: 40),
          ],
          pagination: const {
            UserProfileTab.topics:
                ThreadPagination(currentPage: 1, totalPages: 3),
          },
        ));
    await tester.tap(find.byTooltip('排序'));
    await tester.pumpAndSettle();
    for (final option in [
      '论坛顺序',
      '发帖时间 从新到旧',
      '发帖时间 从旧到新',
      '浏览量 从多到少',
      '浏览量 从少到多',
      '回复数 从多到少',
      '回复数 从少到多',
    ]) {
      expect(find.text(option), findsOneWidget, reason: option);
    }
    await tester.tap(find.text('浏览量 从多到少'));
    await tester.pumpAndSettle();
    expect(titles(tester), ['多', '少', '未知']);
    expect(find.text('按浏览量 从多到少 · 已加载的 1 页（共 3 页）'), findsOneWidget);

    await pickSort(tester, '浏览量 从少到多');
    expect(titles(tester), ['少', '多', '未知'], reason: 'unknown stays last');
    expect(repository.queries, isEmpty, reason: 'sorting reads nothing');
    expect(repository.scans, isEmpty);

    await pickSort(tester, '论坛顺序');
    expect(titles(tester), ['少', '未知', '多']);
    // Forum order drops the sort scope line.
    expect(find.textContaining('按浏览量'), findsNothing);
  });

  testWidgets('排序全部页面 asks first, then scans and is honest until done',
      (tester) async {
    final repository = await open(
        tester,
        '主题',
        FakeProfileRepository(
          topics: [_row('一', views: 1), _row('二', views: 2)],
          pagination: const {
            UserProfileTab.topics:
                ThreadPagination(currentPage: 1, totalPages: 2),
          },
        ));
    await pickSort(tester, '浏览量 从多到少');
    await tester.tap(find.text('排序全部页面'));
    await tester.pumpAndSettle();
    expect(find.text('排序全部页面？'), findsOneWidget);
    expect(repository.scans, isEmpty, reason: 'not before the confirmation');
    await tester.tap(find.text('开始排序'));
    // A running scan animates its progress: no settling until it ends.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final scan = repository.scans.single;
    expect(scan.query.keyword, '');
    expect(scan.loaded!.map((row) => row.title), ['一', '二'],
        reason: 'seeded with the forum order, not the sorted view');
    expect(find.text('按浏览量 从多到少 · 已扫描 1 页，结果不完整'), findsOneWidget);
    expect(find.text('停止'), findsOneWidget);

    scan.scan.finish(
        [_row('一', views: 1), _row('二', views: 2), _row('三', views: 9)]);
    await tester.pumpAndSettle();
    expect(titles(tester), ['三', '二', '一']);
    expect(find.text('按浏览量 从多到少 · 全部 2 页'), findsOneWidget);
    expect(find.text('排序全部页面'), findsNothing);
  });

  testWidgets('replies sort by their own time only; favourites offer no sort',
      (tester) async {
    await open(
        tester,
        '回复',
        FakeProfileRepository(posts: [
          _row('旧', date: '2024-01-02'),
          _row('新', date: '2026-10-19'),
        ]));
    await tester.tap(find.byTooltip('排序'));
    await tester.pumpAndSettle();
    expect(find.text('回复时间 从新到旧'), findsOneWidget);
    expect(find.text('回复时间 从旧到新'), findsOneWidget);
    expect(find.textContaining('浏览量'), findsNothing);
    expect(find.textContaining('回复数'), findsNothing);
    await tester.tap(find.text('回复时间 从新到旧'));
    await tester.pumpAndSettle();
    expect(titles(tester), ['新', '旧']);

    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('排序'), findsNothing);
  });
}
