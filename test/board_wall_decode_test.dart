import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_linux/path_provider_linux.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/board/board_thread_list_screen.dart';
import 'package:south_plus_rewrite/features/common/cached_forum_image.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/image_loading_settings.dart';

import 'support/image_http_fixture.dart';

// Synthetic board and images only.
const _coverUrl = 'https://fixture.invalid/wall-cover.png';
const _stripUrl = 'https://fixture.invalid/wall-strip.png';

class _Repo extends ForumRepository {
  _Repo(this.url);

  final String url;

  @override
  Future<ForumThreadPage> fetchBoardThreadPage(
    ForumCategory category, {
    int page = 1,
    ForumThreadOrder order = ForumThreadOrder.lastPost,
    ForumBoardFilter? filter,
  }) async =>
      ForumThreadPage(
        threads: [
          ForumThread(
            title: 'Wall topic',
            url: 'https://south-plus.net/read.php?tid-1.html',
            replies: 0,
            section: '',
            previewImageUrl: url,
          ),
        ],
        currentPage: 1,
        totalPages: 1,
        hasPictureWall: true,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ImageHttpFixture fixture;
  HttpOverrides? oldOverrides;
  final repos = <String, _Repo>{};

  setUpAll(() async {
    // Repositories build their own HTTP client, so before the fixture.
    SharedPreferences.setMockInitialValues({});
    for (final url in [_coverUrl, _stripUrl]) {
      repos[url] = _Repo(url);
    }
    oldOverrides = HttpOverrides.current;
    fixture = await ImageHttpFixture.start(images: {
      _coverUrl: await _png(600, 800),
      _stripUrl: await _png(200, 20000),
    });
    HttpOverrides.global = fixture;
    PathProviderLinux.registerWith();
    await ForumImageCache.manager.emptyCache();
  });
  tearDownAll(() async {
    HttpOverrides.global = oldOverrides;
    await fixture.close();
  });

  // A 56 px list thumbnail at 2x fits within 336 px (three tiles) a side.
  final thumbnails = <(String, Size)>[
    // Cover keeps a short side above the tile's 112 px.
    (_coverUrl, const Size(336 * 600 / 800, 336)),
    // A very long strip stays small.
    (_stripUrl, const Size(336 * 200 / 20000, 336)),
  ];
  for (final (url, want) in thumbnails) {
    testWidgets(
        'a list thumbnail decodes ${url.split('/').last} within '
        'its bounds', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await ImageLoadingSettings.saveMode(ImageLoadMode.automatic);
        await tester.pumpWidget(MaterialApp(
          home: BoardThreadListScreen(
            category: const ForumCategory(name: 'Wall', slug: 'fid-936'),
            repository: repos[url]!,
          ),
        ));
        await tester.pumpAndSettle();
        final decoded = find.byWidgetPredicate(
          (widget) => widget is RawImage && widget.image != null,
        );
        for (var i = 0; i < 200 && decoded.evaluate().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(decoded, findsOneWidget, reason: 'resized thumbnail decodes');
        expect(tester.getSize(decoded), const Size(56, 56));
        final image = tester.widget<RawImage>(decoded).image!;
        expect(
          (image.width - want.width).abs() <= 2 &&
              (image.height - want.height).abs() <= 2,
          isTrue,
          reason: 'decoded ${image.width}x${image.height}, want $want',
        );
        await tester.pumpWidget(const SizedBox());
      });
    });
  }

  // (image, decoded size for a 2x card of the given on-screen size)
  final cases = <(String, Size Function(Size card))>[
    // A cover-sized image decodes at the card's pixel width.
    (_coverUrl, (card) => Size(card.width * 2, card.width * 2 * 800 / 600)),
    // A very long strip stays within three cards' height.
    (_stripUrl, (card) => Size(card.height * 6 * 200 / 20000, card.height * 6)),
  ];
  for (final (url, expected) in cases) {
    testWidgets('a wall card decodes ${url.split('/').last} within its bounds',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final repo = repos[url]!;
      await tester.runAsync(() async {
        await ImageLoadingSettings.saveMode(ImageLoadMode.automatic);
        await tester.pumpWidget(MaterialApp(
          home: BoardThreadListScreen(
            category: const ForumCategory(name: 'Wall', slug: 'fid-936'),
            repository: repo,
          ),
        ));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('图墙'));
        // Build the wall before looking, or a decoded list thumbnail counts.
        await tester.pump();
        final decoded = find.byWidgetPredicate(
          (widget) => widget is RawImage && widget.image != null,
        );
        for (var i = 0; i < 200 && decoded.evaluate().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(decoded, findsOneWidget, reason: 'resized wall image decodes');
        final image = tester.widget<RawImage>(decoded).image!;
        final card = tester.getSize(decoded);
        final want = expected(card);
        expect(
          (image.width - want.width).abs() <= 2 &&
              (image.height - want.height).abs() <= 2,
          isTrue,
          reason: 'decoded ${image.width}x${image.height}, want $want '
              'for a $card card',
        );
        await tester.pumpWidget(const SizedBox());
      });
    });
  }
}

Future<List<int>> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF3366CC),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}
