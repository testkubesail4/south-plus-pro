import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/auth/login_screen.dart';
import 'package:south_plus_rewrite/features/common/app_switcher.dart';
import 'package:south_plus_rewrite/features/common/async_state_view.dart';
import 'package:south_plus_rewrite/features/common/native_form_fields.dart';
import 'package:south_plus_rewrite/features/messages/pm_detail_screen.dart';
import 'package:south_plus_rewrite/features/profile/account_profile_edit_screen.dart';
import 'package:south_plus_rewrite/models/forum_account_models.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

import 'app_redesign_fixture.dart';
import 'app_redesign_paint_fixture.dart';

const _root = ValueKey('loading-paint-root');
const _message = ForumPmSummary(
  box: ForumPmBox.inbox,
  type: ForumPmType.personal,
  id: '14',
  peer: 'fixture-peer',
  title: 'Private title',
  time: '2026-01-01',
  detailPath: 'message.php?action-read-mid-14.html',
);

class _Repository extends AppRedesignRepository {
  final message = Completer<ForumPmDetail>();
  final challenge = Completer<LoginChallenge>();

  @override
  Future<ForumPmDetail> fetchPmDetail(ForumPmSummary summary) => message.future;

  @override
  Future<LoginChallenge> fetchLoginChallenge() => challenge.future;

  @override
  Future<ForumAccountForm> fetchAccountProfileForm() async => ForumAccountForm(
        kind: ForumAccountFormKind.profile,
        fields: [
          ForumAccountField(
            name: 'facetype',
            label: '头像方式',
            type: 'radio',
            values: const ['1'],
            group: 'avatar',
            options: const [
              ForumAccountOption(value: '1', label: '系统头像'),
              ForumAccountOption(value: '2', label: '头像链接'),
            ],
          ),
          ForumAccountField(
            name: 'proicon',
            label: '系统头像',
            type: 'system-avatar',
            values: const [''],
            group: 'avatar',
          ),
          ForumAccountField(
            name: 'httpurl[0]',
            label: '头像链接',
            type: 'text',
            values: const [''],
            group: 'avatar',
          ),
        ],
      );
}

Future<void> _mount(
  WidgetTester tester,
  Widget page,
  ThemeMode mode, {
  bool reduce = false,
}) async {
  final previousMode = AppThemeController.themeMode;
  addTearDown(() => AppThemeController.notifier.value = previousMode);
  AppThemeController.notifier.value = mode;
  tester.view.physicalSize = const Size(320, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2.3),
          disableAnimations: reduce,
        ),
        child: RepaintBoundary(key: _root, child: child!),
      ),
      home: page,
    ),
  );
  await tester.pump();
}

Future<(Uint8List, double)> _paint(
        WidgetTester tester, Rect region, Color background) =>
    captureRedesignPaint(tester, find.byKey(_root), region, background);

Future<void> _fade(
  WidgetTester tester,
  VoidCallback complete, {
  required bool reduce,
  Rect? region,
}) async {
  final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
  region ??= tester.getRect(find.byWidget(scaffold.body!));
  region = region.intersect(const Rect.fromLTWH(0, 0, 320, 800));
  final background = Theme.of(
    tester.element(find.byType(Scaffold).first),
  ).scaffoldBackgroundColor;
  final before = await _paint(tester, region, background);
  complete();
  await tester.pump();
  await tester.pump();
  final frames = <(Uint8List, double)>[];
  for (var i = 0; i < 16; i++) {
    frames.add(await _paint(tester, region, background));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pumpAndSettle();
  final after = await _paint(tester, region, background);
  if (reduce) {
    expect(
      redesignPaintDifference(frames.first.$1, after.$1),
      lessThan(0.000001),
      reason:
          'The caller, not just the helper, reaches its final paint immediately',
    );
  } else {
    expect(
      frames.any(
        (frame) =>
            redesignPaintDifference(frame.$1, before.$1) > 0.0001 &&
            redesignPaintDifference(frame.$1, after.$1) > 0.0001,
      ),
      isTrue,
      reason: 'A real middle frame differs from both endpoints',
    );
    final minimum = math.min(before.$2, after.$2) * 0.6;
    for (var i = 0; i < frames.length; i++) {
      expect(
        frames[i].$2,
        greaterThanOrEqualTo(minimum),
        reason: 'The changing region retains body ink at ${i * 16}ms',
      );
    }
    debugPrint(
      'LOADING_PAINT before=${before.$2} after=${after.$2} '
      'minimum=${frames.map((f) => f.$2).reduce(math.min)} required=$minimum',
    );
  }
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final reduce in [false, true]) {
      testWidgets('native form body paint at 320x2.3 $mode reduced=$reduce', (
        tester,
      ) async {
        final load = Completer<ForumAccountForm>();
        await _mount(
          tester,
          NativeFormPage(
            title: '论坛偏好',
            sessionEpoch: ValueNotifier(0),
            load: () => load.future,
            save: (_, __, ___) async {},
            builder: (_, c) => [NativeFieldRow(controller: c, name: 'nick')],
          ),
          mode,
          reduce: reduce,
        );
        await _fade(
          tester,
          () => load.complete(
            ForumAccountForm(
              kind: ForumAccountFormKind.preferences,
              fields: [
                ForumAccountField(
                  name: 'nick',
                  label: '昵称',
                  type: 'text',
                  values: const ['fixture name'],
                ),
              ],
            ),
          ),
          reduce: reduce,
        );
        expect(find.text('fixture name'), findsOneWidget);
      });

      testWidgets('PM detail body paint at 320x2.3 $mode reduced=$reduce', (
        tester,
      ) async {
        final repository = _Repository();
        await _mount(
          tester,
          PmDetailScreen(repository: repository, message: _message),
          mode,
          reduce: reduce,
        );
        expect(find.byType(ThreadDetailSkeleton), findsOneWidget);
        await _fade(
          tester,
          () => repository.message.complete(
            ForumPmDetail(
              summary: _message,
              sender: 'fixture peer',
              title: 'Private title',
              time: '2026-01-01',
              content: 'A private message body for this account.',
              replyPath: 'message.php?action-write-remid-14.html',
            ),
          ),
          reduce: reduce,
        );
        final reply = find.text('回复');
        await tester.scrollUntilVisible(
          reply,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(reply.hitTestable(), findsOneWidget);
      });
    }
  }

  for (final reduce in [false, true]) {
    testWidgets(
      'avatar mode has a real intermediate layer at 320x2.3 reduced=$reduce',
      (tester) async {
        await _mount(
          tester,
          AccountProfileEditScreen(repository: _Repository()),
          ThemeMode.dark,
          reduce: reduce,
        );
        await tester.pumpAndSettle();
        final row = find.text('头像方式');
        await tester.ensureVisible(row);
        expect(row.hitTestable(), findsOneWidget);
        await tester.tap(row);
        await tester.pumpAndSettle();
        final choice = find.text('头像链接').last;
        expect(choice.hitTestable(), findsOneWidget);
        await tester.tap(choice);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        final incoming = find.byKey(const ValueKey('httpurl[0]'));
        expect(incoming, findsOneWidget);
        final fade = find
            .ancestor(of: incoming, matching: find.byType(FadeTransition))
            .first;
        final opacity = tester.widget<FadeTransition>(fade).opacity.value;
        expect(opacity, reduce ? 1 : inExclusiveRange(0, 1));
        final old = find.descendant(
          of: find.byType(AccountProfileEditScreen),
          matching: find.text('系统头像'),
        );
        expect(old.hitTestable(), findsNothing);
        await tester.pumpAndSettle();
        expect(old, findsNothing);
        await tester.ensureVisible(incoming);
        expect(incoming.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('captcha paints between spinner and image at 320x2.3 $mode', (
      tester,
    ) async {
      final repository = _Repository();
      await _mount(tester, LoginScreen(repository: repository), mode);
      final spinner = find.byType(CircularProgressIndicator);
      await Scrollable.ensureVisible(tester.element(spinner), alignment: 0.2);
      await tester.pump();
      final switcher =
          find.ancestor(of: spinner, matching: find.byType(AppSwitcher)).first;
      final region = tester.getRect(switcher);
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      await tester.runAsync(
        () => precacheImage(MemoryImage(bytes), tester.element(spinner)),
      );
      await _fade(
        tester,
        () => repository.challenge.complete(
          LoginChallenge(captchaBytes: bytes, fields: const {}),
        ),
        reduce: false,
        region: region,
      );
      expect(spinner, findsNothing);
      final refresh = find.byTooltip('刷新验证码');
      await tester.ensureVisible(refresh);
      expect(refresh.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
