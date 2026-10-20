import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/messages/pm_detail_screen.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';

import 'app_redesign_fixture.dart';

// Synthetic fixtures only: fictional links and texts.
const _first = 'message.php?action=chatlog&withuid=901';
const _second = 'message.php?action=chatlog&withuid=901&page=2';

class _Repo extends AppRedesignRepository {
  @override
  Future<ForumPmChatlog> fetchPmChatlog(String path) async => ForumPmChatlog(
        currentPage: path == _first ? 1 : 2,
        pageLinks: [
          if (path == _first) const ForumPmPageLink(label: '2', path: _second),
        ],
        records: [
          for (var i = 0; i < 30; i++)
            ForumPmChatRecord(
              id: '$path $i',
              sender: '',
              title: '',
              time: '',
              content: '${path == _first ? 'p1' : 'p2'} $i',
            ),
        ],
      );
}

void main() {
  // Desktop adds a scrollbar, which needs one scroll position per list.
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
      // Both pages show while the new one is scrolled.
      expect(find.text('p1 29'), findsOneWidget);
      expect(find.text('p2 0'), findsOneWidget);
      await tester.drag(find.text('p2 0'), const Offset(0, -100));
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('p1 29'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
