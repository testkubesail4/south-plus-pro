import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_linux/path_provider_linux.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/cached_forum_image.dart';
import 'package:south_plus_rewrite/features/thread/thread_image_viewer.dart';
import 'package:south_plus_rewrite/features/thread/thread_rich_content.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/image_loading_settings.dart';

import 'support/image_http_fixture.dart';

const _a = 'https://fixture.invalid/viewer-a.png';
const _b = 'https://fixture.invalid/viewer-b.png';
const _long = 'https://fixture.invalid/viewer-long.png';
const _animation = 'https://fixture.invalid/viewer-animation';
const _offscreenAnimation = 'https://fixture.invalid/viewer-animation-below';
const _redBlueGif =
    'R0lGODlhYABAAYEAAP8AAAAAAAAAAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQACAAAACwAAAAA'
    'YABAAQAI/wABCBxIsKDBgwgTKlzIsKHDhxAjSpxIsaLFixgzatzIsaPHjyBDihxJsqTJkyhT'
    'qlzJsqXLlzBjypxJs6bNmzhz6tzJs6fPn0CDCh1KtKjRo0iTKl3KtKnTp1CjSp1KtarVq1'
    'izat3KtavXr2DDih1LtqzZs2jTql3Ltq3bt3Djyp1Lt67du3jz6t3Lt6/fv4ADCx5MuLDh'
    'w4gTK17MuLHjx5AjS55MubLly5gza97MubPnz6BDix5NurTp06hTq17NurXr17Bjy55Nu7'
    'bt27hz697Nu7fv38CDCx9OvLjx48iTK1/OvLnz59CjS59Ovbr169iza9/Ovbv37+DDixsf'
    'T768+fPo06tfz769+/fw48ufT7++/ftcAwIAIfkEAQgAAQAsAAAAAGAAQAGBAAD/AAAAAAAA'
    'AAAACP8AAQgcSLCgwYMIEypcyLChw4cQI0qcSLGixYsYM2rcyLGjx48gQ4ocSbKkyZMoU6'
    'pcybKly5cwY8qcSbOmzZs4c+rcybOnz59AgwodSrSo0aNIkypdyrSp06dQo0qdSrWq1atYs'
    '2rdyrWr169gw4odS7as2bNo06pdy7at27dw48qdS7eu3bt48+rdy7ev37+AAwseTLiw4cO'
    'IEytezLix48eQI0ueTLmy5cuYM2vezLmz58+gQ4seTbq06dOoU6tezbq169ewY8ueTbu27d'
    'u4c+vezbu379/AgwsfTry48ePIkytfzry58+fQo0ufTr269evYs2vfzr279+/gw4sbH0++'
    'vPnz6NOrX8++vfv38OPLn0+/vv37XAMCADs=';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ImageHttpFixture fixture;
  HttpOverrides? oldOverrides;

  setUpAll(() async {
    oldOverrides = HttpOverrides.current;
    fixture = await ImageHttpFixture.start(
      images: {
        _a: await _png(300, 200),
        _b: await _png(300, 200),
        // 1:40, so filling the width needs more than the 8x pinch limit.
        _long: await _png(100, 4000),
        _animation: base64Decode(_redBlueGif),
        _offscreenAnimation: base64Decode(_redBlueGif),
      },
      imageTypes: {
        _animation: ContentType('image', 'gif'),
        _offscreenAnimation: ContentType('image', 'gif'),
      },
    );
    HttpOverrides.global = fixture;
    PathProviderLinux.registerWith();
    await ForumImageCache.manager.emptyCache();
  });
  tearDownAll(() async {
    HttpOverrides.global = oldOverrides;
    await fixture.close();
  });

  Future<void> settle(WidgetTester tester, {bool Function()? ready}) async {
    // Wait for real I/O only when needed; advance UI animation time virtually.
    for (var i = 0; ready != null && !ready() && i < 200; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (ready != null) expect(ready(), isTrue, reason: 'viewer I/O completed');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  const firstFrame = {0xff0000ff};
  const animation = {0xff0000ff, 0x0000ffff};

  Future<Set<int>> colorsSeen(WidgetTester tester, Finder image,
      {required bool waitForChange}) async {
    final colors = <int>{};
    for (var i = 0; i < (waitForChange ? 60 : 12); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 15));
      await tester.pump(const Duration(milliseconds: 80));
      final frame = tester.widget<RawImage>(image).image!;
      final pixels = await frame.toByteData();
      colors.add(pixels!.getUint32(0));
      if (waitForChange && colors.length == 2) break;
    }
    return colors;
  }

  // Real timers run inside runAsync; a second tap needs kDoubleTapMinTime.
  Future<void> doubleTap(WidgetTester tester) async {
    await tester.tap(find.byType(InteractiveViewer));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.tap(find.byType(InteractiveViewer));
  }

  double scale(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!
      .value
      .getMaxScaleOnAxis();

  Future<void> openViewer(
    WidgetTester tester, {
    bool private = false,
    List<ThreadContentSegment> segments = const [
      ThreadContentSegment.image(url: _a),
      ThreadContentSegment.quote([
        ThreadContentSegment.image(url: _long),
      ]),
      ThreadContentSegment.image(url: _b),
    ],
    Future<void> Function(String url, String label)? onOpenLink,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    await ImageLoadingSettings.saveMode(ImageLoadMode.automatic);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ThreadRichContent(
            privateMedia: private,
            onOpenLink: onOpenLink,
            segments: segments,
          ),
        ),
      ),
    ));
    final decoded = find.byWidgetPredicate(
        (widget) => widget is RawImage && widget.image != null);
    final image = find.byType(ThreadInlineImage).at(1);
    await settle(tester,
        ready: () => find
            .descendant(of: image, matching: decoded)
            .evaluate()
            .isNotEmpty);
    await tester.tap(image);
    await settle(tester,
        ready: () => find
            .descendant(of: find.byType(Dialog), matching: decoded)
            .evaluate()
            .isNotEmpty);
  }

  testWidgets('inline GIFs pause during scrolling and play only in view',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final scroll = ScrollController();
    addTearDown(scroll.dispose);

    await tester.runAsync(() async {
      await ImageLoadingSettings.saveMode(ImageLoadMode.automatic);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScrollNotificationObserver(
            child: SingleChildScrollView(
              controller: scroll,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 48,
                    child:
                        ThreadInlineImage(image: ThreadImage(url: _animation)),
                  ),
                  SizedBox(height: 900),
                  SizedBox(
                    width: 48,
                    child: ThreadInlineImage(
                      image: ThreadImage(url: _offscreenAnimation),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ));
      final images = find.byWidgetPredicate(
        (widget) => widget is RawImage && widget.image != null,
      );
      final inline = find.byType(ThreadInlineImage).first;
      final second = find.byType(ThreadInlineImage).last;
      final visible = find.descendant(of: inline, matching: images);
      final offscreen = find.descendant(
        of: second,
        matching: images,
      );
      await settle(tester, ready: () => offscreen.evaluate().isNotEmpty);
      final painted = tester.widget<RawImage>(offscreen).image!;
      expect((painted.width, painted.height), (48, 160));

      await settle(tester, ready: () => visible.evaluate().isNotEmpty);
      expect(await colorsSeen(tester, visible, waitForChange: true), animation);
      expect(await colorsSeen(tester, offscreen, waitForChange: false),
          firstFrame);

      final drag = await tester.startGesture(tester.getCenter(inline));
      await drag.moveBy(const Offset(0, -32));
      await drag.moveBy(const Offset(0, -32));
      await tester.pump();
      await settle(tester,
          ready: () => tester.widget<RawImage>(visible).image!.width == 48);
      expect(
          await colorsSeen(tester, visible, waitForChange: false), firstFrame);
      await drag.up();
      expect(await colorsSeen(tester, visible, waitForChange: true), animation);

      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      await tester.pump();
      expect(
          await colorsSeen(tester, visible, waitForChange: false), firstFrame);
      expect(
          await colorsSeen(tester, offscreen, waitForChange: true), animation);

      await tester.tap(second);
      final viewer = find.descendant(of: find.byType(Dialog), matching: images);
      await settle(tester, ready: () => viewer.evaluate().isNotEmpty);
      expect(await colorsSeen(tester, viewer, waitForChange: true), animation);
      expect(fixture.requests.where((url) => url == _animation), hasLength(1));
      expect(fixture.requests.where((url) => url == _offscreenAnimation),
          hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('GIF playback follows the outer viewport of nested post tables',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      await ImageLoadingSettings.saveMode(ImageLoadMode.automatic);
      ThreadContentTableCell nestedImage(String url) => ThreadContentTableCell([
            ThreadContentSegment.table([
              [
                ThreadContentTableCell([ThreadContentSegment.image(url: url)])
              ],
            ]),
          ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScrollNotificationObserver(
            child: SingleChildScrollView(
              child: ThreadRichContent(segments: [
                ThreadContentSegment.table([
                  [
                    nestedImage(_animation),
                    ...List.filled(5, const ThreadContentTableCell([])),
                    nestedImage(_offscreenAnimation),
                  ],
                ]),
              ]),
            ),
          ),
        ),
      ));
      final images = find.byWidgetPredicate(
        (widget) => widget is RawImage && widget.image != null,
      );
      final cells = find.byType(ThreadInlineImage);
      final left = find.descendant(of: cells.first, matching: images);
      final right = find.descendant(of: cells.last, matching: images);
      await settle(tester, ready: () => images.evaluate().length == 2);
      expect(await colorsSeen(tester, left, waitForChange: true), animation);
      expect(await colorsSeen(tester, right, waitForChange: false), firstFrame);

      final horizontal = tester
          .stateList<ScrollableState>(find.byType(Scrollable))
          .firstWhere((state) =>
              axisDirectionToAxis(state.axisDirection) == Axis.horizontal);
      horizontal.position.jumpTo(horizontal.position.maxScrollExtent);
      await tester.pump();
      await tester.pump();
      expect(await colorsSeen(tester, left, waitForChange: false), firstFrame,
          reason: 'a GIF that leaves the outer horizontal viewport must stop');
      expect(await colorsSeen(tester, right, waitForChange: true), animation);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('pages through every image of the post, quotes included',
      (tester) async {
    await tester.runAsync(() async {
      await openViewer(tester);
      expect(find.text('2 / 3'), findsOneWidget);

      await tester.tap(find.byTooltip('下一张'));
      await settle(tester);
      expect(find.text('3 / 3'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await settle(tester);
      expect(find.text('2 / 3'), findsOneWidget);

      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await settle(tester);
      expect(find.text('3 / 3'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('reduced motion turns to the next image at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.runAsync(() async {
      await openViewer(tester);
      await tester.tap(find.byTooltip('下一张'));
      await tester.pump();
      expect(find.text('3 / 3'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('a repeated image opens its own occurrence and link',
      (tester) async {
    await tester.runAsync(() async {
      final opened = <String>[];
      await openViewer(
        tester,
        segments: const [
          ThreadContentSegment.image(
              url: _a, href: 'https://fixture.invalid/1'),
          ThreadContentSegment.image(
              url: _a, href: 'https://fixture.invalid/2'),
        ],
        onOpenLink: (url, label) async => opened.add(url),
      );
      expect(find.text('2 / 2'), findsOneWidget);
      await tester.tap(find.text('打开链接'));
      await settle(tester);
      expect(opened, ['https://fixture.invalid/2']);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('save feedback shows in the viewer; closing mid-save is safe',
      (tester) async {
    await tester.runAsync(() async {
      const channel = MethodChannel('south_plus_rewrite/image_saver');
      final messenger = tester.binding.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'save_failed', message: 'disk full');
      });
      await openViewer(tester);
      await tester.tap(find.text('保存图片'));
      await settle(tester,
          ready: () => find.text('保存图片失败：disk full').evaluate().isNotEmpty);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('保存图片失败：disk full'),
        ),
        findsOneWidget,
      );
      tester
          .state<ScaffoldMessengerState>(find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(ScaffoldMessenger),
          ))
          .removeCurrentSnackBar();
      await settle(tester);

      var calls = 0;
      final release = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls++;
        await release.future;
        return 'saved';
      });
      await tester.tap(find.text('保存图片'));
      await settle(tester, ready: () => calls == 1);
      await tester.tap(find.text('保存图片'));
      await settle(tester);
      await tester.tap(find.byTooltip('关闭'));
      await settle(tester);
      release.complete();
      await settle(tester);
      expect(calls, 1, reason: 'one save at a time per image');
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('zooms by buttons, keys, wheel and double tap; long fills width',
      (tester) async {
    await tester.runAsync(() async {
      await openViewer(tester);
      await tester.tap(find.byTooltip('放大'));
      await tester.pump();
      expect(scale(tester), closeTo(1.5, 0.01));
      // Zoomed images pan instead of turning the page.
      expect(
        tester.widget<PageView>(find.byType(PageView)).physics,
        isA<NeverScrollableScrollPhysics>(),
      );
      await tester.tap(find.byTooltip('缩小'));
      await tester.pump();
      expect(scale(tester), 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.pump();
      expect(scale(tester), closeTo(1.5, 0.01));
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.pump();
      expect(scale(tester), 1);

      final centre = tester.getCenter(find.byType(InteractiveViewer));
      tester.binding.handlePointerEvent(PointerScrollEvent(
        position: centre,
        scrollDelta: const Offset(0, -100),
      ));
      await tester.pump();
      expect(scale(tester), greaterThan(1));
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.pump();

      // The long image's double tap fills the width from its top edge.
      final viewport = tester.getSize(find.byType(InteractiveViewer));
      final raw = find.descendant(
        of: find.byType(InteractiveViewer),
        matching: find.byType(RawImage),
      );
      final shown = tester.getSize(raw);
      await doubleTap(tester);
      await settle(tester);
      expect(scale(tester), closeTo(viewport.width / shown.width, 0.01));
      final rect = tester.getRect(raw);
      final top = tester.getTopLeft(find.byType(InteractiveViewer));
      expect(rect.left, closeTo(top.dx, 0.5));
      expect(rect.top, closeTo(top.dy, 0.5));

      await doubleTap(tester);
      await settle(tester);
      expect(scale(tester), 1);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('no-images policy shares no public image bytes', (tester) async {
    await tester.runAsync(() async {
      const channel = MethodChannel('south_plus_rewrite/image_saver');
      final messenger = tester.binding.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await openViewer(tester);
      await ImageLoadingSettings.saveMode(ImageLoadMode.noImages);
      addTearDown(() => ImageLoadingSettings.saveMode(ImageLoadMode.automatic));
      await settle(tester);
      await tester.tap(find.byTooltip('更多'));
      await settle(tester);
      expect(find.text('复制图片链接'), findsOneWidget);
      expect(find.text('分享图片'), findsNothing);

      // A share started before the switch still checks the latest policy.
      const unseen = 'https://fixture.invalid/never-fetched.png';
      final context = tester.element(find.text('复制图片链接'));
      await shareForumImage(context, unseen, privateMedia: false);
      expect(calls, isEmpty);
      expect(fixture.requests, isNot(contains(unseen)));
      expect(await ForumImageCache.manager.getFileFromCache(unseen), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  for (final private in [false, true]) {
    testWidgets('long press offers image actions (private: $private)',
        (tester) async {
      await tester.runAsync(() async {
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
        addTearDown(() => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null));
        await openViewer(tester, private: private);
        final press = await tester.startGesture(
          tester.getCenter(find.byType(InteractiveViewer)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await tester.pump(const Duration(milliseconds: 600));
        await press.up();
        await settle(tester);
        expect(find.text('保存图片'), private ? findsNothing : findsNWidgets(2));
        expect(find.text('在浏览器打开图片'), findsOneWidget);
        await tester.tap(find.text('复制图片链接'));
        await settle(tester);
        expect(copied, _long);

        // Public images share the cached file; private ones only the link.
        final shared = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('south_plus_rewrite/image_saver'),
          (call) async {
            shared.add(call);
            return true;
          },
        );
        addTearDown(() => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(
                const MethodChannel('south_plus_rewrite/image_saver'), null));
        final press2 = await tester.startGesture(
          tester.getCenter(find.byType(InteractiveViewer)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await tester.pump(const Duration(milliseconds: 600));
        await press2.up();
        await settle(tester);
        await tester.tap(find.text(private ? '分享图片链接' : '分享图片'));
        await settle(tester, ready: () => shared.isNotEmpty);
        expect(shared.single.method, private ? 'shareText' : 'shareImage');
        final args = shared.single.arguments as Map;
        if (private) {
          expect(args['text'], _long);
        } else {
          final file = await ForumImageCache.manager.getFileFromCache(_long);
          expect(args['path'], file!.file.path);
        }
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
