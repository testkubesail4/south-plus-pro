import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/messages/pm_detail_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_compose_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';

import 'app_redesign_fixture.dart';

// Synthetic fixtures only: fictional board, links, amounts and texts.
const _board = ForumCategory(
    name: '茶馆',
    slug: 'f9',
    url: 'https://south-plus.net/thread.php?fid-9.html');
const _first = 'message.php?action=chatlog&withuid=901';
const _second = 'message.php?action=chatlog&withuid=901&page=2';

class _Repo extends AppRedesignRepository {
  @override
  Future<ThreadComposeDraft> fetchThreadComposeDraft(
          ForumCategory category) async =>
      const ThreadComposeDraft(
        categories: [],
        selectedCategory: '',
        bountySupported: true,
        defaultBestAmount: 5,
        defaultHelpfulAmount: 3,
        controls: [],
        actionPath: 'post.php?',
        fid: '9',
      );

  @override
  Future<ForumPmChatlog> fetchPmChatlog(String path) async => path == _first
      ? ForumPmChatlog(
          currentPage: 1,
          pageLinks: const [ForumPmPageLink(label: '2', path: _second)],
          records: [
            for (var i = 0; i < 30; i++)
              ForumPmChatRecord(
                  id: '$i', sender: '', title: '', time: '', content: 'p1 $i'),
          ],
        )
      : ForumPmChatlog(currentPage: 2, records: [
          for (var i = 0; i < 30; i++)
            ForumPmChatRecord(
                id: '${100 + i}',
                sender: '',
                title: '',
                time: '',
                content: 'p2 $i'),
        ]);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'a bounty confirmation empties in the frame another account signs in',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final repository = _Repo();
    await tester.pumpWidget(MaterialApp(
        home: ThreadComposeScreen(category: _board, repository: repository)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('compose-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('13 SP币'), findsWidgets);
    repository.changeOwner('fixture-owner-b');
    await tester.pump();
    expect(find.textContaining('13 SP币', skipOffstage: false), findsNothing);
    expect(find.textContaining('最佳答案', skipOffstage: false), findsNothing);
    expect(find.semantics.byLabel(RegExp('SP币')), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('a 通信记录 page fading out never shares its scroll with the next',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      SharedPreferences.setMockInitialValues(
          {'settings.loading.pm': LoadingMode.manual.name});
      await LoadingPreferences.load();
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: PmChatlogScreen(repository: _Repo(), path: _first)));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -20000));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      // Both pages show; desktop adds a scrollbar that needs one position.
      expect(find.text('p2 0'), findsOneWidget);
      expect(find.text('p1 29'), findsOneWidget);
      await tester.drag(find.text('p2 0'), const Offset(0, -100));
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('p1 29'), findsNothing);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .pixels,
          0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
