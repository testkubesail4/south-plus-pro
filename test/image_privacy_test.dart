import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_linux/path_provider_linux.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/cached_forum_image.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_rich_content.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/image_loading_settings.dart';

import 'support/image_http_fixture.dart';

Finder get decodedImages => find.byWidgetPredicate(
      (widget) => widget is RawImage && widget.image != null,
    );

Future<void> waitForImages(WidgetTester tester, int count) async {
  for (var i = 0; i < 100; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));
    if (decodedImages.evaluate().length == count) break;
  }
  expect(decodedImages, findsNWidgets(count));
  expect(tester.takeException(), isNull);
}

Widget frame(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ImageHttpFixture fixture;
  HttpOverrides? oldOverrides;

  setUpAll(() async {
    oldOverrides = HttpOverrides.current;
    fixture = await ImageHttpFixture.start();
    HttpOverrides.global = fixture;
    PathProviderLinux.registerWith();
    await ForumImageCache.manager.emptyCache();
  });
  tearDown(() => ImageLoadingSettings.saveMode(ImageLoadMode.automatic));
  tearDownAll(() async {
    HttpOverrides.global = oldOverrides;
    await fixture.close();
  });

  testWidgets(
    'persisted strict policy prevents unknown startup and every bypass; live restore and manual tap work',
    (tester) async {
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({
          'settings.imageLoadMode': 'noImages',
        });
        await tester.pumpWidget(
          frame(
            const Column(
              children: [
                CachedForumImage(
                  url: ImageHttpFixture.emojiUrl,
                  width: 24,
                  height: 24,
                ),
                CachedForumImage(
                  url: ImageHttpFixture.avatarUrl,
                  width: 48,
                  height: 48,
                  bypassLoadPolicy: true,
                ),
                SizedBox(
                  width: 360,
                  child: ThreadInlineImage(
                    image: ThreadImage(url: ImageHttpFixture.imageUrl),
                  ),
                ),
              ],
            ),
          ),
        );
        expect(find.byType(CachedNetworkImage), findsNothing);
        expect(await ImageLoadingSettings.loadMode(), ImageLoadMode.noImages);
        await tester.pump();
        expect(find.byType(CachedNetworkImage), findsNothing);
        expect(fixture.requests, isEmpty);

        await ImageLoadingSettings.saveMode(ImageLoadMode.automatic);
        await waitForImages(tester, 3);
        expect(
          fixture.requests.toSet(),
          containsAll([
            ImageHttpFixture.emojiUrl,
            ImageHttpFixture.avatarUrl,
            ImageHttpFixture.imageUrl,
          ]),
        );
        final requests = fixture.requests.length;
        await ImageLoadingSettings.saveMode(ImageLoadMode.noImages);
        await tester.pump();
        expect(decodedImages, findsNothing);
        expect(find.byType(CachedNetworkImage), findsNothing);
        expect(find.text('点击加载图片'), findsNothing);
        expect(
          (await SharedPreferences.getInstance()).getString(
            'settings.imageLoadMode',
          ),
          'noImages',
        );
        expect(fixture.requests.length, requests);

        await ImageLoadingSettings.saveMode(ImageLoadMode.manual);
        await waitForImages(tester, 2);
        expect(find.text('点击加载图片'), findsOneWidget);
        await tester.tap(find.text('点击加载图片'));
        await waitForImages(tester, 3);
        await ImageLoadingSettings.saveMode(ImageLoadMode.noImages);
        await tester.pump();
        expect(
          decodedImages,
          findsNothing,
          reason: 'strict hides previously forced and cached images',
        );
        await ImageLoadingSettings.saveMode(ImageLoadMode.automatic);
        await waitForImages(tester, 3);

        await tester.tap(find.byType(ThreadInlineImage));
        await waitForImages(tester, 4);
        await ImageLoadingSettings.saveMode(ImageLoadMode.noImages);
        await tester.pump();
        expect(
          decodedImages,
          findsNothing,
          reason: 'already open full viewer reacts',
        );
        expect(
          tester
              .widget<TextButton>(
                find.ancestor(
                  of: find.text('保存图片'),
                  matching: find.byWidgetPredicate(
                    (widget) => widget is TextButton,
                  ),
                ),
              )
              .onPressed,
          isNull,
        );
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets(
    'thread and profile avatar owners hide real cached imagery without hiding text',
    (tester) async {
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final repository = _AvatarRepository();
        for (final screen in <Widget>[
          ThreadDetailScreen(
            thread: _AvatarRepository.thread,
            repository: repository,
          ),
          UserProfileScreen(
            userUrl: _AvatarRepository.profile.url,
            repository: repository,
          ),
        ]) {
          await ImageLoadingSettings.saveMode(ImageLoadMode.noImages);
          await tester.pumpWidget(MaterialApp(home: screen));
          await tester.pump();
          await tester.pump();
          expect(find.text('Safe Alice'), findsWidgets);
          expect(decodedImages, findsNothing);
          expect(find.byType(CachedNetworkImage), findsNothing);
          expect(
              find.byWidgetPredicate((widget) =>
                  widget is CircleAvatar && widget.backgroundImage != null),
              findsNothing);
          await ImageLoadingSettings.saveMode(ImageLoadMode.automatic);
          await waitForImages(tester, 1);
          expect(fixture.requests, contains(ImageHttpFixture.avatarUrl));
          await ImageLoadingSettings.saveMode(ImageLoadMode.noImages);
          await tester.pump();
          expect(decodedImages, findsNothing);
          expect(find.text('Safe Alice'), findsWidgets);
          await tester.pumpWidget(const SizedBox());
        }
      });
    },
  );

  testWidgets(
    'download screenshot strip and open viewer react while metadata and links survive',
    (tester) async {
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        await ImageLoadingSettings.saveMode(ImageLoadMode.noImages);
        await tester.pumpWidget(
          frame(
            ThreadRichContent(
              segments: const [
                ThreadContentSegment.text(
                  'magnet:?xt=urn:btih:abcdef1234567890abcdef1234567890abcdef12',
                ),
              ],
            ),
          ),
        );
        await tester.tap(find.text('预览'));
        for (var i = 0;
            i < 100 && find.text('Safe sample').evaluate().isEmpty;
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(find.text('Safe sample'), findsOneWidget);
        expect(find.text('1.0 KB'), findsOneWidget);
        expect(find.byType(CachedNetworkImage), findsNothing);
        expect(
          fixture.requests.where(
            (url) => url == ImageHttpFixture.screenshotUrl,
          ),
          isEmpty,
        );
        await ImageLoadingSettings.saveMode(ImageLoadMode.automatic);
        await waitForImages(tester, 1);
        expect(fixture.requests, contains(ImageHttpFixture.screenshotUrl));
        await tester.tap(find.byType(CachedNetworkImage));
        await waitForImages(tester, 2);
        await ImageLoadingSettings.saveMode(ImageLoadMode.noImages);
        await tester.pump();
        expect(decodedImages, findsNothing);
        expect(find.byType(CachedNetworkImage), findsNothing);
        await ImageLoadingSettings.saveMode(ImageLoadMode.automatic);
        await waitForImages(tester, 2);
        await tester.tap(find.byTooltip('关闭'));
        await tester.pump();
        expect(find.text('Safe sample'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('复制'),
          ),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets(
    'rich-content emoji owner and local forum assets obey strict privacy',
    (tester) async {
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        await ImageLoadingSettings.saveMode(ImageLoadMode.manual);
        await tester.pumpWidget(
          frame(
            ThreadRichContent(
              segments: const [
                ThreadContentSegment.image(
                  url: ImageHttpFixture.emojiUrl,
                  isEmoji: true,
                ),
                ThreadContentSegment.image(
                  url:
                      'https://fixture.invalid/images/post/smile/smallface/face002.jpg',
                  isEmoji: true,
                ),
              ],
            ),
          ),
        );
        await waitForImages(tester, 2);
        expect(find.text('点击加载图片'), findsNothing);
        await ImageLoadingSettings.saveMode(ImageLoadMode.noImages);
        await tester.pump();
        expect(decodedImages, findsNothing);
        expect(find.byType(Image), findsNothing);
        expect(find.byType(CachedNetworkImage), findsNothing);
        expect(find.text('点击加载图片'), findsNothing);
        await ImageLoadingSettings.saveMode(ImageLoadMode.automatic);
        await waitForImages(tester, 2);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );
}

class _AvatarRepository extends ForumRepository {
  _AvatarRepository() : super(client: ForumClient(httpClient: HttpClient()));
  static const thread = ForumThread(
    title: 'Safe thread',
    url: 'https://fixture.invalid/thread',
    replies: 0,
    section: 'Test',
    author: 'Safe Alice',
    authorAvatarUrl: ImageHttpFixture.avatarUrl,
  );
  static const profile = UserProfile(
    uid: '1',
    name: 'Safe Alice',
    url: 'https://fixture.invalid/profile',
    avatarUrl: ImageHttpFixture.avatarUrl,
  );
  @override
  Future<ThreadDetail> fetchThreadDetail(
    ForumThread thread, {
    int page = 1,
  }) async =>
      ThreadDetail(
        thread: thread,
        body: 'Safe text',
        replies: const [],
        pagination: const ThreadPagination(currentPage: 1, totalPages: 1),
      );
  @override
  Future<UserProfile?> cachedUserProfileOverview(String url) async => null;
  @override
  Future<UserProfile> fetchUserProfileOverview(String url) async => profile;
  @override
  Future<UserProfile> fetchUserProfileDetails(UserProfile overview) async =>
      overview;
}
