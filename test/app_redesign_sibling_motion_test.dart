import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/friends_screen.dart';
import 'package:south_plus_rewrite/features/profile/forum_tasks_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/models/forum_friend_models.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

import 'app_redesign_fixture.dart';

class _FriendsRepository extends AppRedesignRepository {
  @override
  Future<ForumFriendPage> fetchFriends({bool pending = false, int page = 1}) =>
      SynchronousFuture(ForumFriendPage(
        pending: pending,
        items: [
          for (var i = 0; i < 2; i++)
            ForumFriend(
              uid: '${(pending ? 100 : 200) + i}',
              name: '$currentUsername ${pending ? 'pending' : 'friend'} $i',
              url: 'https://fixture.invalid/u.php?uid-${100 + i}.html',
            ),
        ],
      ));
}

class _TasksRepository extends AppRedesignRepository {
  @override
  Future<List<ForumTask>> fetchForumTasks(ForumTaskStatus status) =>
      SynchronousFuture([
        ForumTask(
          name: '$currentUsername ${status.name} task',
          status: status,
          cooldownRemaining: const Duration(hours: 12),
          cooldownThreshold: const Duration(hours: 24),
        ),
      ]);

  @override
  Future<ForumTaskSnapshot> refreshForumTaskSnapshot() => SynchronousFuture(
      ForumTaskSnapshot(tasks: const [], updatedAt: DateTime.utc(2026)));
}

Future<void> _select(WidgetTester tester, bool pending,
    {bool settle = true}) async {
  await tester.tap(find.descendant(
    of: find.byType(SegmentedButton<bool>),
    matching: find.textContaining(pending ? '待验证' : '好友'),
  ));
  if (settle) await tester.pumpAndSettle();
}

Future<void> _push(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => page)),
          child: const Text('Open sibling surface'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open sibling surface'));
  await tester.pumpAndSettle();
}

Future<_FriendsRepository> _mount(WidgetTester tester) async {
  final repository = _FriendsRepository();
  await _push(tester, FriendsScreen(repository: repository));
  await _select(tester, true);
  await _select(tester, false);
  expect(find.text('fixture-owner-a friend 0'), findsOneWidget);
  return repository;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'task status exits discard the old account cooldown card immediately',
      (tester) async {
    final repository = _TasksRepository();
    await _push(tester, ForumTasksScreen(repository: repository));
    expect(find.text('fixture-owner-a inProgress task'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(SegmentedButton<ForumTaskStatus>),
        matching: find.text('已完成')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('fixture-owner-a completed task').hitTestable(),
        findsOneWidget);
    final semantics = tester.ensureSemantics();
    try {
      repository.changeOwner('fixture-owner-b');
      await tester.pump();
      expect(find.textContaining('fixture-owner-a', skipOffstage: false),
          findsNothing,
          reason:
              'Old claimed/cooldown cards must not remain in outgoing switch layers');
      expect(find.bySemanticsLabel(RegExp('fixture-owner-a')), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  for (final reverse in [false, true]) {
    testWidgets(
        'friends discard every outgoing owner at 80ms (rapid reverse=$reverse)',
        (tester) async {
      final repository = await _mount(tester);
      final semantics = tester.ensureSemantics();
      try {
        await _select(tester, true, settle: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        if (reverse) {
          await _select(tester, false, settle: false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 80));
        }
        final outgoing = 'fixture-owner-a ${reverse ? 'pending' : 'friend'} 0';
        expect(find.text(outgoing).hitTestable(), findsNothing);
        expect(find.bySemanticsLabel(RegExp(RegExp.escape(outgoing))),
            findsNothing);
        expect(
            find
                .text('fixture-owner-a ${reverse ? 'friend' : 'pending'} 0')
                .hitTestable(),
            findsOneWidget);
        repository.changeOwner('fixture-owner-b');
        await tester.pump();
        expect(find.textContaining('fixture-owner-a', skipOffstage: false),
            findsNothing,
            reason:
                'Session replacement must destroy all retained outgoing children in the first frame');
        expect(find.bySemanticsLabel(RegExp('fixture-owner-a')), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }
}
