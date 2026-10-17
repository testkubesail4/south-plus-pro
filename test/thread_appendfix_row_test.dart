import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/common/forum_title_text.dart';
import 'package:south_plus_rewrite/features/common/thread_row.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

// Synthetic titles only.
const _long = '这是一个很长很长的合成标题，用来检查换行以后第二行是否仍从同一位置开始，不被标记挤开';
const _style = ForumTitleStyle(bold: true, colorValue: 0xFFFF00FF);

Widget _host(Widget row) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SizedBox(width: 260, child: row)),
    );

Future<void> _expectHangingMark(WidgetTester tester) async {
  await tester.pumpWidget(_host(const ForumThreadRow(
    title: _long,
    titleStyle: _style,
    meta: ['茶馆', '作者'],
    tag: '置顶',
  )));

  final title = tester.getRect(find.text(_long));
  // Wrapped (more than one line) and flush with the meta line.
  expect(title.height, greaterThan(30));
  expect(title.left, tester.getRect(find.text('置顶')).left);

  final markFinder = find.descendant(
    of: find.byType(ForumTitleText),
    matching: find.byType(DecoratedBox),
  );
  final mark = tester.getRect(markFinder);
  expect(mark.right, lessThanOrEqualTo(title.left));
  expect(mark.left, greaterThanOrEqualTo(4));
  // The label is not a node of its own (it merges into the row's), so read
  // the node that carries it rather than searching for one.
  expect(tester.getSemantics(markFinder).label, contains('高亮标题'));
}

void main() {
  testWidgets('a highlighted title is not inset; its mark hangs in the gutter',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _expectHangingMark(tester);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('置顶 leads the meta line instead of sitting beside the title',
      (tester) async {
    await tester.pumpWidget(_host(const ForumThreadRow(
      title: _long,
      meta: ['茶馆'],
      tag: '置顶',
    )));

    expect(find.byType(AppTag), findsNothing);
    final tag = tester.getRect(find.text('置顶'));
    final title = tester.getRect(find.text(_long));
    expect(tag.left, title.left);
    expect(tag.top, greaterThan(title.bottom - 1));
    // The title keeps the full row width.
    expect(title.width, greaterThan(200));
  });

  testWidgets('a plain title draws no mark', (tester) async {
    await tester.pumpWidget(_host(const ForumThreadRow(title: '普通标题')));
    expect(
      find.descendant(
        of: find.byType(ForumTitleText),
        matching: find.byType(DecoratedBox),
      ),
      findsNothing,
    );
  });
}
