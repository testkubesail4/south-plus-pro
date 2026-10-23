import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/account_screen.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('我的 row icons share one neutral colour', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AccountScreen(repository: _Repo(), onLoggedOut: () {}),
      ),
    ));
    await tester.pump();

    Color? iconColor(String title) => tester
        .widget<Icon>(find
            .descendant(
                of: find
                    .ancestor(
                        of: find.text(title), matching: find.byType(InkWell))
                    .first,
                matching: find.byType(Icon))
            .first)
        .color;

    final neutral = iconColor('我的主题');
    for (final title in ['我的回复', '浏览历史', '论坛任务', '屏蔽配置']) {
      expect(iconColor(title), neutral, reason: title);
    }
    expect(iconColor('退出登录'), isNot(neutral), reason: 'destructive');
  });

  test('icons come from the outlined family app-wide', () {
    final mixed = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      for (final match in RegExp(r'Icons\.\w+_(rounded|sharp)\b')
          .allMatches(file.readAsStringSync())) {
        mixed.add('${file.path}: ${match[0]}');
      }
    }
    expect(mixed, isEmpty);
  });

  test('screens take type and colour from the theme roles', () {
    // DESIGN §2/§3: screens use the theme roles, never their own literals.
    final literal = RegExp(r'fontSize: [0-9]|FontWeight\.w[89]00|Color\(0x');
    final offenders = <String>[];
    for (final file in Directory('lib/features').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (literal.hasMatch(file.readAsStringSync())) offenders.add(file.path);
    }
    expect(offenders, isEmpty);
  });
}

class _Repo extends ForumRepository {
  @override
  bool get isLoggedIn => true;

  @override
  String? get currentUsername => 'fixture_login';

  @override
  Future<void> loadAccountNickname() async {}
}
