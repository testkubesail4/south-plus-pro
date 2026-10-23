import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/native_form_fields.dart';
import 'package:south_plus_rewrite/features/home/home_shell.dart';
import 'package:south_plus_rewrite/features/profile/account_profile_edit_screen.dart';
import 'package:south_plus_rewrite/features/profile/forum_preferences_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/models/forum_account_models.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_network_setup_store.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_search_preferences.dart';
import 'package:south_plus_rewrite/services/forum_session_store.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

class _FixtureSite extends ForumSite {
  const _FixtureSite() : super('127.0.0.1');

  @override
  Uri get baseUri => Uri.parse('http://127.0.0.1:8765/');
}

const _config = ForumNetworkConfig(
  site: _FixtureSite(),
  mode: ForumNetworkMode.native,
  dohProvider: ForumNetworkConfig.defaultProvider,
);
const _thread = ForumThread(
  title: '本地阅读笔记',
  url: 'http://127.0.0.1:8765/read.php?tid-930002.html',
  replies: 0,
  section: '本地阅读版块',
);

// Distinct corners make moving/zooming the crop independently observable.
Future<Uint8List> _sourceImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (final (rect, color) in [
    (const Rect.fromLTWH(0, 0, 180, 120), const Color(0xffff0000)),
    (const Rect.fromLTWH(180, 0, 180, 120), const Color(0xff00ff00)),
    (const Rect.fromLTWH(0, 120, 180, 120), const Color(0xff0000ff)),
    (const Rect.fromLTWH(180, 120, 180, 120), const Color(0xffffff00)),
  ]) {
    canvas.drawRect(rect, Paint()..color = color);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(360, 240);
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> _expectYellowCrop(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  try {
    expect(image.width, 120, reason: 'zoom 2 halves the 240px short side');
    expect(image.height, 120);
    final pixels =
        (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    for (final y in [12, 60, 108]) {
      for (final x in [12, 60, 108]) {
        final index = (y * image.width + x) * 4;
        expect(
          [
            for (var channel = 0; channel < 4; channel++)
              pixels.getUint8(index + channel)
          ],
          [255, 255, 0, 255],
          reason: 'pan to bottom-right must select the yellow source region',
        );
      }
    }
  } finally {
    image.dispose();
    codec.dispose();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late ForumRepository repository;
  var scale = 2.0;
  var dark = true;
  var reduced = true;
  final frames = <Map<String, Object>>[];
  final output = Platform.environment['SPP_ARTIFACT_DIR'] ?? '/output';

  Future<Uint8List> fixture(String path, {bool reset = false}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = _config.baseUri.resolve(path);
      expect(uri.host, '127.0.0.1');
      final request = await client.openUrl(reset ? 'POST' : 'GET', uri);
      request.headers.set('Cookie', 'appendfix_winduser=synthetic-local-only');
      if (reset) {
        final body = utf8.encode('fixture-only');
        request.contentLength = body.length;
        request.add(body);
      }
      final response = await request.close();
      expect(response.statusCode, 200, reason: path);
      return Uint8List.fromList(await response.fold<List<int>>(
        [],
        (all, bytes) => all..addAll(bytes),
      ));
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> stats() async =>
      jsonDecode(utf8.decode(await fixture('appendfix/stats')))
          as Map<String, dynamic>;

  Future<ForumRepository> restore() async {
    final repo = ForumRepository(config: _config);
    expect(await repo.restoreSession(), isTrue);
    expect(repo.accountIdentity.value?.uid, '930001');
    return repo;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {ForumNetworkSetupStore.completedKey: true});
    await fixture('account-redesign/reset', reset: true);
    await ForumSessionStore().saveCookies({
      'appendfix_winduser': ForumStoredCookie.session(
        name: 'appendfix_winduser',
        value: 'synthetic-local-only',
        origin: _config.baseUri,
      ),
    });
    scale = 2;
    dark = true;
    reduced = true;
    await AppThemeController.setMode(ThemeMode.dark);
    repository = await restore();
  });

  Widget app(Widget home) => MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduced,
          ),
          child: child!,
        ),
        home: home,
      );

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsWidgets);
    expect(tester.takeException(), isNull);
  }

  Future<String> window(WidgetTester tester) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump();
      final result = await Process.run('xdotool',
          ['search', '--onlyvisible', '--name', r'^south_plus_rewrite$']);
      final ids = '${result.stdout}'.trim();
      if (result.exitCode == 0 && ids.isNotEmpty) return ids.split('\n').first;
      await tester.pump(const Duration(milliseconds: 100));
    }
    throw StateError('Native test window was not mapped');
  }

  Future<void> mount(WidgetTester tester, Widget home,
      {bool wide = false}) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app(home));
    final size = wide ? const Size(1100, 800) : const Size(400, 800);
    final result = await Process.run('xdotool', [
      'windowsize',
      await window(tester),
      '${size.width.toInt()}',
      '${size.height.toInt()}',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    await tester.pumpAndSettle();
    expect(tester.view.physicalSize / tester.view.devicePixelRatio, size);
  }

  Future<void> reveal(WidgetTester tester, Finder finder,
      {double? alignment}) async {
    await waitFor(tester, finder);
    final target = finder.first;
    for (var attempt = 0; attempt < 30; attempt++) {
      if (alignment == null) {
        await tester.ensureVisible(target);
      } else {
        await Scrollable.ensureVisible(tester.element(target),
            alignment: alignment);
      }
      await tester.pump();
      final center = tester.getCenter(target);
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      if ((Offset.zero & size).contains(center) &&
          target.hitTestable().evaluate().isNotEmpty) return;
      await tester.pump(const Duration(milliseconds: 100));
    }
    fail('$finder did not become laid out and hit-testable');
  }

  Future<void> tap(WidgetTester tester, Finder finder,
      {bool settle = true}) async {
    await reveal(tester, finder);
    expect(finder.first.hitTestable(), findsOneWidget);
    await tester.tap(finder.first);
    if (settle) await tester.pumpAndSettle();
  }

  Finder textField(String name) => find.descendant(
        of: find.byKey(ValueKey(name)),
        matching: find.byType(TextField),
      );

  Future<void> enter(WidgetTester tester, String name, String value) async {
    final field = textField(name);
    await reveal(tester, field, alignment: 0.35);
    await tester.tap(field);
    await tester.pump();
    await tester.showKeyboard(field);
    final editable =
        find.descendant(of: field, matching: find.byType(EditableText));
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!tester.widget<EditableText>(editable).focusNode.hasFocus &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue,
        reason: '$name must own focus before its single input event');
    await tester.enterText(field, value);
    await tester.pumpAndSettle();
    final focused = FocusManager.instance.primaryFocus;
    expect(tester.widget<TextField>(field).controller?.text, value,
        reason: '$name must display requested "$value" before proceeding; '
            'focus=${focused?.context?.widget.runtimeType}(${focused?.debugLabel})');
    expect(
        tester
            .widget<NativeFieldRow>(find.byKey(ValueKey(name)))
            .controller
            .value(name),
        value,
        reason: '$name must deliver the requested text to the form');
  }

  Future<void> choose(WidgetTester tester, String name, String label) async {
    await tap(tester, find.byKey(ValueKey(name)));
    await tap(tester, find.text(label).last);
  }

  void fullyVisible(WidgetTester tester, Finder finder) {
    final bounds = tester.getRect(finder.first);
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final bars = find.byType(AppBar);
    final top =
        bars.evaluate().isEmpty ? 0.0 : tester.getBottomLeft(bars.first).dy;
    expect(
        bounds.left >= 0 &&
            bounds.right <= size.width &&
            bounds.top >= top &&
            bounds.bottom <= size.height,
        isTrue,
        reason:
            '$finder must be fully visible below the app bar: $bounds in $size');
    expect(finder.first.hitTestable(), findsOneWidget,
        reason: '$finder must also be hit-testable in the captured viewport');
  }

  void formDiagnostic(WidgetTester tester, String stage) {
    final rows = tester
        .widgetList<NativeFieldRow>(find.byType(NativeFieldRow))
        .take(20)
        .toList();
    final controller = rows.first.controller;
    debugPrint('ACCOUNT_FORM_DIAGNOSTIC ${jsonEncode({
          'stage': stage,
          'saveEnabled': tester
                  .widget<TextButton>(find.widgetWithText(TextButton, '保存'))
                  .onPressed !=
              null,
          'dirty': controller.dirty,
          'busy': controller.busy,
          'retired': controller.retired,
          'valid': controller.valid,
          'changes': controller.changes,
          'fields': [
            for (final field in controller.form.fields.take(20))
              {
                'name': field.name,
                'values': controller.values(field.name),
                'error': controller.error(field.name),
                'required': field.required,
                'min': field.min,
                'max': field.max,
              }
          ],
          'textFields': [
            for (final row in rows)
              {
                'name': row.name,
                'controls': [
                  for (final field in tester.widgetList<TextField>(
                      find.descendant(
                          of: find.byWidget(row),
                          matching: find.byType(TextField))))
                    {
                      'value': field.controller?.text,
                      'errorText': field.decoration?.errorText,
                    }
                ],
              }
          ],
          'banners': tester
              .widgetList<NativeFormBanner>(find.byType(NativeFormBanner))
              .map((banner) => banner.message)
              .take(3)
              .toList(),
          'snackbars': tester
              .widgetList<Text>(find.descendant(
                  of: find.byType(SnackBar), matching: find.byType(Text)))
              .map((text) => text.data)
              .take(3)
              .toList(),
        })}');
  }

  Future<void> openFavoriteMenu(WidgetTester tester) async {
    // The header stays busy until the sheet returns; it must not settle globally.
    await tap(tester, find.text('收藏'), settle: false);
    await waitFor(tester, find.text('选择收藏分类'));
    final category = find.byKey(const ValueKey('favorite-category:1'));
    await reveal(tester, category);
    final route = ModalRoute.of(tester.element(category))!;
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (route.animation?.isCompleted == false &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(route.animation?.isCompleted ?? true, isTrue);
    expect(category.hitTestable(), findsOneWidget);
  }

  Future<void> screenshot(WidgetTester tester, String name,
      {bool settle = true, bool inventory = true}) async {
    if (settle) await tester.pumpAndSettle();
    await tester.pump();
    expect(tester.takeException(), isNull, reason: name);
    final path = '$output/$name.png';
    final result =
        await Process.run('import', ['-window', await window(tester), path]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(File(path).lengthSync(), greaterThan(1000));
    if (!inventory) return;
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    frames.add({
      'name': name,
      'path': path,
      'width': size.width.toInt(),
      'height': size.height.toInt(),
      'theme': dark ? 'dark' : 'light',
      'textScale': scale,
      'reducedMotion': reduced,
    });
    File('$output/account-redesign-frames.json').writeAsStringSync(jsonEncode({
      'scope':
          'Loopback native fixture only; injected picker, real built-in crop; no OS picker or live upload proof',
      'frames': frames,
    }));
  }

  Uint8List previewBytes(WidgetTester tester) {
    final image = tester.widget<Image>(find.byWidgetPredicate(
      (widget) => widget is Image && widget.semanticLabel == '新头像预览',
    ));
    final provider = image.image is ResizeImage
        ? (image.image as ResizeImage).imageProvider
        : image.image;
    expect(provider, isA<MemoryImage>());
    return (provider as MemoryImage).bytes;
  }

  testWidgets(
      'native account modes crop pixels upload and explicit failure preserve state',
      (tester) async {
    debugPrint('ACCOUNT_REDESIGN avatar start');
    final semantics = tester.ensureSemantics();
    try {
      final source = await _sourceImage();
      var picks = 0;
      await mount(
          tester,
          AccountProfileEditScreen(
            repository: repository,
            avatarPicker: () async {
              picks++;
              return ForumAccountUpload(
                  bytes: source,
                  fileName: 'corners.png',
                  mimeType: 'image/png');
            },
          ));
      await waitFor(tester, find.text('头像类型'));
      expect(find.text('系统头像'), findsWidgets);
      expect(textField('httpurl[0]'), findsNothing);
      expect(find.text('选择图片'), findsNothing);
      await tap(tester, find.text('头像类型'));
      await tap(tester, find.text('头像链接').last);
      expect(find.text('选择图片'), findsNothing);
      expect(find.text('系统头像'), findsNothing);
      await enter(tester, 'httpurl[0]', 'http://127.0.0.1:8765/fixture.png');
      expect(find.bySemanticsLabel('头像链接'), findsWidgets);
      await tap(tester, find.text('显示尺寸'));
      expect(find.bySemanticsLabel('显示宽度'), findsWidgets);
      final widthSemantics = tester
          .getSemantics(find.bySemanticsLabel('显示宽度').first)
          .getSemanticsData();
      expect(widthSemantics.hint, contains('1 – 150'));
      expect(widthSemantics.hint, contains('必填'));
      expect(find.bySemanticsLabel('显示高度'), findsWidgets);
      final heightSemantics = tester
          .getSemantics(find.bySemanticsLabel('显示高度').first)
          .getSemanticsData();
      expect(heightSemantics.hint, contains('1 – 270'));
      expect(heightSemantics.hint, contains('选填'));
      await enter(tester, 'httpurl[1]', '151');
      expect(find.textContaining('不能大于 150'), findsOneWidget);
      await tap(tester, find.widgetWithText(TextButton, '保存'));
      await waitFor(tester, find.text('请先修正标出的项目'));
      expect((await stats())['attempts'], isEmpty,
          reason: 'invalid native width is rejected before any form request');
      ScaffoldMessenger.of(
              tester.element(find.widgetWithText(TextButton, '保存')))
          .hideCurrentSnackBar();
      await tester.pumpAndSettle();
      await enter(tester, 'httpurl[1]', '150');
      await enter(tester, 'httpurl[2]', '271');
      expect(find.textContaining('不能大于 270'), findsOneWidget);
      await enter(tester, 'httpurl[2]', '');
      expect(find.text('1 – 270 的整数；选填'), findsWidgets);
      formDiagnostic(tester, 'valid-link-before-capture');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await reveal(tester, find.byKey(const ValueKey('httpurl[1]')),
          alignment: 0.1);
      fullyVisible(tester, find.byKey(const ValueKey('httpurl[1]')));
      fullyVisible(tester, find.byKey(const ValueKey('httpurl[2]')));
      await screenshot(tester, 'account_phone-dark2_link-dimensions');
      await tap(tester, find.widgetWithText(TextButton, '保存'));
      formDiagnostic(tester, 'valid-link-after-save');
      try {
        await waitFor(tester, find.text('已保存'));
      } catch (_) {
        formDiagnostic(tester, 'valid-link-save-failed');
        await screenshot(tester, 'failure_account-link-save',
            settle: false, inventory: false);
        rethrow;
      }
      final linked = await stats();
      expect(linked['writes'], ['modify']);
      expect(
          linked['profile']['httpurl[0]'], 'http://127.0.0.1:8765/fixture.png');
      expect(linked['profile']['httpurl[1]'], '150');
      expect(linked['profile']['httpurl[2]'], '');
      await enter(tester, 'httpurl[0]', 'http://127.0.0.1:8765/portrait.png');
      await tap(tester, find.text('头像类型'));
      await tap(tester, find.text('头像上传').last);
      expect(textField('httpurl[0]'), findsNothing);
      expect(find.text('系统头像'), findsNothing);
      await tap(tester, find.text('选择图片'));
      final canvas = find.byKey(const Key('avatar-crop-canvas'));
      await waitFor(tester, canvas);
      await tap(tester, canvas);
      for (var step = 0; step < 4; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      }
      await tester.pump();
      expect(
          tester
              .widget<Slider>(find.byKey(const Key('avatar-crop-zoom')))
              .value,
          2);
      await tester.drag(canvas, const Offset(-600, -600));
      await tester.pumpAndSettle();
      await screenshot(tester, 'account_phone-dark2_crop-pan-zoom');
      await tap(tester, find.byKey(const Key('avatar-crop-confirm')));
      final cropped = Uint8List.fromList(previewBytes(tester));
      await _expectYellowCrop(cropped);
      expect(cropped, isNot(orderedEquals(source)));
      final caption = find.textContaining('新头像');
      await reveal(tester, caption, alignment: 0.3);
      fullyVisible(tester, caption);
      fullyVisible(
          tester,
          find.byWidgetPredicate(
              (widget) => widget is Image && widget.semanticLabel == '新头像预览'));
      await screenshot(tester, 'account_phone-dark2_cropped-preview');
      await tap(tester, find.text('重新选择图片'));
      await waitFor(tester, canvas);
      await tap(tester, find.byKey(const Key('avatar-crop-cancel')));
      expect(picks, 2);
      expect(previewBytes(tester), orderedEquals(cropped));
      expect((await stats())['attempts'], hasLength(1),
          reason:
              'pick, crop and cancel add no requests after the earlier link save');
      await tap(tester, find.text('头像类型'));
      await tap(tester, find.text('系统头像').last);
      expect(find.text('重新选择图片'), findsNothing);
      await tap(tester, find.text('头像类型'));
      await tap(tester, find.text('头像上传').last);
      expect(previewBytes(tester), orderedEquals(cropped),
          reason: 'inactive upload draft survives mode changes');
      await tap(tester, find.widgetWithText(TextButton, '保存'));
      await waitFor(tester, find.text('选择图片'));
      final saved = await stats();
      expect(saved['writes'], ['modify', 'modify']);
      expect(
          (saved['attempts'] as List).map((entry) => entry['action']).toList(),
          ['modify', 'ajaxface', 'modify']);
      expect(saved['profile']['facetype'], '3');
      expect(saved['profile']['uploadurl[1]'], '150');
      expect(saved['profile']['uploadurl[2]'], '');
      expect(
          saved['profile']['httpurl[0]'], 'http://127.0.0.1:8765/fixture.png',
          reason:
              'inactive URL draft must not replace its previously saved value');
      expect(await fixture('account-redesign/upload'), orderedEquals(cropped));
      await _expectYellowCrop(await fixture('account-redesign/upload'));
      final fresh = await (await restore()).fetchAccountProfileForm();
      expect(fresh.field('proicon')?.value, 'upload/930001.png');
      expect(fresh.field('uploadurl[2]')?.value, '');
      await tap(tester, find.text('头像类型'));
      await tap(tester, find.text('头像链接').last);
      expect(tester.widget<TextField>(textField('httpurl[0]')).controller?.text,
          'http://127.0.0.1:8765/portrait.png',
          reason:
              'inactive draft survives successful active-mode save/readback');
      await tap(tester, find.text('头像类型'));
      await tap(tester, find.text('头像上传').last);
      // A real native storage error is a rejected upload, never a final form save.
      await fixture('account-redesign/reject-upload');
      await tap(tester, find.text('选择图片'));
      await waitFor(tester, canvas);
      await tap(tester, find.byKey(const Key('avatar-crop-confirm')));
      final rejectedDraft = Uint8List.fromList(previewBytes(tester));
      await tap(tester, find.widgetWithText(TextButton, '保存'));
      await waitFor(tester, find.textContaining('上传附件失败'));
      final failed = await stats();
      expect(failed['writes'], ['modify', 'modify']);
      expect(
          (failed['attempts'] as List).map((entry) => entry['action']).toList(),
          ['modify', 'ajaxface', 'modify', 'ajaxface']);
      expect(failed['profile']['proicon'], 'upload/930001.png');
      expect(previewBytes(tester), orderedEquals(rejectedDraft));
      expect(await fixture('account-redesign/upload'), orderedEquals(cropped));
      await reveal(tester, find.textContaining('上传附件失败'), alignment: 0.1);
      fullyVisible(tester, find.textContaining('上传附件失败'));
      await screenshot(tester, 'account_phone-dark2_native-upload-error');
      debugPrint('ACCOUNT_REDESIGN avatar complete');
    } finally {
      semantics.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets(
      'native preferences short titles custom date and fresh changed-only readback',
      (tester) async {
    debugPrint('ACCOUNT_REDESIGN preferences start');
    final before =
        Map<String, dynamic>.from((await stats())['preferences'] as Map);
    await mount(tester, ForumPreferencesScreen(repository: repository));
    await waitFor(tester, find.text('私讯黑名单'));
    for (final name in [
      'msggroups[]',
      'banidinfo',
      'friendcheck',
      'timedf',
      'd_type',
      'time_f',
      't_num',
      'p_num',
      'editor',
      'proreceivemail'
    ]) {
      expect(find.byKey(ValueKey(name)), findsOneWidget,
          reason: 'native preference $name remains editable');
    }
    expect(find.textContaining('数字 UID（不是昵称）'), findsOneWidget);
    expect(find.byKey(const ValueKey('date_f')), findsNothing);
    expect(find.textContaining('时间格式(格式如:'), findsNothing,
        reason: 'native paragraph is help, not a title');
    expect(find.text('网页风格'), findsNothing,
        reason: 'default-only skin is not a meaningful choice');
    await choose(tester, 'd_type', '自定义');
    await waitFor(tester, textField('date_f'));
    expect(find.textContaining('示例：2026-03-07'), findsOneWidget);
    await enter(tester, 'date_f', 'yy-m-d');
    expect(find.textContaining('示例：26-3-7'), findsOneWidget);
    await choose(tester, 'time_f', '12 小时制');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await reveal(tester, find.byKey(const ValueKey('date_f')), alignment: 0.25);
    fullyVisible(tester, find.byKey(const ValueKey('date_f')));
    fullyVisible(tester, find.textContaining('示例：26-3-7'));
    expect(find.textContaining('示例：26-3-7').hitTestable(), findsOneWidget);
    await screenshot(tester, 'preferences_phone-dark2_custom-date');
    await choose(tester, 'd_type', '论坛默认');
    expect(textField('date_f'), findsNothing);
    await choose(tester, 'd_type', '自定义');
    expect(tester.widget<TextField>(textField('date_f')).controller?.text,
        'yy-m-d');
    await enter(tester, 'banidinfo', '930004');
    await tap(tester, find.widgetWithText(TextButton, '保存'));
    await waitFor(tester, find.text('已保存'));
    final after = await stats();
    expect(after['writes'], ['bbsset']);
    expect((after['attempts'] as List).length, 1);
    final expected = {
      ...before,
      'd_type': '1',
      'date_f': 'yy-m-d',
      'time_f': '12',
      'banidinfo': '930004'
    };
    expect(after['preferences'], expected,
        reason: 'every untouched native preference retains its original value');
    final fresh = await (await restore()).fetchForumPreferences();
    for (final entry in expected.entries) {
      expect(fresh.field(entry.key)?.value, entry.value,
          reason: 'fresh native GET ${entry.key}');
    }
    scale = 1;
    dark = false;
    reduced = false;
    await AppThemeController.setMode(ThemeMode.light);
    try {
      await mount(tester, ForumPreferencesScreen(repository: await restore()),
          wide: true);
      await waitFor(tester, textField('date_f'));
      expect(tester.widget<TextField>(textField('date_f')).controller?.text,
          'yy-m-d');
      await reveal(tester, find.byKey(const ValueKey('t_num')));
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('t_num')),
              matching: find.text('论坛默认')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('p_num')),
              matching: find.text('论坛默认')),
          findsOneWidget);
      await screenshot(tester, 'preferences_wide-light_saved-default-counts');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await AppThemeController.setMode(ThemeMode.dark);
    }
    debugPrint('ACCOUNT_REDESIGN preferences complete');
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets(
      'native board tree keeps flat contextual pins and favorites require category confirmation',
      (tester) async {
    debugPrint('ACCOUNT_REDESIGN boards and favorites start');
    await ForumSearchPreferences.savePinnedBoards(
      const [ForumSearchPinnedBoard(id: '227', label: '同人志&CG')],
      account: repository.localPreferenceAccount,
    );
    Future<List<String>> pinIds() async => (await ForumSearchPreferences.load(
          account: repository.localPreferenceAccount,
        ))
            .pinnedBoards
            .map((pin) => pin.id)
            .toList();
    await mount(tester, HomeShell(repository: repository));
    final legacyChip = find.widgetWithText(ActionChip, 'CM107 / 同人志&CG');
    await waitFor(tester, legacyChip);
    await tap(tester, legacyChip);
    await waitFor(tester, find.text('置顶阅读指南：本地收藏、用户备注与长标题换行的完整阅读示例'));
    expect(
        (await stats())['reads'],
        contains(predicate<dynamic>((read) =>
            read['path'] == '/thread_new.php' &&
            '${read['query']}'.contains('fid-227'))));
    await mount(tester, HomeShell(repository: repository));
    await waitFor(tester, legacyChip);
    await tap(tester, find.text('编辑'));
    final group = find.byKey(const ValueKey('board-row:g3'));
    await waitFor(tester, group);
    expect(find.byKey(const ValueKey('board-row:3/0')), findsNothing);
    await tap(tester, group);
    expect(find.byKey(const ValueKey('board-row:3/0/0')), findsNothing);
    await tap(tester, find.byKey(const ValueKey('board-row:3/0')));
    await waitFor(tester, find.byKey(const ValueKey('board-row:3/0/0')));
    expect(await pinIds(), ['227'], reason: 'expanding a parent adds nothing');
    await tap(tester, find.byKey(const ValueKey('board-add:3/0')));
    expect(await pinIds(), ['227', '229'],
        reason: 'adding CM108 must not add child230 or its sibling');
    await tap(tester, find.byKey(const ValueKey('board-add:3/0/0')));
    expect(await pinIds(), ['227', '229', '230']);
    await tap(tester, find.byKey(const ValueKey('board-row:3/1')));
    await waitFor(tester, find.byKey(const ValueKey('board-row:3/1/0')));
    final otherChild = tester
        .widget<IconButton>(find.byKey(const ValueKey('board-add:3/1/0')));
    expect(otherChild.onPressed, isNull,
        reason: 'legacy FID227 remains distinct and already pinned');
    await screenshot(tester, 'boards_phone-dark2_duplicate-child-tree');
    await tap(tester, find.text('完成'));
    final newChip = find.widgetWithText(ActionChip, 'CM108 / 同人志&CG');
    await waitFor(tester, newChip);
    expect(legacyChip, findsOneWidget);
    expect(find.byKey(const ValueKey('board-row:3/0')), findsNothing,
        reason: 'saved shortcuts are flat, not a fold tree');
    await reveal(tester, newChip, alignment: 0.55);
    fullyVisible(tester, newChip);
    fullyVisible(tester, find.text('我的版块'));
    fullyVisible(tester, find.text('常用'));
    fullyVisible(tester, find.text('最近'));
    await screenshot(tester, 'boards_phone-dark2_flat-contextual-pins');
    await tap(tester, newChip);
    await waitFor(tester, find.text('置顶阅读指南：本地收藏、用户备注与长标题换行的完整阅读示例'));
    expect(
        (await stats())['reads'],
        contains(predicate<dynamic>((read) =>
            read['path'] == '/thread_new.php' &&
            '${read['query']}'.contains('fid-230'))));
    expect((await stats())['writes'], isEmpty,
        reason: 'pins write only local preferences');

    for (final containsFavoriteWord in [false, true]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await fixture('account-redesign/reset', reset: true);
      if (containsFavoriteWord)
        await fixture('account-redesign/menu-with-favorite-word');
      repository = await restore();
      await mount(
          tester, ThreadDetailScreen(repository: repository, thread: _thread));
      await openFavoriteMenu(tester);
      final categoryLabel = containsFavoriteWord ? '收藏测试分类' : 'SPP-repro-10';
      expect(find.text(categoryLabel), findsOneWidget);
      expect(find.text('已收藏'), findsNothing,
          reason: 'a menu label containing 收藏 is not a success ACK');
      final menuStats = await stats();
      expect(menuStats['writes'], isEmpty);
      expect(menuStats['favorites'], isEmpty);
      final firstAttempts = menuStats['attempts'] as List;
      expect(firstAttempts, isEmpty,
          reason:
              'opening the collection chooser must only read the native list');
      expect(
          menuStats['reads'],
          contains(predicate<dynamic>((read) =>
              read['path'] == '/u.php' &&
              '${read['query']}'.startsWith('action=favor'))));
      await screenshot(
          tester,
          containsFavoriteWord
              ? 'favorites_phone-dark2_collection-word-menu'
              : 'favorites_phone-dark2_native-category-menu',
          settle: false);
      await tap(tester, find.byKey(const ValueKey('favorite-category-cancel')));
      final cancelled = await stats();
      expect(cancelled['attempts'], isEmpty,
          reason: 'cancel must issue no favorite request at all');
      expect(cancelled['favorites'], isEmpty);
      expect(cancelled['writes'], isEmpty);
      expect(find.text('已收藏'), findsNothing);
      expect(utf8.decode(await fixture('u.php?action-favor.html')),
          isNot(contains('value="930002"')));
      await openFavoriteMenu(tester);
      await tap(tester, find.byKey(const ValueKey('favorite-category:1')));
      await waitFor(tester, find.text('已收藏'));
      final confirmed = await stats();
      expect(confirmed['favorites'], {'930002': '1'});
      expect(confirmed['writes'], ['favor']);
      final attempts = confirmed['attempts'] as List;
      expect(attempts, hasLength(1),
          reason: 'two read-only opens then exactly one typed favorite write');
      expect(attempts.single['path'], '/pw_ajax.php');
      expect(attempts.single['query']['tid'], ['930002']);
      expect(attempts.single['query']['type'], ['1']);
      expect((attempts.single['query'] as Map).keys,
          unorderedEquals(['action', 'tid', 'type', 'nowtime', 'verify']));
      final chosenFolder =
          utf8.decode(await fixture('u.php?action=favor&type=1'));
      expect(chosenFolder, contains('value="930002"'));
      expect(chosenFolder, contains(categoryLabel));
      expect(utf8.decode(await fixture('u.php?action=favor&type=0')),
          isNot(contains('value="930002"')));
      expect((await stats())['attempts'], hasLength(1),
          reason: 'fresh folder reads never repeat the mutation');
    }
    debugPrint('ACCOUNT_REDESIGN boards and favorites complete');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
