import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/account_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('我的 icons share one colour; unread is a dot, not a colour',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AccountScreen(repository: repo, onLoggedOut: () {}),
      ),
    ));
    await tester.pump();

    Finder tile(String title) => find
        .ancestor(of: find.text(title), matching: find.byType(InkWell))
        .first;
    Color? iconColor(String title) => tester
        .widget<Icon>(
            find.descendant(of: tile(title), matching: find.byType(Icon)).first)
        .color;
    bool dotted(String title) => tester
        .widget<Badge>(
            find.descendant(of: tile(title), matching: find.byType(Badge)))
        .isLabelVisible;

    final neutral = iconColor('资料');
    for (final title in ['主题', '短消息', '回复提醒', '论坛任务', '浏览历史', '设置']) {
      expect(iconColor(title), neutral, reason: title);
    }
    expect(dotted('短消息'), isFalse);
    expect(dotted('回复提醒'), isFalse);

    repo.flags.value =
        const ForumNoticeFlags(replyNotice: true, unreadPm: true);
    await tester.pump();
    expect(dotted('短消息'), isTrue);
    expect(dotted('回复提醒'), isTrue);
    expect(iconColor('短消息'), neutral);
    expect(iconColor('回复提醒'), neutral);
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
}

class _Repo extends ForumRepository {
  final flags = ValueNotifier(const ForumNoticeFlags());

  @override
  ValueNotifier<ForumNoticeFlags> get noticeFlags => flags;

  @override
  bool get isLoggedIn => true;

  @override
  String? get currentUsername => 'fixture_login';

  @override
  Future<void> loadAccountNickname() async {}
}
