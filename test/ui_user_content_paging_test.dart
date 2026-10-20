import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';

import 'profile_appendfix_support.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LoadingPreferences.load();
  });

  Future<FakeProfileRepository> openTopics(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = FakeProfileRepository(
      topics: [for (var i = 0; i < 20; i++) listItem('主题 $i', tid: '$i')],
      onContent: (_) async => contentResult(
        items: [for (var i = 0; i < 40; i++) listItem('主题 $i', tid: '$i')],
        scanned: 2,
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: UserProfileScreen(
        userUrl: profileFixture.url,
        repository: repository,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> toEnd(WidgetTester tester) async {
    await tester.drag(find.text('主题 3'), const Offset(0, -20000));
    await tester.pumpAndSettle();
  }

  testWidgets('手动翻页: reaching the end waits for 加载更多, which appends',
      (tester) async {
    await LoadingPreferences.save(
        LoadingDomain.userContent, LoadingMode.manual);
    final repository = await openTopics(tester);
    await toEnd(tester);
    expect(repository.queries, isEmpty);

    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(repository.queries, hasLength(1));
    await toEnd(tester);
    expect(find.text('主题 39'), findsOneWidget);
    expect(repository.queries, hasLength(1));
  });

  testWidgets('自动接续, the default: reaching the end reads on', (tester) async {
    final repository = await openTopics(tester);
    await toEnd(tester);
    expect(repository.queries, hasLength(1));
    await toEnd(tester);
    expect(find.text('主题 39'), findsOneWidget);
  });
}
