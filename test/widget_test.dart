import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/app.dart';
import 'package:south_plus_rewrite/features/common/async_state_view.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
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
  });

  testWidgets('download links render preview and download actions',
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

    expect(find.text(magnetUrl), findsOneWidget);
    expect(find.text('预览'), findsOneWidget);
    expect(find.text('下载'), findsOneWidget);
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
