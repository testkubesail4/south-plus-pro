import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/auth/login_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

import 'app_redesign_fixture.dart';

class _ChallengeRepository extends AppRedesignRepository {
  final reads = <Completer<LoginChallenge>>[];

  @override
  Future<LoginChallenge> fetchLoginChallenge() {
    final read = Completer<LoginChallenge>();
    reads.add(read);
    return read.future;
  }
}

LoginChallenge _challenge() => LoginChallenge(
      captchaBytes: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='),
      fields: const {},
    );

Finder _captcha() => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == '验证码');

void main() {
  testWidgets('a refreshed captcha keeps the current keyboard focus',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _ChallengeRepository();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: LoginScreen(repository: repository),
    ));
    await tester.pump(Duration.zero);
    expect(repository.reads, hasLength(1));
    repository.reads.single.complete(_challenge());
    await tester.pumpAndSettle();
    final refresh = find.byTooltip('刷新验证码');
    await tester.ensureVisible(refresh);
    expect(refresh.hitTestable(), findsOneWidget);
    await tester.tap(refresh);
    await tester.pump(Duration.zero);
    expect(repository.reads, hasLength(2));
    // The displayed challenge is editable while the next response is pending.
    await tester.ensureVisible(_captcha());
    await tester.enterText(_captcha(), 'before response');
    final editable =
        find.descendant(of: _captcha(), matching: find.byType(EditableText));
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
    repository.reads.last.complete(_challenge());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final current = tester.widget<EditableText>(find.descendant(
        of: _captcha().last, matching: find.byType(EditableText)));
    debugPrint('CAPTCHA_CURRENT focused=${current.focusNode.hasFocus}');
    expect(current.focusNode.hasFocus, isTrue,
        reason:
            'Replacing the picture must not dismiss a focused current input');
    expect(tester.takeException(), isNull);
  });
}
