import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_floor_actions.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// Synthetic fixtures only: fictional tid, uids and authors.
const _url = 'https://south-plus.net/read.php?tid-7.html';
String _profile(int uid) =>
    'https://south-plus.net/u.php?action-show-uid-$uid.html';

class _Repo extends ForumRepository {
  // The profile screen a tap opens never finishes loading here.
  @override
  Future<UserProfile?> cachedUserProfileOverview(String url) async => null;

  @override
  Future<UserProfile> fetchUserProfileOverview(String url) =>
      Completer<UserProfile>().future;

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
          authorUrl: _profile(3),
        ),
        body: 'opening body',
        replies: [
          for (final (author, uid, floor) in [
            ('路人乙', 4, 'B1F'),
            ('楼主甲', 3, 'B2F'),
            // Same display name, another account: not the thread starter.
            ('楼主甲', 5, 'B3F'),
          ])
            ThreadReply(
              author: author,
              authorUrl: _profile(uid),
              content: 'reply $floor',
              segments: [ThreadContentSegment.text('reply $floor')],
              floor: floor,
              postedAt: '2026-10-12 10:20',
              quoteUrl: 'post.php?action-quote-tid-7-pid-$floor.html',
            ),
        ],
      );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpThread(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: ThreadDetailScreen(
        repository: _Repo(),
        thread:
            const ForumThread(title: '', url: _url, replies: 0, section: ''),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder footerOf(String floor) => find.ancestor(
        of: find.byKey(ValueKey('floor-actions-路人乙-$floor')),
        matching: find.byType(ThreadFloorFooter),
      );

  testWidgets('a floor reads name, then time · floor; the OP is tagged',
      (tester) async {
    await pumpThread(tester, const Size(400, 1600));

    expect(find.text('2026-10-12 10:20 · B1F'), findsOneWidget);
    expect(find.text('[B1F]'), findsNothing);
    // The opening post and the OP's own reply carry the tag; a namesake
    // with another uid does not.
    expect(find.text('楼主'), findsNWidgets(2));
  });

  testWidgets('phones get labelled icon actions with full tap targets',
      (tester) async {
    await pumpThread(tester, const Size(400, 1600));
    final footer = footerOf('B1F');

    for (final label in ['回复', '引用', '更多操作']) {
      final action = find.descendant(
        of: footer,
        matching: find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == label,
        ),
      );
      expect(action, findsOneWidget, reason: label);
      // The tap target, padded beyond the 40 px visual.
      final size = tester.getSize(action);
      expect(size.width, greaterThanOrEqualTo(48), reason: label);
      expect(size.height, greaterThanOrEqualTo(48), reason: label);
    }
    expect(
        find.descendant(of: footer, matching: find.text('回复')), findsNothing);
  });

  testWidgets('the whole author row is one 48 px tap target to the profile',
      (tester) async {
    await pumpThread(tester, const Size(400, 1600));
    final row = find
        .ancestor(of: find.text('路人乙'), matching: find.byType(InkWell))
        .first;
    expect(tester.getSize(row).height, greaterThanOrEqualTo(48));

    // The meta line is part of the target, not only the name.
    await tester.tap(find.text('2026-10-12 10:20 · B1F'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.widget<UserProfileScreen>(find.byType(UserProfileScreen)).userUrl,
      _profile(4),
    );
  });

  testWidgets('wide windows spell the actions out', (tester) async {
    await pumpThread(tester, const Size(900, 1600));

    final footer = footerOf('B1F');
    expect(
        find.descendant(of: footer, matching: find.text('回复')), findsOneWidget);
    expect(
        find.descendant(of: footer, matching: find.text('引用')), findsOneWidget);
  });
}
