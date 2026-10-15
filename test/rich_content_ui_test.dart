import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/board/board_thread_list_screen.dart';
import 'package:south_plus_rewrite/features/common/cached_forum_image.dart';
import 'package:south_plus_rewrite/features/messages/pm_detail_screen.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_rich_content.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/image_loading_settings.dart';

// Synthetic fixtures only: fictional ids, peers and hosts.
const _summary = ForumPmSummary(
  box: ForumPmBox.inbox,
  type: ForumPmType.personal,
  id: '7',
  peer: 'peer-x',
  title: 'rich title',
  time: '2026-01-01',
  detailPath: 'message.php?action-read-mid-7.html',
);

const _threadLink = 'https://blue-plus.net/read.php?tid-5.html#pid9';
const _userLink = 'https://www.south-plus.org/u.php?action-show-uid-42.html';
const _boardLink = 'https://south-plus.net/thread.php?fid-9.html';
const _pageLink = 'https://blue-plus.net/faq.php?hid-1.html';
const _longUrl = 'https://example.invalid/'
    'averyveryveryveryveryveryveryveryveryveryveryverylongpathsegment'
    'withoutanybreakopportunity/and?query=thatkeepsgoingandgoingandgoing';

const _segments = [
  ThreadContentSegment.text('bold part ', isBold: true),
  ThreadContentSegment.text('to thread', href: _threadLink),
  ThreadContentSegment.text(' '),
  ThreadContentSegment.text('to user', href: _userLink),
  ThreadContentSegment.text(' '),
  ThreadContentSegment.text('to board', href: _boardLink),
  ThreadContentSegment.text(' '),
  ThreadContentSegment.text('bad link', href: 'javascript:alert(1)'),
  ThreadContentSegment.text(' '),
  ThreadContentSegment.text('to page', href: _pageLink),
  ThreadContentSegment.text(' '),
  ThreadContentSegment.text(_longUrl, href: _longUrl),
  ThreadContentSegment.image(url: 'https://img.invalid/picture.png'),
  ThreadContentSegment.text(
      'magnet:?xt=urn:btih:0000000000000000000000000000000000000000'),
];

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'settings.imageLoadMode': 'automatic',
    });
    await ImageLoadingSettings.saveMode(ImageLoadMode.automatic);
  });

  Future<_FakeRepository> pumpPm(
    WidgetTester tester, {
    double textScale = 1,
    Size size = const Size(400, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _FakeRepository();
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: PmDetailScreen(repository: repository, message: _summary),
    ));
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('PM body renders shared rich content with private media',
      (tester) async {
    await pumpPm(tester);

    expect(find.text('[图片]'), findsNothing);
    expect(find.byType(ThreadRichContent), findsOneWidget);
    expect(find.byType(ThreadInlineImage), findsOneWidget);
    expect(find.textContaining('magnet:?xt='), findsOneWidget);
    // Private bodies never reach the public disk image cache or whatslink.
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.text('预览'), findsNothing);
    expect(find.text('下载'), findsOneWidget);

    await tester.tap(find.byType(ThreadInlineImage));
    await tester.pumpAndSettle();
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.text('保存图片'), findsNothing);
  });

  testWidgets('forum links open native screens on the configured mirror',
      (tester) async {
    final repository = await pumpPm(tester);

    await tester.tap(find.text('to thread'));
    await tester.pumpAndSettle();
    expect(find.byType(ThreadDetailScreen), findsOneWidget);
    final opened = repository.threads.single;
    expect(opened.title, '帖子', reason: 'PM link text stays private');
    expect(Uri.parse(opened.url).host, repository.networkConfig.baseUri.host);
    expect(opened.url, endsWith('#pid9'));
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('to user'));
    await tester.pumpAndSettle();
    expect(find.byType(UserProfileScreen), findsOneWidget);
    // action-show opens the profile tab, not the home tab.
    expect(
      tester
          .widget<UserProfileScreen>(find.byType(UserProfileScreen))
          .initialTab,
      UserProfileTab.profile,
    );
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('to board'));
    await tester.pumpAndSettle();
    expect(find.byType(BoardThreadListScreen), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('bad link'));
    await tester.pumpAndSettle();
    expect(find.text('已阻止不安全链接'), findsOneWidget);

    // Pages without a native screen need an explicit browser hand-off.
    await tester.tap(find.text('to page'));
    await tester.pumpAndSettle();
    expect(find.text('在浏览器中打开'), findsOneWidget);
    final shown = tester.widget<SelectableText>(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(SelectableText),
    ));
    expect(Uri.parse(shown.data!).host, repository.networkConfig.baseUri.host);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    // A platform with no browser: the failure is generic, copy on request.
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async => false,
    );
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        null,
      );
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(find.text('to page'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '打开'));
    await tester.pumpAndSettle();
    final snack = tester.widget<SnackBar>(find.byType(SnackBar).last);
    expect((snack.content as Text).data, isNot(contains('faq.php')));
    expect(snack.action?.label, '复制链接');
  });

  testWidgets('long press shows the full link with copy action',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    await pumpPm(tester);

    await tester.longPress(find.text('to thread'));
    await tester.pumpAndSettle();
    expect(find.text(_threadLink), findsOneWidget);
    await tester.tap(find.text('复制链接'));
    await tester.pumpAndSettle();
    expect(copied, _threadLink);
  });

  testWidgets('private image failure actions follow the link policy',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _FakeRepository()
      ..segments = const [
        ThreadContentSegment.image(
          url: 'https://south-plus.net/login.php?action-quit.html',
        ),
      ];
    await tester.pumpWidget(MaterialApp(
      home: PmDetailScreen(repository: repository, message: _summary),
    ));
    await tester.pumpAndSettle();
    // Test HTTP answers 400, so the image fails into its placeholder.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('图片加载失败'));
    await tester.pumpAndSettle();
    expect(
      find.text('已阻止不安全链接').evaluate().isNotEmpty ||
          find.text('在浏览器中打开').evaluate().isNotEmpty,
      isTrue,
      reason: 'never a direct browser launch',
    );
  });

  testWidgets('private images never print their URL in debug output',
      (tester) async {
    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add('$message');
    const canary = 'https://img.invalid/canary-private-token.png';
    try {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: CachedForumImage(
            url: canary,
            assetName: 'assets/forum_emoji/missing/canary.gif',
            privateMemoryOnly: true,
            bypassLoadPolicy: true,
          ),
        ),
      ));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
    } finally {
      // Must be restored before the binding's end-of-test invariant check.
      debugPrint = original;
    }
    expect(
      find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage),
      findsOneWidget,
      reason: 'missing asset fell back to the private network loader',
    );
    expect(printed.where((line) => line.contains('canary')), isEmpty);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('structural WindCode renders literally and readably at $scale',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final opened = <String>[];
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SelectionArea(
              child: ThreadRichContent(
                privateMedia: true,
                onOpenLink: (url, label) async => opened.add(url),
                segments: const [
                  ThreadContentSegment.block(
                    [ThreadContentSegment.text('centered line')],
                    alignment: ThreadContentAlignment.center,
                  ),
                  ThreadContentSegment.code(
                      '[img]x[/img]  <b>keep</b>\n  indented'),
                  ThreadContentSegment.list([
                    ThreadContentSegment.block(
                        [ThreadContentSegment.text('first')]),
                    ThreadContentSegment.block(
                        [ThreadContentSegment.text('second')]),
                  ], isOrdered: true, listStyle: 'a'),
                  ThreadContentSegment.list([
                    ThreadContentSegment.block([
                      ThreadContentSegment.image(
                          url: 'https://img.invalid/in-list.png'),
                    ]),
                  ]),
                  ThreadContentSegment.table([
                    [
                      ThreadContentTableCell(
                          [ThreadContentSegment.text('head one')],
                          isHeader: true),
                      ThreadContentTableCell(
                          [ThreadContentSegment.text('head two')],
                          isHeader: true),
                      ThreadContentTableCell(
                          [ThreadContentSegment.text('head three')],
                          isHeader: true),
                    ],
                    [
                      ThreadContentTableCell([
                        ThreadContentSegment.image(
                            url: 'https://img.invalid/in-table.png'),
                      ]),
                      ThreadContentTableCell(
                          [ThreadContentSegment.text('cell')]),
                    ],
                  ]),
                  ThreadContentSegment.media(
                    url: 'https://media.invalid/clip.wmv',
                    text: 'clip',
                  ),
                  ThreadContentSegment.media(text: 'flash'),
                ],
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(
          find.text('[img]x[/img]  <b>keep</b>\n  indented'), findsOneWidget);
      expect(find.text('a.'), findsOneWidget);
      expect(find.text('b.'), findsOneWidget);
      expect(find.text('•'), findsOneWidget);
      expect(find.text('head three', findRichText: true), findsOneWidget);
      expect(find.text('cell', findRichText: true), findsOneWidget);
      expect(find.byType(ThreadInlineImage), findsNWidgets(2));
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.text('媒体内容无法在应用内播放'), findsOneWidget);
      final centered = tester
          .getRect(find.textContaining('centered line', findRichText: true));
      expect(centered.center.dx, closeTo(160, 2));

      await tester.ensureVisible(find.text('打开'));
      await tester.tap(find.text('打开'));
      expect(opened, ['https://media.invalid/clip.wmv']);
    });
  }

  for (final scale in [0.9, 1.0, 2.0]) {
    testWidgets('narrow PM body stays readable at text scale $scale',
        (tester) async {
      await pumpPm(tester, textScale: scale, size: const Size(320, 640));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('averyvery'), findsOneWidget);
      final link = tester.getRect(find.textContaining('averyvery'));
      expect(link.right, lessThanOrEqualTo(320));
    });
  }
}

class _FakeRepository extends ForumRepository {
  final threads = <ForumThread>[];
  List<ThreadContentSegment> segments = _segments;

  @override
  Future<ForumPmDetail> fetchPmDetail(ForumPmSummary message) async =>
      ForumPmDetail(
        summary: message,
        sender: message.peer,
        title: message.title,
        time: message.time,
        content: 'plain fallback',
        segments: segments,
      );

  @override
  Future<ThreadDetail> fetchThreadDetail(ForumThread thread, {int page = 1}) {
    threads.add(thread);
    return Completer<ThreadDetail>().future;
  }

  @override
  Future<UserProfile?> cachedUserProfileOverview(String url) async => null;

  @override
  Future<UserProfile> fetchUserProfileOverview(String url) =>
      Completer<UserProfile>().future;

  @override
  Future<ForumThreadPage> fetchBoardThreadPage(
    ForumCategory category, {
    int page = 1,
    ForumThreadOrder order = ForumThreadOrder.lastPost,
    ForumBoardFilter? filter,
  }) =>
      Completer<ForumThreadPage>().future;
}
