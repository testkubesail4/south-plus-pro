import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/board/board_thread_list_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// Synthetic fixtures only: fictional tid, uid, board and authors.
const _filteredUrl = 'https://south-plus.net/read.php?tid-7-uid-9.html';
const _board = ForumCategory(
  name: '茶馆',
  slug: 'f9',
  url: 'https://south-plus.net/thread.php?fid-9.html',
);

class _Repo extends ForumRepository {
  _Repo({this.board});

  final ForumCategory? board;
  final boardRequests = <ForumCategory>[];

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
        thread: thread.copyWith(title: '合成主题', section: '茶馆'),
        body: 'body',
        replies: const [],
        board: board,
        rssFeed: const ThreadActionLink(
          label: 'RSS',
          url: 'https://south-plus.net/rss.php?tid-7',
        ),
      );

  @override
  Future<ForumThreadPage> fetchBoardThreadPage(
    ForumCategory category, {
    int page = 1,
    ForumThreadOrder order = ForumThreadOrder.lastPost,
    ForumBoardFilter? filter,
  }) {
    boardRequests.add(category);
    return Completer<ForumThreadPage>().future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final copied = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    copied.clear();
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  });
  tearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );

  Future<_Repo> pumpThread(WidgetTester tester, {ForumCategory? board}) async {
    final repository = _Repo(board: board);
    await tester.pumpWidget(MaterialApp(
      home: ThreadDetailScreen(
        repository: repository,
        thread: const ForumThread(
          title: '',
          url: _filteredUrl,
          replies: 0,
          section: '',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('the board name opens that board', (tester) async {
    final repository = await pumpThread(tester, board: _board);

    await tester.tap(find.byTooltip('打开版块'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      tester.widget<BoardThreadListScreen>(find.byType(BoardThreadListScreen))
          .category,
      _board,
    );
    expect(repository.boardRequests.single.slug, 'f9');
  });

  testWidgets('an unknown board is a plain title', (tester) async {
    await pumpThread(tester);

    expect(find.text('茶馆'), findsOneWidget);
    expect(find.byTooltip('打开版块'), findsNothing);
  });

  testWidgets('分享 hands over the canonical link, never the filtered one',
      (tester) async {
    const channel = MethodChannel('south_plus_rewrite/image_saver');
    final shared = <Object?>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      shared.add(call.arguments);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await pumpThread(tester, board: _board);

    await tester.tap(find.byTooltip('分享'));
    await tester.pumpAndSettle();

    expect(shared, [
      {'text': '合成主题\nhttps://south-plus.net/read.php?tid-7.html'},
    ]);
    expect(copied, isEmpty);
  });

  testWidgets('分享 without a share sheet copies the link and says so',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await pumpThread(tester, board: _board);

    await tester.tap(find.byTooltip('分享'));
    await tester.pumpAndSettle();

    expect(copied, ['https://south-plus.net/read.php?tid-7.html']);
    expect(find.text('已复制链接'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('⋮ holds the rare thread actions', (tester) async {
    await pumpThread(tester, board: _board);

    expect(find.byTooltip('回复'), findsNothing, reason: 'the FAB replies');
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();

    expect(find.text('搜索同名主题'), findsOneWidget);
    expect(find.text('RSS 订阅'), findsOneWidget);
  });
}
