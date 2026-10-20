import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/reply/thread_edit_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

// Synthetic fixtures only: fictional host, tid, pids, authors and texts.
const _url = 'https://south-plus.net/read.php?tid-7.html';
const _thread = ForumThread(
    title: 'edit', url: _url, replies: 2, section: '', author: 'op');
const _opLink = ThreadActionLink(
    label: '编辑',
    url: 'post.php?action-modify-fid-8-tid-7-pid-tpc-article-0.html');
const _replyLink = ThreadActionLink(
    label: '编辑',
    url: 'post.php?action-modify-fid-8-tid-7-pid-501-article-1.html');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_Repo> pumpThread(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _Repo();
    await tester.pumpWidget(MaterialApp(
      home: ThreadDetailScreen(repository: repository, thread: _thread),
    ));
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> openMenu(WidgetTester tester, String key) async {
    final more = find.byKey(ValueKey(key));
    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();
  }

  Future<void> openEdit(WidgetTester tester, String key) async {
    await openMenu(tester, key);
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
  }

  testWidgets('编辑 shows only on floors that carry the forum edit link',
      (tester) async {
    await pumpThread(tester);
    await openMenu(tester, 'floor-actions-other-B2F');
    expect(find.text('编辑'), findsNothing);
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();
    await openMenu(tester, 'floor-actions-me-B1F');
    expect(find.text('编辑'), findsOneWidget);
  });

  testWidgets('a reply opens prefilled, saves, and its page reloads in place',
      (tester) async {
    final repository = await pumpThread(tester);
    await openEdit(tester, 'floor-actions-me-B1F');
    expect(find.text('编辑回复'), findsOneWidget);
    expect(repository.draftLinks.single, same(_replyLink));
    expect(find.widgetWithText(TextField, '[b]原文[/b]'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '[b]原文[/b]'), '新正文');
    await tester.tap(find.byKey(const ValueKey('edit-save-button')));
    await tester.pumpAndSettle();

    expect(repository.submits.single, ('Re:edit', '新正文'));
    expect(find.text('编辑回复'), findsNothing);
    expect(find.text('已保存修改'), findsOneWidget);
    expect(repository.pages, [1, 1], reason: 'reloaded, nothing appended');
  });

  testWidgets(
      'an unconfirmed save keeps the text, says so, and resends only on request',
      (tester) async {
    final repository = await pumpThread(tester);
    repository.results.add(const ReplyResult(success: false, message: '提示信息'));
    await openEdit(tester, 'floor-actions-op-楼主');
    expect(find.text('编辑帖子'), findsOneWidget);
    expect(repository.draftLinks.single, same(_opLink));

    await tester.enterText(find.widgetWithText(TextField, '[b]原文[/b]'), '改过');
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();
    expect(find.text('编辑帖子'), findsOneWidget, reason: 'stays open');
    expect(find.widgetWithText(TextField, '改过'), findsOneWidget);
    expect(find.textContaining('保存未确认：提示信息'), findsOneWidget);
    expect(repository.draftLinks, hasLength(1), reason: 'no automatic retry');

    // 保存修改 again reads a fresh form and sends what is on screen.
    repository.results.add(const ReplyResult(success: false, message: '提示信息'));
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();
    expect(repository.draftLinks, hasLength(2));
    expect(repository.submits.map((s) => s.$2), ['改过', '改过']);

    await tester.tap(find.text('查看帖子'));
    await tester.pumpAndSettle();
    expect(find.text('编辑帖子'), findsNothing);
    expect(find.text('已保存修改'), findsNothing);
    expect(repository.pages, [1, 1]);
  });

  testWidgets('the form fades in over its spinner', (tester) async {
    final repository = _Repo()..hold = Completer();
    await tester.pumpWidget(MaterialApp(
      home: ThreadEditScreen(
          repository: repository, link: _replyLink, openingPost: false),
    ));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repository.hold!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Mid-fade: the spinner leaves as the form comes in.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final form = tester.widget<FadeTransition>(find
        .ancestor(
            of: find.text('[b]原文[/b]'), matching: find.byType(FadeTransition))
        .first);
    expect(form.opacity.value, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a draft that cannot load offers a retry and sends nothing',
      (tester) async {
    final repository = await pumpThread(tester);
    repository.draftFails = true;
    await openEdit(tester, 'floor-actions-me-B1F');
    expect(find.text('无法打开编辑'), findsOneWidget);
    expect(find.text('编辑链接无效，请刷新帖子'), findsOneWidget);
    expect(find.text('保存修改'), findsNothing);

    repository.draftFails = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('保存修改'), findsOneWidget);
    expect(repository.submits, isEmpty);
  });

  testWidgets(
      'a narrow phone with large text and the keyboard up still reaches 查看帖子',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    final repository = _Repo()
      ..results.add(const ReplyResult(success: false, message: '提示信息'));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: ThreadEditScreen(
          repository: repository, link: _replyLink, openingPost: false),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, '[b]原文[/b]'), '很长的改动\n' * 20);
    await tester.tap(find.byKey(const ValueKey('edit-save-button')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('查看帖子').hitTestable(), findsOneWidget);
    expect(find.textContaining('保存未确认'), findsOneWidget);
    final content = find.textContaining('很长的改动');
    await tester.dragUntilVisible(
        content, find.byType(ListView), const Offset(0, -100));
    expect(tester.widget<EditableText>(content).controller.text, '很长的改动\n' * 20,
        reason: 'the text is kept');
  });

  testWidgets('leaving with changes asks first', (tester) async {
    final repository = await pumpThread(tester);
    await openEdit(tester, 'floor-actions-me-B1F');
    await tester.enterText(find.widgetWithText(TextField, '[b]原文[/b]'), 'x');
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('放弃修改？'), findsOneWidget);
    await tester.tap(find.text('放弃'));
    await tester.pumpAndSettle();
    expect(find.text('编辑回复'), findsNothing);
    expect(repository.submits, isEmpty);
    expect(repository.pages, [1], reason: 'nothing sent, nothing reloaded');
  });
}

class _Repo extends ForumRepository {
  final pages = <int>[];
  final draftLinks = <ThreadActionLink>[];
  final submits = <(String, String)>[];
  final results = <ReplyResult>[];
  bool draftFails = false;
  Completer<void>? hold;

  @override
  Future<ThreadDetail> fetchThreadDetail(ForumThread thread,
      {int page = 1}) async {
    pages.add(page);
    return ThreadDetail(
      thread: _thread,
      body: 'opening',
      bodySegments: const [ThreadContentSegment.text('opening')],
      bodyAnchors: const ['tpc'],
      bodyEditLink: _opLink,
      replies: const [
        ThreadReply(
          author: 'me',
          content: 'mine',
          floor: 'B1F',
          editLink: _replyLink,
          segments: [ThreadContentSegment.text('mine')],
          anchors: ['501'],
        ),
        ThreadReply(
          author: 'other',
          content: 'theirs',
          floor: 'B2F',
          segments: [ThreadContentSegment.text('theirs')],
          anchors: ['502'],
        ),
      ],
    );
  }

  @override
  Future<ThreadEditDraft> fetchEditDraft(ThreadActionLink link) async {
    draftLinks.add(link);
    await hold?.future;
    if (draftFails) {
      throw const ForumRequestException(
          ForumRequestKind.invalidInput, '编辑链接无效，请刷新帖子');
    }
    return ThreadEditDraft(
      title: 'Re:edit',
      content: '[b]原文[/b]',
      fields: const {},
      controls: const [],
      actionPath: 'post.php?',
    );
  }

  @override
  Future<ReplyResult> submitEdit({
    required ThreadEditDraft draft,
    required String title,
    required String content,
  }) async {
    submits.add((title, content));
    return results.isEmpty
        ? const ReplyResult(success: true, message: '编辑已保存')
        : results.removeAt(0);
  }
}
