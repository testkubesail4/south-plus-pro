import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/thread/thread_rich_content.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';

void main() {
  testWidgets('a link scales with large text exactly like the body text',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: Column(children: [
            ThreadRichContent(segments: const [
              ThreadContentSegment.text('正文'),
            ]),
            ThreadRichContent(segments: const [
              ThreadContentSegment.text('链接',
                  href: 'https://example.invalid/page'),
            ]),
          ]),
        ),
      ),
    ));

    final richBody = tester.widget<RichText>(find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == '正文'));
    expect(richBody.textScaler.scale(10), closeTo(20, 0.001));
    // getRect includes paint transforms, so a doubled scale shows up here.
    final link = tester.getRect(find.text('链接'));
    final body = tester.getRect(find.text('正文', findRichText: true));
    expect(link.height, closeTo(body.height, 2));
  });
}
