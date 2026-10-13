import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:south_plus_rewrite/features/thread/thread_rich_content.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';
import 'package:south_plus_rewrite/services/parsers/forum_pm_parser.dart';
import 'package:south_plus_rewrite/services/parsers/thread_content_parser.dart';

void main() {
  testWidgets(
      'server code chrome yields one native copy action and literal code',
      (tester) async {
    final segments = ThreadContentParser().extractInlineSegments(
      html.parseFragment(
          '''<div><table><tbody><tr><td><div class="c"></div><span class="f10 s8"><a>复制代码</a></span>
        <div class="blockquote2"><ol><li>Fixture line A</li><li>Fixture line B</li><li>Fixture line C</li></ol></div></td></tr></tbody></table></div>''').querySelector('div')!,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ThreadRichContent(segments: segments)),
    ));
    expect(find.byType(Table), findsNothing);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is RichText && widget.text.toPlainText().trim() == '复制代码'),
        findsNothing);
    expect(find.byTooltip('复制代码'), findsOneWidget);
    expect(find.text('代码'), findsOneWidget);
    expect(find.text('Fixture line A\nFixture line B\nFixture line C'),
        findsOneWidget);
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
    await tester.tap(find.byTooltip('复制代码'));
    await tester.pump();
    expect(copied, 'Fixture line A\nFixture line B\nFixture line C');
    expect(tester.takeException(), isNull);
  });

  for (final context in ['PM', 'unlocked sale']) {
    testWidgets('$context links retain separate lines and independent targets',
        (tester) async {
      const content =
          '''<span>Fixture links</span><br><a href="https://example.invalid/one">Fixture first link</a><br><a href="https://example.invalid/two">Fixture second link</a>''';
      final segments = context == 'PM'
          ? ForumPmParser(baseUri: Uri.https('south-plus.net', '/'))
              .parseDetail(
                html.parse('''<table class="set-table2">
                  <tr><td>发件人</td><td>Fixture sender</td></tr>
                  <tr><td>标题</td><td>Fixture title</td></tr>
                  <tr><td>时间</td><td>2020-01-01</td></tr>
                  <tr><td>内容</td><td>$content</td></tr>
                  <tr><td>选项</td><td></td></tr></table>'''),
                const ForumPmSummary(
                  box: ForumPmBox.inbox,
                  type: ForumPmType.personal,
                  id: '701',
                  peer: 'Fixture sender',
                  title: 'Fixture title',
                  time: '',
                  detailPath: 'message.php?action-read-mid-701.html',
                ),
              )
              .segments
          : ThreadContentParser()
              .extractInlineSegments(html.parseFragment('''<div>
              <h6 class="quote jumbotron"><span class="s3">此帖售价 0 SP币</span></h6>
              <blockquote class="blockquote jumbotron">$content</blockquote></div>''').querySelector('div')!);
      final opened = <String>[];
      var purchases = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ThreadRichContent(
            segments: segments,
            privateMedia: context == 'PM',
            onOpenLink: (url, _) async {
              opened.add(url);
            },
            onBuySaleBox: (_) {
              purchases++;
            },
          ),
        ),
      ));
      await tester.pump();
      final first = find.text('Fixture first link');
      final second = find.text('Fixture second link');
      expect(first, findsOneWidget);
      expect(second, findsOneWidget);
      expect(tester.getTopLeft(second).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(first).dy));
      expect(opened, isEmpty);
      expect(purchases, 0);
      await tester.tap(first);
      await tester.tap(second);
      expect(opened,
          ['https://example.invalid/one', 'https://example.invalid/two']);
      expect(purchases, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
