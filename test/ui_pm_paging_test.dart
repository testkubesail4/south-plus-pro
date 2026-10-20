import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/messages/pm_box_screen.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';

// Synthetic messages only: 12 a page; page 2 repeats one row of page 1.
const _next = 'message.php?action-receivebox-page-2.html';

ForumPmSummary _message(String id) => ForumPmSummary(
      box: ForumPmBox.inbox,
      type: ForumPmType.personal,
      id: id,
      peer: 'peer $id',
      title: 'Message $id',
      time: '2026-01-01',
      detailPath: 'message.php?action-read-mid-$id.html',
    );

class _Repo extends ForumRepository {
  final paths = <String?>[];

  @override
  Future<ForumPmPage> fetchPmBox(ForumPmBox box, {String? pagePath}) async {
    paths.add(pagePath);
    return pagePath == null
        ? ForumPmPage(
            box: box,
            messages: [for (var i = 0; i < 12; i++) _message('${100 + i}')],
            nextPagePath: _next,
          )
        : ForumPmPage(
            box: box,
            currentPage: 2,
            messages: [_message('111'), _message('200')],
          );
  }
}

void main() {
  Future<_Repo> pump(WidgetTester tester, LoadingMode mode) async {
    SharedPreferences.setMockInitialValues({});
    await LoadingPreferences.load();
    await LoadingPreferences.save(LoadingDomain.pm, mode);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    await tester.pumpWidget(MaterialApp(home: PmBoxScreen(repository: repo)));
    await tester.pumpAndSettle();
    return repo;
  }

  Future<void> toEnd(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, -20000));
    await tester.pumpAndSettle();
  }

  testWidgets('手动翻页: 下一页 turns to page 2 alone', (tester) async {
    final repo = await pump(tester, LoadingMode.manual);
    await toEnd(tester);
    expect(repo.paths, [null]);
    await tester.tap(find.byKey(const ValueKey('page-end-next')));
    await tester.pumpAndSettle();
    expect(repo.paths, [null, _next]);
    expect(find.text('Message 200'), findsOneWidget);
    expect(find.text('Message 100', skipOffstage: false), findsNothing);
  });

  testWidgets('自动接续 appends the next page, a repeated message once',
      (tester) async {
    final repo = await pump(tester, LoadingMode.continuous);
    await toEnd(tester);
    await toEnd(tester);
    expect(repo.paths, [null, _next]);
    expect(find.text('第 2 页'), findsOneWidget);
    expect(find.text('Message 200'), findsOneWidget);
    expect(find.text('Message 111', skipOffstage: false), findsOneWidget);
    expect(find.text('已到最后一页'), findsOneWidget);
  });
}
