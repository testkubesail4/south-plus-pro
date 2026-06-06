import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/app.dart';
import 'package:south_plus_rewrite/features/auth/login_screen.dart';
import 'package:south_plus_rewrite/features/board/board_thread_list_screen.dart';
import 'package:south_plus_rewrite/features/common/async_state_view.dart';
import 'package:south_plus_rewrite/features/history/browsing_history_screen.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/features/reply/reply_sheet.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_post_body.dart';
import 'package:south_plus_rewrite/features/thread/thread_rich_content.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_network_setup_store.dart';
import 'package:south_plus_rewrite/services/image_loading_settings.dart';

void main() {
  testWidgets('app boots to simple home screen', (tester) async {
    SharedPreferences.setMockInitialValues({
      ForumNetworkSetupStore.completedKey: true,
    });

    await tester.pumpWidget(const SouthPlusApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('southplus'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });

  testWidgets('skeleton card fits compact three-line layouts', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: SkeletonCard(height: 86, lines: [0.92, 0.58, 0.36]),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('login failure remains visible if captcha refresh fails',
      (tester) async {
    final repository = _FakeLoginRepository();

    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(repository: repository)),
    );
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(0), 'alice');
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.enterText(find.byType(TextField).at(2), '1234');
    await tester.ensureVisible(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.text('密码错误'), findsOneWidget);
    expect(
      find.textContaining('验证码加载失败：没有找到登录表单'),
      findsOneWidget,
    );
  });

  testWidgets('login submits selected forum options', (tester) async {
    final repository = _FakeLoginRepository();

    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('UID'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('一年'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('一个月').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐身登录'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '10001');
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.enterText(find.byType(TextField).at(2), '1234');
    await tester.ensureVisible(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(repository.lastFields, containsPair('lgt', '1'));
    expect(repository.lastFields, containsPair('hideid', '1'));
    expect(repository.lastFields, containsPair('cktime', '2592000'));
  });

  testWidgets('board thread list supports pull refresh on short pages',
      (tester) async {
    final repository = _FakeBoardRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: BoardThreadListScreen(
          category: _FakeBoardRepository.category,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RefreshIndicator), findsOneWidget);
    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.physics, isA<AlwaysScrollableScrollPhysics>());
  });

  testWidgets('browsing history opens a viewed thread', (tester) async {
    final repository = _FakeHistoryRepository();

    await tester.pumpWidget(
      MaterialApp(home: BrowsingHistoryScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('浏览历史'), findsOneWidget);
    expect(find.text('看过的主题'), findsOneWidget);
    expect(find.text('10 回'), findsOneWidget);

    await tester.tap(find.text('看过的主题'));
    await tester.pumpAndSettle();

    expect(repository.requestedThreadUrls, [
      'https://south-plus.net/read.php?tid-88.html',
    ]);
    expect(find.text('history body', findRichText: true), findsOneWidget);
  });

  testWidgets('browsing history can be cleared after confirmation',
      (tester) async {
    final repository = _FakeHistoryRepository();

    await tester.pumpWidget(
      MaterialApp(home: BrowsingHistoryScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('清空浏览历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '清空'));
    await tester.pumpAndSettle();

    expect(repository.cleared, isTrue);
    expect(find.text('还没有浏览历史'), findsOneWidget);
    expect(find.text('浏览历史已清空'), findsOneWidget);
  });

  testWidgets('profile overview renders before detail tabs finish loading',
      (tester) async {
    final repository = _FakeProfileRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: UserProfileScreen(
          userUrl: 'https://south-plus.net/u.php?action-show-uid-1.html',
          repository: repository,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('在线'), findsOneWidget);
    expect(find.text('UID 1'), findsOneWidget);
    expect(find.text('个人动态'), findsNothing);

    await tester.tap(find.text('资料'));
    await tester.pumpAndSettle();

    expect(find.text('个人信息'), findsOneWidget);
    expect(find.text('论坛资历'), findsOneWidget);

    repository.completeDetails();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();

    expect(find.text('个人动态'), findsOneWidget);
    expect(find.text('发表了主题'), findsOneWidget);
  });

  testWidgets('profile uses cached overview while refreshing fresh data',
      (tester) async {
    final repository = _CachedProfileRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: UserProfileScreen(
          userUrl: 'https://south-plus.net/u.php?action-show-uid-1.html',
          repository: repository,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Cached Alice'), findsOneWidget);
    expect(find.text('Fresh Alice'), findsNothing);

    repository.completeFreshOverview();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Fresh Alice'), findsOneWidget);
    expect(find.text('Cached Alice'), findsNothing);
  });

  testWidgets('deferred inline image placeholder stays compact',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await ImageLoadingSettings.saveMode(ImageLoadMode.manual);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: ThreadInlineImage(
              image: ThreadImage(url: 'https://example.com/image.jpg'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final inlineImageContainerFinder =
        find.byKey(const ValueKey('thread-inline-image-container'));
    final inlineImageContainer =
        tester.widget<Container>(inlineImageContainerFinder);

    expect(inlineImageContainer.color, isNull);
    expect(tester.getSize(find.byType(ThreadInlineImage)).height, 160);
    expect(find.byIcon(Icons.download_outlined), findsNothing);

    final inlineImageTapTarget = tester.widget<InkWell>(
      find.byWidgetPredicate(
        (widget) => widget is InkWell && widget.onLongPress != null,
      ),
    );
    inlineImageTapTarget.onTap!();
    await tester.pumpAndSettle();

    expect(find.text('保存图片'), findsOneWidget);
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
  });

  testWidgets('post body does not duplicate inline links as buttons',
      (tester) async {
    final clipboardWrites = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final arguments = call.arguments as Map<Object?, Object?>;
          clipboardWrites.add(arguments['text']! as String);
          return null;
        }
        if (call.method == 'Clipboard.getData') {
          return <String, Object?>{
            'text': clipboardWrites.isEmpty ? null : clipboardWrites.last,
          };
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThreadPostBody(
            content: 'Example',
            segments: const [
              ThreadContentSegment.text(
                'Example',
                href: 'https://example.com',
              ),
            ],
            quote: null,
            images: const [],
            links: const [
              ThreadLink(url: 'https://example.com', label: 'Example'),
            ],
            saleBoxes: const [],
            saleBoxesFirst: false,
            buyingSaleBoxes: const {},
            onBuySaleBox: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Example'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);

    await tester.longPress(find.text('Example'));
    await tester.pump();

    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    expect(clipboard?.text, 'https://example.com');
    expect(find.text('链接已复制'), findsOneWidget);
  });

  testWidgets('paid content sale box renders clear metadata and action',
      (tester) async {
    final purchases = <ThreadSaleBox>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThreadPostBody(
            content: '',
            segments: const [],
            quote: null,
            images: const [],
            links: const [],
            saleBoxes: const [
              ThreadSaleBox(
                summary: '此帖售价 5 SP币,已有 8 人购买',
                buyPath: 'job.php?action=buytopic&tid=1&pid=1',
                warning: '购买风险提示',
                price: 5,
                buyers: 8,
              ),
            ],
            saleBoxesFirst: true,
            buyingSaleBoxes: const {},
            onBuySaleBox: purchases.add,
          ),
        ),
      ),
    );

    expect(find.text('付费内容'), findsOneWidget);
    expect(find.text('5 SP币'), findsOneWidget);
    expect(find.text('8 人购买'), findsOneWidget);
    expect(find.text('购买查看'), findsOneWidget);
    expect(find.text('购买风险提示'), findsOneWidget);

    await tester.tap(find.text('购买查看'));
    expect(purchases, hasLength(1));
  });

  testWidgets('reply composer can focus content field', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReplyComposer(
            thread: _FakeThreadRepository.thread,
            repository: _FakeThreadRepository(),
            onSubmitted: (_) {},
          ),
        ),
      ),
    );

    final contentFieldFinder = find.byType(TextField).last;
    final submitButtonFinder =
        find.byKey(const ValueKey('reply-submit-button'));
    expect(tester.widget<TextField>(contentFieldFinder).focusNode?.hasFocus,
        isFalse);
    expect(
      tester.widget<ButtonStyleButton>(submitButtonFinder).onPressed,
      isNull,
    );

    final state = tester.state<ReplyComposerState>(find.byType(ReplyComposer));
    state.focusContent();
    await tester.pump();

    expect(tester.widget<TextField>(contentFieldFinder).focusNode?.hasFocus,
        isTrue);

    await tester.enterText(contentFieldFinder, '有效回复');
    await tester.pump();

    expect(
      tester.widget<ButtonStyleButton>(submitButtonFinder).onPressed,
      isNotNull,
    );
  });

  testWidgets('download links render preview and download actions',
      (tester) async {
    final clipboardWrites = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final arguments = call.arguments as Map<Object?, Object?>;
          clipboardWrites.add(arguments['text']! as String);
          return null;
        }
        if (call.method == 'Clipboard.getData') {
          return <String, Object?>{
            'text': clipboardWrites.isEmpty ? null : clipboardWrites.last,
          };
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    const magnetUrl =
        'magnet:?xt=urn:btih:abcdef1234567890abcdef1234567890abcdef12';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ThreadRichContent(
            segments: [
              ThreadContentSegment.text(magnetUrl),
            ],
          ),
        ),
      ),
    );

    expect(find.text(magnetUrl), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('预览'), findsOneWidget);
    expect(find.text('下载'), findsOneWidget);

    await tester.tap(find.text('复制'));
    await tester.pump();

    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    expect(clipboardData?.text, magnetUrl);
    expect(find.text('链接已复制'), findsOneWidget);
  });

  testWidgets('download link preview dialog includes copy action',
      (tester) async {
    const magnetUrl =
        'magnet:?xt=urn:btih:abcdef1234567890abcdef1234567890abcdef12';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ThreadRichContent(
            segments: [
              ThreadContentSegment.text(magnetUrl),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('复制'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('thread detail shows avatar fallback and page controls',
      (tester) async {
    final repository = _FakeThreadRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: ThreadDetailScreen(
          thread: _FakeThreadRepository.thread,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('thread-author-avatar-fallback')),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('南+ / 事务受理'),
      ),
      findsOneWidget,
    );
    expect(find.text('南+ South Plus'), findsNothing);
    expect(find.text('上一主题'), findsOneWidget);
    expect(find.text('下一主题'), findsOneWidget);
    expect(find.text('RSS'), findsOneWidget);
    expect(find.byTooltip('更多操作'), findsOneWidget);
    expect(find.text('只看该作者'), findsNothing);
    expect(find.text('2 / 4'), findsNWidgets(2));
    expect(find.text('page 2 body', findRichText: true), findsNothing);
    expect(find.text('reply on page 2', findRichText: true), findsOneWidget);

    await tester.tap(find.text('»').first);
    await tester.pumpAndSettle();

    expect(repository.requestedPages, [1, 3]);
    expect(find.text('reply on page 3', findRichText: true), findsOneWidget);
  });

  testWidgets('thread detail jump clamps page number', (tester) async {
    final repository = _FakeThreadRepository(initialPage: 2);

    await tester.pumpWidget(
      MaterialApp(
        home: ThreadDetailScreen(
          thread: _FakeThreadRepository.thread,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('跳转').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'abc',
    );
    await tester.tap(find.widgetWithText(FilledButton, '跳转'));
    await tester.pumpAndSettle();

    expect(find.text('请输入有效页码'), findsOneWidget);
    expect(repository.requestedPages, [1]);

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '99',
    );
    await tester.tap(find.widgetWithText(FilledButton, '跳转'));
    await tester.pumpAndSettle();

    expect(repository.requestedPages, [1, 4]);
    expect(find.text('reply on page 4', findRichText: true), findsOneWidget);
  });

  testWidgets('thread detail keeps current content when pagination fails',
      (tester) async {
    final repository = _FakeThreadRepository(failPages: {3});

    await tester.pumpWidget(
      MaterialApp(
        home: ThreadDetailScreen(
          thread: _FakeThreadRepository.thread,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('»').first);
    await tester.pumpAndSettle();

    expect(repository.requestedPages, [1, 3]);
    expect(find.text('reply on page 2', findRichText: true), findsOneWidget);
    expect(find.text('reply on page 3', findRichText: true), findsNothing);
    expect(find.textContaining('页面加载失败：boom page 3'), findsOneWidget);
  });

  testWidgets('thread detail loads and clears server author filter',
      (tester) async {
    final repository = _FakeThreadRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: ThreadDetailScreen(
          thread: _FakeThreadRepository.thread,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('floor-actions-Bob-B2F')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('只看该作者'));
    await tester.pumpAndSettle();

    expect(repository.requestedPages, [1, 1]);
    expect(repository.requestedThreadUrls, [
      'https://south-plus.net/read.php?tid-1.html',
      'https://south-plus.net/read.php?tid-1-uid-2.html',
    ]);
    expect(find.text('只看 Bob'), findsOneWidget);
    expect(find.text('第 1 / 1 页 · 本页 1 楼'), findsOneWidget);

    await tester.tap(find.byTooltip('取消只看该作者'));
    await tester.pumpAndSettle();

    expect(repository.requestedThreadUrls.last,
        'https://south-plus.net/read.php?tid-1.html');
    expect(find.text('只看 Bob'), findsNothing);
  });

  testWidgets('thread detail uses server pagination for original poster filter',
      (tester) async {
    final repository = _FakeThreadRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: ThreadDetailScreen(
          thread: _FakeThreadRepository.thread,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.ancestor(
        of: find.text('只看楼主'),
        matching: find.byType(FilterChip),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.requestedThreadUrls, [
      'https://south-plus.net/read.php?tid-1.html',
      'https://south-plus.net/read.php?tid-1-uid-1.html',
    ]);
    expect(find.text('只看 Alice'), findsOneWidget);
    expect(find.text('第 1 / 2 页 · 本页 1 楼'), findsOneWidget);
    expect(find.text('op filtered page 1', findRichText: true), findsOneWidget);
    expect(find.text('1 / 2'), findsWidgets);
    expect(find.text('2 / 4'), findsNothing);
    expect(
      tester
          .widget<FilterChip>(
            find.ancestor(
              of: find.text('只看楼主'),
              matching: find.byType(FilterChip),
            ),
          )
          .selected,
      isTrue,
    );

    await tester.tap(find.text('»').first);
    await tester.pumpAndSettle();

    expect(repository.requestedThreadUrls.last,
        'https://south-plus.net/read.php?tid-1-uid-1.html');
    expect(repository.requestedPages, [1, 1, 2]);
    expect(find.text('op filtered page 2', findRichText: true), findsOneWidget);
    expect(find.text('2 / 2'), findsWidgets);
    expect(find.text('第 2 / 2 页 · 本页 1 楼'), findsOneWidget);

    await tester.tap(
      find.ancestor(
        of: find.text('只看楼主'),
        matching: find.byType(FilterChip),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.requestedThreadUrls.last,
        'https://south-plus.net/read.php?tid-1.html');
    expect(find.text('只看 Alice'), findsNothing);
    expect(find.text('1 / 4'), findsWidgets);
  });

  testWidgets('thread detail shows empty state for empty author filter',
      (tester) async {
    final repository = _FakeThreadRepository(emptyAuthorFilter: true);

    await tester.pumpWidget(
      MaterialApp(
        home: ThreadDetailScreen(
          thread: _FakeThreadRepository.thread,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('floor-actions-Bob-B2F')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('只看该作者'));
    await tester.pumpAndSettle();

    expect(find.text('只看 Bob'), findsOneWidget);
    expect(find.text('第 1 / 1 页 · 本页 0 楼'), findsOneWidget);
    expect(find.text('没有该作者内容'), findsOneWidget);
    expect(find.text('当前筛选结果没有可展示的楼层。'), findsOneWidget);
  });

  testWidgets('thread detail inserts server quote draft when available',
      (tester) async {
    final repository = _FakeThreadRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: ThreadDetailScreen(
          thread: _FakeThreadRepository.thread,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final floorActions = find.byKey(const ValueKey('floor-actions-Bob-B2F'));
    await tester.ensureVisible(floorActions);
    await tester.pumpAndSettle();
    await tester.tap(floorActions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('引用').last);
    await tester.pumpAndSettle();

    expect(repository.requestedQuoteUrls, [
      'https://south-plus.net/post.php?action-quote-fid-2-tid-1-pid-20-article-1.html',
    ]);
    final contentField = tester.widget<TextField>(find.byType(TextField).last);
    expect(contentField.controller?.text,
        '[quote]server quote from Bob[/quote]\n');
  });
}

class _FakeProfileRepository extends ForumRepository {
  _FakeProfileRepository();

  final _detailsCompleter = Completer<UserProfile>();

  static const overview = UserProfile(
    uid: '1',
    name: 'Alice',
    url: 'https://south-plus.net/u.php?action-show-uid-1.html',
    tagline: '干净签名',
    level: 'Lv.3',
    isOnline: true,
    statusText: '在线',
    messageUrl: 'https://south-plus.net/message.php?action-write-touid-1.html',
    info: [
      UserProfileField(label: 'UID', value: '1'),
      UserProfileField(label: '昵称', value: 'alice'),
    ],
    stats: [
      UserProfileField(label: '在线时间', value: '9 小时'),
    ],
  );

  @override
  Future<UserProfile?> cachedUserProfileOverview(String url) async => null;

  @override
  Future<UserProfile> fetchUserProfileOverview(String url) async => overview;

  @override
  Future<UserProfile> fetchUserProfileDetails(UserProfile overview) {
    return _detailsCompleter.future;
  }

  void completeDetails() {
    if (_detailsCompleter.isCompleted) return;
    _detailsCompleter.complete(
      overview.copyWith(
        homeActivities: const [
          UserActivityItem(
            title: '测试主题',
            url: 'https://south-plus.net/read.php?tid-1.html',
            action: '发表了主题',
          ),
        ],
      ),
    );
  }
}

class _FakeLoginRepository extends ForumRepository {
  int challengeRequests = 0;
  Map<String, String>? lastFields;

  @override
  Future<LoginChallenge> fetchLoginChallenge() async {
    challengeRequests += 1;
    if (challengeRequests == 1) {
      return LoginChallenge(
        captchaBytes: Uint8List.fromList(_onePixelPng),
        fields: const {'step': '2'},
      );
    }
    throw const ForumRepositoryException('没有找到登录表单');
  }

  @override
  Future<LoginResult> submitLogin({
    required String username,
    required String password,
    required String captcha,
    required Map<String, String> fields,
  }) async {
    lastFields = Map<String, String>.from(fields);
    return const LoginResult(success: false, message: '密码错误');
  }
}

class _FakeBoardRepository extends ForumRepository {
  static const category = ForumCategory(
    name: '测试版块',
    slug: 'test',
    url: 'https://south-plus.net/thread.php?fid-1.html',
  );

  @override
  Future<ForumThreadPage> fetchBoardThreadPage(
    ForumCategory category, {
    int page = 1,
  }) async {
    return const ForumThreadPage(
      currentPage: 1,
      totalPages: 1,
      threads: [
        ForumThread(
          title: '短列表主题',
          url: 'https://south-plus.net/read.php?tid-1.html',
          replies: 0,
          section: '测试版块',
        ),
      ],
    );
  }
}

class _FakeHistoryRepository extends ForumRepository {
  bool cleared = false;
  var _entries = [
    BrowsingHistoryEntry(
      thread: ForumThread(
        title: '看过的主题',
        url: 'https://south-plus.net/read.php?tid-88.html',
        replies: 10,
        section: '茶馆',
        bodyPreview: '历史里的摘要',
        author: 'Alice',
      ),
      viewedAt: DateTime.now().subtract(const Duration(minutes: 3)).toUtc(),
    ),
  ];
  final requestedThreadUrls = <String>[];

  @override
  Future<List<BrowsingHistoryEntry>> browsingHistory({int limit = 100}) async {
    return _entries;
  }

  @override
  Future<void> clearBrowsingHistory() async {
    cleared = true;
    _entries = const [];
  }

  @override
  Future<ThreadDetail> fetchThreadDetail(
    ForumThread thread, {
    int page = 1,
  }) async {
    requestedThreadUrls.add(thread.url);
    return ThreadDetail(
      thread: thread.copyWith(
        author: 'Alice',
        lastPost: '2026-05-30 10:00',
      ),
      body: 'history body',
      bodySegments: const [ThreadContentSegment.text('history body')],
      replies: const [],
      pagination: const ThreadPagination(currentPage: 1, totalPages: 1),
    );
  }
}

const _onePixelPng = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

class _CachedProfileRepository extends ForumRepository {
  _CachedProfileRepository();

  final _overviewCompleter = Completer<UserProfile>();
  final _detailsCompleter = Completer<UserProfile>();

  static const cached = UserProfile(
    uid: '1',
    name: 'Cached Alice',
    url: 'https://south-plus.net/u.php?action-show-uid-1.html',
    tagline: '缓存签名',
    level: 'Lv.2',
    isOnline: true,
    statusText: '在线',
    info: [
      UserProfileField(label: 'UID', value: '1'),
    ],
  );

  static const fresh = UserProfile(
    uid: '1',
    name: 'Fresh Alice',
    url: 'https://south-plus.net/u.php?action-show-uid-1.html',
    tagline: '最新签名',
    level: 'Lv.3',
    isOnline: true,
    statusText: '在线',
    info: [
      UserProfileField(label: 'UID', value: '1'),
    ],
  );

  @override
  Future<UserProfile?> cachedUserProfileOverview(String url) async => cached;

  @override
  Future<UserProfile> fetchUserProfileOverview(String url) {
    return _overviewCompleter.future;
  }

  @override
  Future<UserProfile> fetchUserProfileDetails(UserProfile overview) {
    return _detailsCompleter.future;
  }

  void completeFreshOverview() {
    if (_overviewCompleter.isCompleted) return;
    _overviewCompleter.complete(fresh);
  }
}

class _FakeThreadRepository extends ForumRepository {
  _FakeThreadRepository({
    this.initialPage = 2,
    this.failPages = const {},
    this.emptyAuthorFilter = false,
  });

  final int initialPage;
  final Set<int> failPages;
  final bool emptyAuthorFilter;
  final requestedPages = <int>[];
  final requestedThreadUrls = <String>[];
  final requestedQuoteUrls = <String>[];

  static const thread = ForumThread(
    title: '测试主题',
    url: 'https://south-plus.net/read.php?tid-1.html',
    replies: 3,
    section: '事务受理',
    author: 'Alice',
    authorUrl: 'https://south-plus.net/u.php?action-show-uid-1.html',
  );

  @override
  Future<ThreadDetail> fetchThreadDetail(
    ForumThread thread, {
    int page = 1,
  }) async {
    requestedThreadUrls.add(thread.url);
    final requested = requestedPages.isEmpty ? initialPage : page;
    requestedPages.add(page);
    if (failPages.contains(requested)) {
      throw 'boom page $requested';
    }
    if (thread.url.contains('uid-1')) {
      final current = requested.clamp(1, 2).toInt();
      return ThreadDetail(
        thread: thread.copyWith(
          author: 'Alice',
          authorPostsUrl: 'https://south-plus.net/read.php?tid-1-uid-1.html',
          lastPost: '2026-05-30 10:00',
        ),
        body: current == 1 ? 'op filtered page 1' : '',
        bodySegments: current == 1
            ? [const ThreadContentSegment.text('op filtered page 1')]
            : const [],
        replies: [
          if (current == 2)
            const ThreadReply(
              author: 'Alice',
              content: 'op filtered page 2',
              segments: [ThreadContentSegment.text('op filtered page 2')],
              floor: 'B9F',
              postedAt: '2026-05-30 12:00',
            ),
        ],
        pagination: ThreadPagination(currentPage: current, totalPages: 2),
      );
    }
    if (thread.url.contains('uid-2')) {
      if (emptyAuthorFilter) {
        return ThreadDetail(
          thread: thread.copyWith(
            author: 'Alice',
            authorPostsUrl: 'https://south-plus.net/read.php?tid-1-uid-1.html',
            lastPost: '2026-05-30 10:00',
          ),
          body: '',
          replies: const [],
          pagination: const ThreadPagination(currentPage: 1, totalPages: 1),
        );
      }
      return ThreadDetail(
        thread: thread.copyWith(
          author: 'Alice',
          authorPostsUrl: 'https://south-plus.net/read.php?tid-1-uid-1.html',
          lastPost: '2026-05-30 10:00',
        ),
        body: '',
        replies: const [
          ThreadReply(
            author: 'Bob',
            content: 'bob filtered page 1',
            segments: [ThreadContentSegment.text('bob filtered page 1')],
            floor: 'B2F',
            postedAt: '2026-05-30 11:00',
          ),
        ],
        pagination: const ThreadPagination(currentPage: 1, totalPages: 1),
      );
    }
    final current = requested.clamp(1, 4).toInt();
    final openingPage = current == 1;
    return ThreadDetail(
      thread: thread.copyWith(
        author: 'Alice',
        authorAvatarUrl: openingPage ? null : thread.authorAvatarUrl,
        authorPostsUrl: 'https://south-plus.net/read.php?tid-1-uid-1.html',
        lastPost: '2026-05-30 10:00',
      ),
      body: openingPage ? 'page $current body' : '',
      bodySegments: openingPage
          ? [ThreadContentSegment.text('page $current body')]
          : const [],
      replies: [
        ThreadReply(
          author: 'Bob',
          authorAvatarUrl: null,
          content: 'reply on page $current',
          segments: [ThreadContentSegment.text('reply on page $current')],
          authorPostsUrl: 'https://south-plus.net/read.php?tid-1-uid-2.html',
          quoteUrl:
              'https://south-plus.net/post.php?action-quote-fid-2-tid-1-pid-${current}0-article-1.html',
          floor: 'B${current}F',
          postedAt: '2026-05-30 11:00',
        ),
      ],
      pagination: ThreadPagination(currentPage: current, totalPages: 4),
      previousThread: const ThreadActionLink(
        label: '上一主题',
        url:
            'https://south-plus.net/job.php?action-previous-fid-2-tid-1-fpage-0-goto-previous.html',
      ),
      nextThread: const ThreadActionLink(
        label: '下一主题',
        url:
            'https://south-plus.net/job.php?action-previous-fid-2-tid-1-fpage-0-goto-next.html',
      ),
      rssFeed: const ThreadActionLink(
        label: 'Rss订阅本帖最新内容',
        url: 'https://south-plus.net/rss.php?tid=1',
      ),
    );
  }

  @override
  Future<String?> fetchQuoteDraft(ThreadReply reply) async {
    requestedQuoteUrls.add(reply.quoteUrl!);
    return '[quote]server quote from ${reply.author}[/quote]';
  }
}
