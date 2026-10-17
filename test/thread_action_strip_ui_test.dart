import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// Synthetic fixtures only: fictional tid, uid and authors.
const _url = 'https://south-plus.net/read.php?tid-7.html';
const _previous = 'https://south-plus.net/read.php?tid-6.html';
const _next = 'https://south-plus.net/read.php?tid-8.html';

class _Repo extends ForumRepository {
  _Repo({this.signedIn = true, this.previous = true, this.next = true});

  final bool signedIn;
  final bool previous;
  final bool next;
  final favoriteCalls = <String>[];
  final requested = <String>[];

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
  }) async {
    requested.add(thread.url);
    return ThreadDetail(
      thread: thread.copyWith(
        title: '合成主题',
        author: '楼主甲',
        authorUrl: 'https://south-plus.net/u.php?action-show-uid-3.html',
      ),
      body: 'body',
      replies: const [],
      favorite: signedIn
          ? const ThreadFavorite(
              tid: '7',
              verify: 'synthetic',
              state: ThreadFavoriteState.notFavorite,
            )
          : null,
      previousThread: previous
          ? const ThreadActionLink(label: '上一主题', url: _previous)
          : null,
      nextThread:
          next ? const ThreadActionLink(label: '下一主题', url: _next) : null,
    );
  }

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

  Future<_Repo> pumpThread(
    WidgetTester tester, {
    double textScale = 1,
    _Repo? repository,
  }) async {
    final repo = repository ?? _Repo();
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ThreadDetailScreen(
        repository: repo,
        thread: const ForumThread(title: '', url: _url, replies: 0, section: ''),
      ),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  void setView(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Finder button(String label) => find
      .ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      )
      .first;

  testWidgets('收藏 toggles on and off, showing its state', (tester) async {
    final repository = await pumpThread(tester);
    expect(
      tester.getSemantics(find.text('收藏')),
      containsSemantics(isSelected: false),
    );

    await tester.ensureVisible(button('收藏'));
    await tester.tap(button('收藏'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text('已收藏')),
      containsSemantics(isSelected: true),
    );

    await tester.tap(button('已收藏'));
    await tester.pumpAndSettle();
    expect(repository.favoriteCalls, ['add', 'remove']);
    expect(find.text('收藏'), findsOneWidget);
  });

  testWidgets('the toggles share the floor actions row on a phone',
      (tester) async {
    setView(tester, const Size(400, 800));
    await pumpThread(tester);

    final reply = tester.getCenter(find.byTooltip('回复')).dy;
    expect(tester.getCenter(button('收藏')).dy, reply);
    expect(tester.getCenter(button('只看楼主')).dy, reply);
    // The neighbour row sits below, 上一主题 at the start, 下一主题 at the end.
    expect(tester.getTopLeft(button('上一主题')).dy, greaterThan(reply));
    expect(tester.getTopLeft(button('上一主题')).dx,
        lessThan(tester.getTopLeft(button('收藏')).dx + 1));
    expect(tester.getTopRight(button('下一主题')).dx,
        greaterThan(tester.getTopRight(find.byTooltip('更多操作')).dx - 16));
  });

  for (final width in [320.0, 400.0]) {
    testWidgets('at large text on a $width px phone the toggles take their '
        'own line, never breaking a label', (tester) async {
      setView(tester, Size(width, 1600));
      await pumpThread(tester, textScale: 2);

      final reply = tester.getTopLeft(find.byTooltip('回复')).dy;
      expect(tester.getBottomLeft(button('只看楼主')).dy,
          lessThanOrEqualTo(reply + 1));
      // One line each: no label wraps inside its button.
      for (final label in ['收藏', '只看楼主', '上一主题', '下一主题']) {
        expect(tester.getSize(find.text(label)).height, lessThan(14 * 2 * 2),
            reason: label);
        expect(tester.getTopRight(find.text(label)).dx,
            lessThanOrEqualTo(width), reason: label);
      }
    });
  }

  testWidgets('every thread control is a 48 px target', (tester) async {
    setView(tester, const Size(400, 800));
    final repository = await pumpThread(tester);

    for (final label in ['收藏', '只看楼主', '上一主题', '下一主题']) {
      final size = tester.getSize(button(label));
      expect(size.height, greaterThanOrEqualTo(48), reason: label);
      expect(size.width, greaterThanOrEqualTo(48), reason: label);
    }
    // The pill draws 32 high; a tap just above it still lands.
    final pill = tester.getRect(find.descendant(
        of: button('收藏'), matching: find.byType(Material)));
    expect(pill.height, lessThan(48));
    await tester.tapAt(pill.topCenter - const Offset(0, 6));
    await tester.pumpAndSettle();
    expect(repository.favoriteCalls, ['add']);
  });

  testWidgets('a busy 收藏 is announced as disabled until it settles',
      (tester) async {
    final repository = await pumpThread(tester);
    repository.holdFavorite = Completer<void>();

    await tester.ensureVisible(button('收藏'));
    await tester.tap(button('收藏'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget, reason: 'the label stays');
    expect(
      tester.getSemantics(find.text('收藏')),
      containsSemantics(isButton: true, isEnabled: false),
    );
    await tester.tap(button('收藏'), warnIfMissed: false);
    expect(repository.favoriteCalls, ['add'], reason: 'no second request');

    repository.holdFavorite!.complete();
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text('已收藏')),
      containsSemantics(isEnabled: true, isSelected: true),
    );
  });

  testWidgets('下一主题 opens the neighbouring thread', (tester) async {
    final repository = await pumpThread(tester);

    await tester.ensureVisible(button('下一主题'));
    await tester.tap(button('下一主题'));
    await tester.pumpAndSettle();
    expect(repository.requested.last, _next);
  });

  testWidgets('a control the thread lacks is left out', (tester) async {
    setView(tester, const Size(400, 800));
    await pumpThread(tester, repository: _Repo(signedIn: false, previous: false));

    expect(find.text('收藏'), findsNothing);
    expect(find.text('上一主题'), findsNothing);
    // The remaining neighbour keeps its side.
    expect(tester.getTopRight(button('下一主题')).dx,
        greaterThan(tester.getTopRight(find.byTooltip('更多操作')).dx - 16));
    expect(find.text('只看楼主'), findsOneWidget);
  });

  testWidgets('without neighbours the divider and row go too',
      (tester) async {
    await pumpThread(tester,
        repository: _Repo(previous: false, next: false));

    expect(find.text('上一主题'), findsNothing);
    expect(find.text('下一主题'), findsNothing);
    expect(
      find.descendant(of: find.byType(Card).first, matching: find.byType(Divider)),
      findsNothing,
    );
  });
}
