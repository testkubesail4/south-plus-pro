import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/native_form_fields.dart';
import 'package:south_plus_rewrite/features/profile/account_profile_edit_screen.dart';
import 'package:south_plus_rewrite/features/profile/avatar_crop.dart';
import 'package:south_plus_rewrite/models/forum_account_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// Synthetic pictures only. Decoding and encoding run on the real engine, so
// every wait goes through runAsync.

Future<void> _settle(WidgetTester tester, [int rounds = 12]) async {
  for (var i = 0; i < rounds; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// 360 x 240: red, green and yellow bands of 120 pixels each.
Future<ForumAccountUpload> _bands(WidgetTester tester) async {
  final upload = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const colors = [Color(0xFFE61E1E), Color(0xFF1EC83C), Color(0xFFFADC14)];
    for (var i = 0; i < 3; i++) {
      canvas.drawRect(
          Rect.fromLTWH(i * 120.0, 0, 120, 240), Paint()..color = colors[i]);
    }
    final image = await recorder.endRecording().toImage(360, 240);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return ForumAccountUpload(
        bytes: data!.buffer.asUint8List(),
        fileName: 'bands.png',
        mimeType: 'image/png');
  });
  return upload!;
}

/// Two frames of 1 x 1; written by hand, so the test needs no encoder.
ForumAccountUpload _animatedGif() {
  const frame = [
    0x21, 0xF9, 0x04, 0x00, 0x0A, 0x00, 0x00, 0x00, // frame timing
    0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0, // 1 x 1 image
    0x02, 0x02, 0x44, 0x01, 0x00, // pixel data
  ];
  return ForumAccountUpload(
    bytes: Uint8List.fromList([
      ...'GIF89a'.codeUnits, 1, 0, 1, 0, 0x80, 0, 0, // header, 2 colours
      0, 0, 0, 0xFF, 0xFF, 0xFF,
      0x21, 0xFF, 0x0B, ...'NETSCAPE2.0'.codeUnits, 3, 1, 0, 0, 0, // loop
      ...frame, ...frame,
      0x3B,
    ]),
    fileName: 'spin.gif',
    mimeType: 'image/gif',
  );
}

class _Pixels {
  _Pixels(this.width, this.height, this.rgba);
  final int width;
  final int height;
  final Uint8List rgba;

  bool is_(int x, int y, int r, int g, int b) {
    final i = (y * width + x) * 4;
    return (rgba[i] - r).abs() < 12 &&
        (rgba[i + 1] - g).abs() < 12 &&
        (rgba[i + 2] - b).abs() < 12;
  }
}

Future<_Pixels> _decode(WidgetTester tester, Uint8List png) async {
  final pixels = await tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData();
    final result = _Pixels(
        frame.image.width, frame.image.height, data!.buffer.asUint8List());
    frame.image.dispose();
    codec.dispose();
    return result;
  });
  return pixels!;
}

NativeFormController _controller() => NativeFormController(
    ForumAccountForm(kind: ForumAccountFormKind.profile, fields: const []));

/// Opens the crop route from a button and reports how it ended.
class _Harness {
  ForumAccountUpload? result;
  var done = false;

  Future<void> open(WidgetTester tester, ForumAccountUpload source) async {
    final controller = _controller();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => cropAvatar(context, source, controller).then((r) {
              result = r;
              done = true;
            }),
            child: const Text('开始'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('开始'));
    await _settle(tester);
  }
}

void main() {
  // The repository reads its saved address from preferences.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the default square is what the frame shows, as PNG',
      (tester) async {
    final harness = _Harness();
    await harness.open(tester, await _bands(tester));
    expect(find.byKey(const Key('avatar-crop-screen')), findsOneWidget);
    expect(find.textContaining('240 × 240 像素 PNG'), findsOneWidget);
    await tester.tap(find.byKey(const Key('avatar-crop-confirm')));
    await _settle(tester);
    expect(harness.done, isTrue);
    final out = harness.result!;
    expect(out.fileName, 'avatar.png');
    expect(out.mimeType, 'image/png');
    final p = await _decode(tester, out.bytes);
    expect([p.width, p.height], [240, 240]);
    // The middle 240 columns of 360: part red, all green, part yellow.
    expect(p.is_(5, 120, 230, 30, 30), isTrue);
    expect(p.is_(120, 120, 30, 200, 60), isTrue);
    expect(p.is_(235, 120, 250, 220, 20), isTrue);
  });

  testWidgets('zooming and panning change the pixels that are uploaded',
      (tester) async {
    final harness = _Harness();
    await harness.open(tester, await _bands(tester));
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    }
    for (var i = 0; i < 80; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    await tester.tap(find.byKey(const Key('avatar-crop-confirm')));
    await _settle(tester);
    final p = await _decode(tester, harness.result!.bytes);
    // Twice the zoom is half the side, pinned to the yellow right edge.
    expect([p.width, p.height], [120, 120]);
    for (final (x, y) in [(2, 2), (60, 60), (117, 117), (2, 117)]) {
      expect(p.is_(x, y, 250, 220, 20), isTrue, reason: '$x,$y');
    }
  });

  testWidgets('cancelling returns nothing', (tester) async {
    final harness = _Harness();
    await harness.open(tester, await _bands(tester));
    await tester.tap(find.byKey(const Key('avatar-crop-cancel')));
    await _settle(tester);
    expect(harness.done, isTrue);
    expect(harness.result, isNull);
    expect(find.byKey(const Key('avatar-crop-screen')), findsNothing);
  });

  testWidgets('a file that is no picture ends in a message, not a crop',
      (tester) async {
    final harness = _Harness();
    await harness.open(
        tester,
        ForumAccountUpload(
            bytes: Uint8List.fromList([1, 2, 3]),
            fileName: 'a.png',
            mimeType: 'image/png'));
    expect(find.text('无法读取这张图片'), findsOneWidget);
    expect(find.byKey(const Key('avatar-crop-confirm')), findsNothing);
    await tester.tap(find.byKey(const Key('avatar-crop-cancel')));
    await _settle(tester);
    expect(harness.result, isNull);
  });

  testWidgets('an animated picture is kept whole unless a still is chosen',
      (tester) async {
    final gif = _animatedGif();
    final keep = _Harness();
    await keep.open(tester, gif);
    expect(find.textContaining('这是一张动图'), findsOneWidget);
    await tester.tap(find.byKey(const Key('avatar-crop-original')));
    await _settle(tester);
    expect(identical(keep.result, gif), isTrue);

    final still = _Harness();
    await still.open(tester, gif);
    await tester.tap(find.byKey(const Key('avatar-crop-still')));
    await _settle(tester);
    expect(find.byKey(const Key('avatar-crop-confirm')), findsOneWidget);
    await tester.tap(find.byKey(const Key('avatar-crop-confirm')));
    await _settle(tester);
    expect(still.result!.mimeType, 'image/png');
    expect(still.result!.fileName, 'avatar.png');
  });

  testWidgets('a picked picture is cropped, saved as that PNG, and shown',
      (tester) async {
    final repo = _UploadRepo();
    final source = await _bands(tester);
    await tester.pumpWidget(MaterialApp(
      home: AccountProfileEditScreen(
          repository: repo, avatarPicker: () async => source),
    ));
    await _settle(tester, 3);
    await tester.tap(find.text('选择图片'));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('avatar-crop-confirm')));
    await _settle(tester);
    // The blank native width starts at the widest the forum allows.
    expect(find.textContaining('avatar.png'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await _settle(tester);
    expect(repo.saved, {
      'uploadurl[1]': ['150']
    });
    final sent = repo.savedUpload!;
    expect([sent.fileName, sent.mimeType], ['avatar.png', 'image/png']);
    final p = await _decode(tester, sent.bytes);
    expect([p.width, p.height], [240, 240]);
    expect(p.is_(120, 120, 30, 200, 60), isTrue);
  });

  testWidgets(
      'a forum that takes only PNG still takes a GIF through the crop, '
      'not as the original', (tester) async {
    final gif = _animatedGif();
    for (final keep in [false, true]) {
      final repo = _UploadRepo(accept: 'image/png');
      await tester.pumpWidget(MaterialApp(
        home: AccountProfileEditScreen(
            key: UniqueKey(), repository: repo, avatarPicker: () async => gif),
      ));
      await _settle(tester, 3);
      await tester.tap(find.text('选择图片'));
      await _settle(tester);
      await tester.tap(
          find.byKey(Key(keep ? 'avatar-crop-original' : 'avatar-crop-still')));
      await _settle(tester);
      if (!keep) await tester.tap(find.byKey(const Key('avatar-crop-confirm')));
      await _settle(tester);
      // The original GIF is judged as it is and refused; the still is a PNG.
      expect(find.textContaining('avatar.png'),
          keep ? findsNothing : findsOneWidget);
      expect(
          find.textContaining('论坛只接受'), keep ? findsOneWidget : findsNothing);
    }
  });

  testWidgets('cancelling the crop keeps the form as it was', (tester) async {
    final repo = _UploadRepo();
    final source = await _bands(tester);
    await tester.pumpWidget(MaterialApp(
      home: AccountProfileEditScreen(
          repository: repo, avatarPicker: () async => source),
    ));
    await _settle(tester, 3);
    await tester.tap(find.text('选择图片'));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('avatar-crop-cancel')));
    await _settle(tester);
    expect(find.text('选择图片'), findsOneWidget);
    expect(find.textContaining('avatar.png'), findsNothing);
    final save =
        tester.widget<TextButton>(find.widgetWithText(TextButton, '保存'));
    expect(save.onPressed, isNull);
  });
}

ForumAccountForm _uploadForm(String? accept) =>
    ForumAccountForm(kind: ForumAccountFormKind.profile, fields: [
      ForumAccountField(
          name: 'field_1',
          label: '昵称',
          type: 'text',
          values: const ['old'],
          group: 'nickname'),
      ForumAccountField(
        name: 'facetype',
        label: '头像类型',
        type: 'radio',
        values: const ['3'],
        group: 'avatar',
        options: const [
          ForumAccountOption(value: '1', label: '系统头像'),
          ForumAccountOption(value: '2', label: '头像链接'),
          ForumAccountOption(value: '3', label: '头像上传'),
        ],
      ),
      ForumAccountField(
          name: 'upload',
          label: '头像上传',
          type: 'file',
          values: const [],
          accept: accept,
          group: 'avatar'),
      ForumAccountField(
          name: 'uploadurl[1]',
          label: '头像宽度',
          type: 'number',
          values: const [''],
          min: 1,
          max: 150,
          group: 'avatar'),
      ForumAccountField(
          name: 'uploadurl[2]',
          label: '头像高度',
          type: 'number',
          values: const [''],
          min: 1,
          max: 270,
          group: 'avatar'),
    ]);

class _UploadRepo extends ForumRepository {
  _UploadRepo({this.accept});

  final String? accept;
  Map<String, List<String>>? saved;
  ForumAccountUpload? savedUpload;

  @override
  Future<ForumAccountForm> fetchAccountProfileForm() async =>
      _uploadForm(accept);

  @override
  Future<void> saveAccountProfileForm(
    ForumAccountForm form,
    Map<String, List<String>> changes, {
    ForumAccountUpload? avatar,
  }) async {
    saved = changes;
    savedUpload = avatar;
  }
}
