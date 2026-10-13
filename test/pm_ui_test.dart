import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/messages/pm_box_screen.dart';
import 'package:south_plus_rewrite/features/messages/pm_compose_screen.dart';
import 'package:south_plus_rewrite/features/messages/pm_detail_screen.dart';
import 'package:south_plus_rewrite/features/profile/account_screen.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

const _personal = ForumPmSummary(
  box: ForumPmBox.inbox,
  type: ForumPmType.personal,
  id: '11',
  peer: 'peer-a',
  peerUid: '101',
  title: 'personal title',
  time: '2026-01-01',
  unread: true,
  detailPath: 'message.php?action-read-mid-11.html',
);
const _broadcast = ForumPmSummary(
  box: ForumPmBox.inbox,
  type: ForumPmType.broadcast,
  id: '12',
  peer: 'system',
  title: 'broadcast title',
  time: '2026-01-02',
  detailPath: 'message.php?action-readpub-mid-12.html',
);
const _tracked = ForumPmSummary(
  box: ForumPmBox.scout,
  type: ForumPmType.tracked,
  id: '13',
  peer: 'peer-b',
  title: 'tracked title',
  time: '2026-01-03',
  recipientRead: true,
  detailPath: 'message.php?action-readscout-mid-13.html',
);

void main() {
  testWidgets('boxes group the inbox, show tracked read state and page links',
      (tester) async {
    final repository = _FakePmRepository();
    await tester.pumpWidget(
      MaterialApp(home: PmBoxScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('个人消息'), findsOneWidget);
    expect(find.text('群发消息'), findsOneWidget);
    expect(find.text('有新消息'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('personal title')).dy,
      lessThan(tester.getTopLeft(find.text('broadcast title')).dy),
    );

    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    expect(repository.boxRequests.last,
        (ForumPmBox.inbox, 'message.php?action-receivebox-page-2.html'));

    await tester.tap(find.text('消息跟踪'));
    await tester.pumpAndSettle();
    expect(repository.boxRequests.last, (ForumPmBox.scout, null));
    expect(find.textContaining('对方已读'), findsOneWidget);
  });

  testWidgets('detail shows only server actions and confirms before delete',
      (tester) async {
    final repository = _FakePmRepository()
      ..detail = const ForumPmDetail(
        summary: _personal,
        sender: 'peer-a',
        title: 'personal title',
        time: '2026-01-01',
        content: 'line one\nline two',
        replyPath: 'message.php?action-write-remid-11.html',
        deletePath:
            'message.php?action-del-towhere-receivebox-delids-11-verify-fixture-token.html',
      );
    await tester.pumpWidget(MaterialApp(
      home: PmDetailScreen(repository: repository, message: _personal),
    ));
    await tester.pumpAndSettle();

    expect(find.text('line one\nline two'), findsOneWidget);
    expect(find.text('回复'), findsOneWidget);
    expect(find.text('转发'), findsNothing);
    expect(find.text('编辑'), findsNothing);
    expect(find.text('标为未读'), findsNothing);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repository.deletes, 0);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(repository.deletes, 1);
  });

  testWidgets('compose submits once, shows failures and never retries',
      (tester) async {
    final repository = _FakePmRepository();
    await tester.pumpWidget(
      MaterialApp(home: PmComposeScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    final submit = find.byKey(const ValueKey('pm-submit-button'));

    await tester.enterText(find.byType(TextField).at(0), 'a1b2');
    await tester.enterText(find.byType(TextField).at(1), 'hello');
    await tester.enterText(find.byType(TextField).at(2), 'body');
    expect(find.text('12'), findsOneWidget);
    await tester.tap(find.text('保存到发件箱'));
    await tester.tap(submit);
    await tester.pump();
    await tester.tap(submit);
    await tester.pump();
    expect(repository.submits, hasLength(1));
    expect(repository.submits.single, ('12', 'hello', 'body', true));

    repository.submitResult.completeError(
      const ForumRequestException(ForumRequestKind.rateLimited, 'raw'),
    );
    await tester.pumpAndSettle();
    expect(find.text('请求过于频繁'), findsOneWidget);
    expect(repository.submits, hasLength(1));
  });

  testWidgets('edit form requires a numeric recipient and neutral label',
      (tester) async {
    final repository = _FakePmRepository()..editCompose = true;
    await tester.pumpWidget(MaterialApp(
      home: PmComposeScreen(
          repository: repository,
          path: 'message.php?action-write-edmid-13.html'),
    ));
    await tester.pumpAndSettle();
    expect(repository.composePaths, ['message.php?action-write-edmid-13.html']);
    expect(find.text('提交修改'), findsOneWidget);

    await tester.tap(find.text('提交修改'));
    await tester.pump();
    expect(find.text('请输入数字收件人 UID'), findsOneWidget);
    expect(repository.submits, isEmpty);

    await tester.enterText(find.byType(TextField).at(0), '101');
    await tester.pumpAndSettle();
    // The formatting toolbar sits above the submit button.
    await tester.ensureVisible(find.text('提交修改'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交修改'));
    await tester.pump();
    expect(repository.submits.single,
        ('101', 'old title', '\n old body\n', false));
  });

  testWidgets(
      'return after a failed unread action refreshes inbox without another detail GET',
      (tester) async {
    const message = ForumPmSummary(
        box: ForumPmBox.inbox,
        type: ForumPmType.personal,
        id: '11',
        peer: 'peer-a',
        title: 'personal title',
        time: '',
        detailPath: 'message.php?action-read-mid-11.html');
    final repository = _FakePmRepository()
      ..inboxMessages = [message]
      ..unreadFailure = true
      ..detail = const ForumPmDetail(
          summary: message,
          sender: 'peer-a',
          title: 'personal title',
          time: '',
          content: 'body',
          markUnreadPath:
              'message.php?action-unread-mid-11-verify-fixture-token.html');
    await tester
        .pumpWidget(MaterialApp(home: PmBoxScreen(repository: repository)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('personal title'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '标为未读'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '标为未读'));
    await tester.pumpAndSettle();
    expect(repository.unreadCalls, 1);
    expect(find.text('网络失败'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(repository.boxRequests, hasLength(2));
    expect(repository.detailCalls, 1);
    expect(repository.unreadCalls, 1);
  });

  testWidgets(
      'successful compose returns to server refresh box without re-reading detail',
      (tester) async {
    final repository = _FakePmRepository()
      ..detail = const ForumPmDetail(
          summary: _tracked,
          sender: 'peer-b',
          title: 'tracked title',
          time: '',
          content: 'body',
          replyPath: 'message.php?action-write-touid-101.html');
    await tester
        .pumpWidget(MaterialApp(home: PmBoxScreen(repository: repository)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('消息跟踪'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('tracked title'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回复'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '101');
    await tester.enterText(find.byType(TextField).at(1), 'hello');
    await tester.enterText(find.byType(TextField).at(2), 'body');
    await tester.tap(find.byKey(const ValueKey('pm-submit-button')));
    await tester.pump();
    repository.submitResult.complete(const ForumPmActionResult(
        message: '操作完成', refreshPath: 'message.php?action=receivebox'));
    await tester.pumpAndSettle();
    expect(find.byType(PmDetailScreen), findsNothing);
    expect(find.byType(PmComposeScreen), findsNothing);
    expect(repository.boxRequests.last,
        (ForumPmBox.inbox, 'message.php?action=receivebox'));
    expect(repository.detailCalls, 1);
    expect(repository.submits, hasLength(1));
  });

  testWidgets('profile message chip opens the server compose entry',
      (tester) async {
    final repository = _FakePmRepository();
    await tester.pumpWidget(MaterialApp(
      home: UserProfileScreen(userUrl: 'u.php', repository: repository),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('发短消息'));
    await tester.pumpAndSettle();
    expect(repository.composePaths, [_FakePmRepository.profile.messageUrl]);
  });

  testWidgets('account screen opens messages when logged in', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repository = _FakePmRepository();
    await tester.pumpWidget(MaterialApp(
      home: AccountScreen(
        repository: repository,
        onLoggedOut: () {},
        packageInfoLoader: () async => PackageInfo(
          appName: 'app',
          packageName: 'app',
          version: '0',
          buildNumber: '0',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('短消息'), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('短消息'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('短消息'));
    await tester.pumpAndSettle();
    expect(find.byType(PmBoxScreen), findsOneWidget);
  });
}

class _FakePmRepository extends ForumRepository {
  static const profile = UserProfile(
    uid: '101',
    name: 'peer-a',
    url: 'u.php?action-show-uid-101.html',
    messageUrl: 'message.php?action-write-touid-101.html',
  );

  final boxRequests = <(ForumPmBox, String?)>[];
  final composePaths = <String?>[];
  final submits = <(String, String, String, bool)>[];
  final submitResult = Completer<ForumPmActionResult>();
  ForumPmDetail? detail;
  bool editCompose = false;
  bool unreadFailure = false;
  List<ForumPmSummary>? inboxMessages;
  int detailCalls = 0;
  int unreadCalls = 0;
  int deletes = 0;

  @override
  bool get isLoggedIn => true;

  @override
  Future<ForumPmPage> fetchPmBox(ForumPmBox box, {String? pagePath}) async {
    boxRequests.add((box, pagePath));
    return switch (box) {
      ForumPmBox.inbox => ForumPmPage(
          box: ForumPmBox.inbox,
          messages: inboxMessages ?? const [_broadcast, _personal],
          pageLinks: [
            ForumPmPageLink(
                label: '2', path: 'message.php?action-receivebox-page-2.html')
          ],
          hasUnread: true,
        ),
      _ => ForumPmPage(box: box, messages: const [_tracked]),
    };
  }

  @override
  Future<ForumPmDetail> fetchPmDetail(ForumPmSummary message) async {
    detailCalls++;
    return detail!;
  }

  @override
  Future<ForumPmActionResult> markPmUnread(ForumPmDetail detail) async {
    unreadCalls++;
    if (unreadFailure)
      throw const ForumRequestException(
          ForumRequestKind.network, 'Fixture failure');
    return const ForumPmActionResult(
        message: '操作完成', refreshPath: 'message.php?action=receivebox');
  }

  @override
  Future<ForumPmCompose> fetchPmCompose({String? path}) async {
    composePaths.add(path);
    return ForumPmCompose(
      actionPath: 'message.php',
      fields: const {},
      recipientUid: editCompose ? 'peer-a' : '',
      title: editCompose ? 'old title' : '',
      body: editCompose ? '\n old body\n' : '',
      isEdit: editCompose,
    );
  }

  @override
  Future<ForumPmActionResult> submitPm({
    required ForumPmCompose compose,
    required String recipientUid,
    required String title,
    required String body,
    bool saveToSendbox = false,
  }) {
    submits.add((recipientUid, title, body, saveToSendbox));
    return submitResult.future;
  }

  @override
  Future<ForumPmActionResult> deletePm(
    ForumPmSummary message, {
    ForumPmDetail? detail,
  }) async {
    deletes++;
    return const ForumPmActionResult(message: 'deleted');
  }

  @override
  Future<UserProfile?> cachedUserProfileOverview(String url) async => null;

  @override
  Future<UserProfile> fetchUserProfileOverview(String url) async => profile;

  @override
  Future<UserProfile> fetchUserProfileDetails(UserProfile overview) async =>
      overview;
}
