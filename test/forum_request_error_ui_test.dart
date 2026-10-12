import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/reply/reply_sheet.dart';
import 'package:south_plus_rewrite/features/search/search_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

void main() {
  testWidgets('search blocks resubmits and separates failures from no results',
      (tester) async {
    final repository = _FakeRepository();
    final searchButton = find.byWidgetPredicate((w) => w is FilledButton);
    await tester.pumpWidget(
      MaterialApp(home: SearchScreen(repository: repository)),
    );

    await tester.enterText(find.byType(TextField), 'sample');
    await tester.tap(searchButton);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(repository.searches, hasLength(1));
    expect(
      tester.widget<ButtonStyleButton>(searchButton).onPressed,
      isNull,
    );

    repository.searches.single.completeError(
      const ForumRequestException(ForumRequestKind.rateLimited, 'raw'),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('请求过于频繁'), findsOneWidget);
    expect(find.text('没有找到相关主题'), findsNothing);

    await tester.tap(searchButton);
    await tester.pump();
    repository.searches.last.complete(const []);
    await tester.pump();
    await tester.pump();
    expect(repository.searches, hasLength(2));
    expect(find.text('没有找到相关主题'), findsOneWidget);
  });

  testWidgets('reply failure shows short text and re-enables submit once',
      (tester) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReplyComposer(
              thread: _FakeRepository.thread,
              repository: repository,
              onSubmitted: (_) {},
            ),
          ),
        ),
      ),
    );
    final submit = find.byKey(const ValueKey('reply-submit-button'));

    await tester.enterText(find.byType(TextField).last, 'body');
    await tester.pump();
    await tester.tap(submit);
    await tester.pump();
    expect(repository.replies, 1);
    expect(tester.widget<ButtonStyleButton>(submit).onPressed, isNull);

    repository.reply.completeError(
      const ForumRequestException(ForumRequestKind.network, 'raw'),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('网络失败'), findsOneWidget);
    expect(repository.replies, 1);
    expect(tester.widget<ButtonStyleButton>(submit).onPressed, isNotNull);
  });
}

class _FakeRepository extends ForumRepository {
  static const thread = ForumThread(
    title: 'title',
    url: 'https://example.invalid/read.php?tid-1.html',
    replies: 0,
    section: 'section',
  );

  final searches = <Completer<List<ForumThread>>>[];
  final reply = Completer<ReplyResult>();
  int replies = 0;

  @override
  Future<List<ForumThread>> searchThreads(String keyword) {
    searches.add(Completer());
    return searches.last.future;
  }

  @override
  Future<ReplyResult> submitReply({
    required ForumThread thread,
    required String title,
    required String content,
  }) {
    replies++;
    return reply.future;
  }
}
