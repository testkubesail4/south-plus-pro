import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_linux/path_provider_linux.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/cached_forum_image.dart';
import 'package:south_plus_rewrite/features/thread/thread_rich_content.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/image_loading_settings.dart';

import 'support/image_http_fixture.dart';

const _a = 'https://fixture.invalid/viewer-a.png';
const _b = 'https://fixture.invalid/viewer-b.png';
const _long = 'https://fixture.invalid/viewer-long.png';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ImageHttpFixture fixture;
  HttpOverrides? oldOverrides;

  setUpAll(() async {
    oldOverrides = HttpOverrides.current;
    fixture = await ImageHttpFixture.start(images: {
      _a: await _png(300, 200),
      _b: await _png(300, 200),
      // 1:40, so filling the width needs more than the 8x pinch limit.
      _long: await _png(100, 4000),
    });
    HttpOverrides.global = fixture;
    PathProviderLinux.registerWith();
    await ForumImageCache.manager.emptyCache();
  });
  tearDownAll(() async {
    HttpOverrides.global = oldOverrides;
    await fixture.close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 50));
    }
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
    await settle(tester);
    await tester.tap(find.byType(ThreadInlineImage).at(1));
    await settle(tester);
  }

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
      await settle(tester);
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
      await settle(tester);
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
