import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// Synthetic fixtures only: fictional tid, uid and authors.
const _url = 'https://south-plus.net/read.php?tid-7.html';

class _Repo extends ForumRepository {
  final favoriteCalls = <String>[];

  /// When set, 收藏 waits for it, so the busy state can be observed.
  Completer<void>? holdFavorite;

  @override
  Future<ThreadReadPosition?> loadThreadReadPosition(ForumThread t) async =>
      null;

  @override
  Future<void> saveThreadReadPosition(
    ForumThread t,
    ThreadReadPosition p,
  ) async {}

  @override
  Future<ThreadDetail> fetchThreadDetail(
    ForumThread thread, {
    int page = 1,
  }) async =>
      ThreadDetail(
        thread: thread.copyWith(
          title: '合成主题',
          author: '楼主甲',
          authorUrl: 'https://south-plus.net/u.php?action-show-uid-3.html',
        ),
        body: 'body',
        replies: const [],
        favorite: const ThreadFavorite(
          tid: '7',
          verify: 'synthetic',
          state: ThreadFavoriteState.notFavorite,
        ),
        nextThread: const ThreadActionLink(
          label: '下一主题',
          url: 'https://south-plus.net/read.php?tid-8.html',
        ),
      );

  @override
  Future<FavoriteResult> addFavorite(ThreadFavorite favorite) async {
    favoriteCalls.add('add');
    await holdFavorite?.future;
    return const FavoriteResult(
      success: true,
      message: 'synthetic notice',
      state: ThreadFavoriteState.favorite,
    );
  }

  @override
  Future<FavoriteResult> removeFavorite(ThreadFavorite favorite) async {
    favoriteCalls.add('remove');
    return const FavoriteResult(
      success: true,
      message: 'synthetic notice',
      state: ThreadFavoriteState.notFavorite,
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_Repo> pumpThread(WidgetTester tester, {double textScale = 1}) async {
    final repository = _Repo();
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ThreadDetailScreen(
        repository: repository,
        thread: const ForumThread(title: '', url: _url, replies: 0, section: ''),
      ),
    ));
    await tester.pumpAndSettle();
    return repository;
  }

  Finder slot(String label) => find
      .ancestor(of: find.text(label), matching: find.byType(InkWell))
      .first;

  testWidgets('收藏 toggles on and off, showing its state', (tester) async {
    final repository = await pumpThread(tester);
    expect(
      tester.getSemantics(find.text('收藏')),
      containsSemantics(isSelected: false),
    );

    await tester.ensureVisible(slot('收藏'));
    await tester.tap(slot('收藏'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text('已收藏')),
      containsSemantics(isSelected: true),
    );

    await tester.tap(slot('已收藏'));
    await tester.pumpAndSettle();
    expect(repository.favoriteCalls, ['add', 'remove']);
    expect(find.text('收藏'), findsOneWidget);
  });

  testWidgets('large text moves the strip to two slots per row, never '
      'breaking a label', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpThread(tester, textScale: 2);

    double top(String label) => tester.getTopLeft(find.text(label)).dy;
    expect(top('收藏'), top('只看楼主'));
    expect(top('上一主题'), greaterThan(top('只看楼主')));
    expect(top('下一主题'), top('上一主题'));
    // One line each: no label wraps inside its slot.
    for (final label in ['只看楼主', '上一主题', '下一主题']) {
      expect(tester.getSize(find.text(label)).height, lessThan(24 * 2),
          reason: label);
    }
  });

  testWidgets('a busy 收藏 is announced as disabled until it settles',
      (tester) async {
    final repository = await pumpThread(tester);
    repository.holdFavorite = Completer<void>();

    await tester.ensureVisible(slot('收藏'));
    await tester.tap(slot('收藏'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.getSemantics(find.text('收藏')),
      containsSemantics(isButton: true, isEnabled: false),
    );

    repository.holdFavorite!.complete();
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text('已收藏')),
      containsSemantics(isEnabled: true, isSelected: true),
    );
  });

  testWidgets('a missing neighbour thread is a disabled slot', (tester) async {
    await pumpThread(tester);

    expect(
      tester.getSemantics(find.text('上一主题')),
      containsSemantics(isButton: true, isEnabled: false),
    );
    expect(
      tester.getSemantics(find.text('下一主题')),
      containsSemantics(isButton: true, isEnabled: true),
    );
  });
}
