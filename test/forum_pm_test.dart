import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('inbox keeps personal and broadcast identities, unread and server links',
      () async {
    final client = _PmClient()..responses.add(_inbox);
    final page =
        await ForumRepository(client: client).fetchPmBox(ForumPmBox.inbox);
    expect(client.getPaths, ['message.php?action-receivebox.html']);
    expect(page.messages.map((m) => (m.type, m.id, m.title, m.unread)), [
      (ForumPmType.personal, '701', 'Fixture personal', true),
      (ForumPmType.broadcast, '701', 'Fixture broadcast', false),
    ]);
    expect(page.messages.first.peer, 'Fixture peer');
    expect(page.messages.first.peerUid, '901');
    expect(
        page.messages.first.detailPath, 'message.php?action-read-mid-701.html');
    expect(page.messages.last.detailPath,
        'message.php?action-readpub-mid-701.html');
    expect(page.hasUnread, true);
    expect(page.currentPage, 1);
    expect(page.nextPagePath, 'message.php?action-receivebox-page-2.html');
    expect(page.pageLinks.map((l) => (l.label, l.path)), [
      ('下一页', 'message.php?action-receivebox-page-2.html'),
    ]);
  });

  test('box continuation metadata follows only the observed consecutive page',
      () async {
    final client = _PmClient()
      ..responses.addAll([
        _inbox.replaceAll('receivebox-page-2', 'receivebox-page-3'),
        _inbox,
        _inbox.replaceAll('receivebox-page-2', 'receivebox-page-4'),
      ]);
    final repository = ForumRepository(client: client);
    final second = await repository.fetchPmBox(ForumPmBox.inbox,
        pagePath: 'message.php?action=receivebox&page=2');
    expect(second.currentPage, 2);
    expect(second.nextPagePath, 'message.php?action-receivebox-page-3.html');
    final third = await repository.fetchPmBox(ForumPmBox.inbox,
        pagePath: second.nextPagePath);
    expect(third.currentPage, 3);
    expect(third.nextPagePath, isNull, reason: 'previous links are not next');
    final first = await repository.fetchPmBox(ForumPmBox.inbox);
    expect(first.currentPage, 1);
    expect(first.nextPagePath, isNull,
        reason: 'do not invent missing page two or skip to page four');
    expect(client.getPaths, [
      'message.php?action=receivebox&page=2',
      'message.php?action-receivebox-page-3.html',
      'message.php?action-receivebox.html',
    ]);
    expect(client.posts, isEmpty);
  });

  test(
      'opening incoming detail is explicit and preserves only safe server actions',
      () async {
    final client = _PmClient()..responses.addAll([_inbox, _detail]);
    final repository = ForumRepository(client: client);
    final page = await repository.fetchPmBox(ForumPmBox.inbox);
    expect(client.getPaths, hasLength(1),
        reason: 'no incoming detail prefetch');
    final detail = await repository.fetchPmDetail(page.messages.first);
    expect(client.getPaths.last, 'message.php?action-read-mid-701.html');
    expect(detail.sender, 'Fixture peer');
    expect(detail.title, 'Fixture detail');
    expect(detail.time, '2020-01-01 10:00');
    expect(detail.content,
        'First line\nSecond line\n[图片：Fixture image]\nLast line');
    expect(detail.replyPath, 'message.php?action-write-remid-701.html');
    expect(detail.forwardPath, 'message.php?action-write-transmit-701.html');
    expect(detail.editPath, isNull);
    expect(detail.chatlogPath, 'message.php?action-chatlog-withuid-901.html');
    expect(detail.markUnreadPath,
        'message.php?action-unread-mid-701-verify-fixture-token.html');
    expect(detail.deletePath,
        'message.php?action-del-towhere-receivebox-delids-701-verify-fixture-token.html');
    expect(detail.hasUnread, false);
    final mismatched = ForumPmSummary(
        box: ForumPmBox.sendbox,
        type: ForumPmType.sent,
        id: '701',
        peer: '',
        title: '',
        time: '',
        detailPath: page.messages.first.detailPath);
    await expectLater(repository.fetchPmDetail(mismatched),
        throwsA(isA<ForumRequestException>()));
    expect(client.getPaths, hasLength(2));
  });

  test(
      'outgoing details follow their box identity and expose server compose-to-peer only',
      () async {
    final client = _PmClient()
      ..responses.add(_detail
          .replaceAll('mid-701', 'mid-802')
          .replaceAll('delids-701', 'delids-802')
          .replaceAll('towhere-receivebox', 'towhere-sendbox')
          .replaceAll('action-write-remid-802', 'action-write-touid-901'));
    final message = ForumPmSummary(
        box: ForumPmBox.sendbox,
        type: ForumPmType.sent,
        id: '802',
        peer: 'Fixture peer',
        peerUid: '901',
        title: '',
        time: '',
        detailPath: 'message.php?action-readsnd-mid-802.html');
    final detail = await ForumRepository(client: client).fetchPmDetail(message);
    expect(client.getPaths.single, 'message.php?action-readsnd-mid-802.html');
    expect(detail.replyPath, 'message.php?action-write-touid-901.html');
    expect(detail.markUnreadPath, isNull);
    expect(detail.deletePath,
        'message.php?action-del-towhere-sendbox-delids-802-verify-fixture-token.html');
    expect(detail.summary.id, '802');
    expect(detail.summary.box, ForumPmBox.sendbox);
  });

  test(
      'compose reads server prefill and immutable hidden fields, including edit identity',
      () async {
    final client = _PmClient()..responses.add(_compose);
    final form = await ForumRepository(client: client).fetchPmCompose(
        path:
            'https://www.south-plus.net/message.php?action-write-edmid-801.html');
    expect(client.getPaths, ['message.php?action-write-edmid-801.html']);
    expect(form.actionPath, 'message.php');
    expect(form.isEdit, true);
    expect(form.recipientUid, 'Fixture nickname');
    expect(form.title, 'Re: Fixture title');
    expect(form.body, '[quote]Fixture body[/quote]');
    expect(form.saveToSendbox, true);
    expect(form.fields['edmid'], '801');
    expect(form.fields['font'], 'Fixture font');
    expect(() => form.fields['verify'] = 'changed', throwsUnsupportedError);
  });

  test(
      'send validates positive UID and text, preserves edit hidden fields and server refresh',
      () async {
    final client = _PmClient()
      ..responses.addAll([_compose, _successInbox, _successInbox]);
    final repository = ForumRepository(client: client);
    final form = await repository.fetchPmCompose(
        path: 'message.php?action-write-edmid-801.html');
    for (final (uid, title, body) in [
      ('0', 'Title', 'Body'),
      ('-9', 'Title', 'Body'),
      ('nickname', 'Title', 'Body'),
      ('901', ' ', 'Body'),
      ('901', 'Title', ' '),
    ]) {
      await expectLater(
          repository.submitPm(
              compose: form, recipientUid: uid, title: title, body: body),
          throwsA(isA<ForumRepositoryException>()));
    }
    expect(client.posts, isEmpty);
    final result = await repository.submitPm(
        compose: form,
        recipientUid: '901',
        title: 'Fixture edited',
        body: 'Fixture new body');
    expect(result.message, '操作完成');
    expect(result.refreshPath, 'message.php?action=receivebox');
    expect(client.posts.single.$1, 'message.php');
    expect(client.posts.single.$2, {
      'action': 'write',
      'step': '2',
      'verify': 'fixture-token',
      'edmid': '801',
      'touidmsg': '901',
      'msg_title': 'Fixture edited',
      'atc_content': 'Fixture new body',
      'font': 'Fixture font',
      'size': '3',
      'color': 'blue',
    });
    await repository.submitPm(
        compose: form,
        recipientUid: '901',
        title: 'Fixture saved',
        body: 'Body',
        saveToSendbox: true);
    expect(client.posts.last.$2['ifsave'], 'Y');
    expect(client.posts, hasLength(2),
        reason: 'one POST per explicit submit, no edit-in-place request');
    for (final (response, kind) in [
      ('<body>Fixture unknown response</body>', ForumRequestKind.server),
      ('<body>认证码错误</body>', ForumRequestKind.server),
      ('<body>请先登录</body>', ForumRequestKind.loginRequired),
      ('<body>没有权限</body>', ForumRequestKind.forbidden),
      ('<body>刷新不要快于3秒</body>', ForumRequestKind.rateLimited),
    ]) {
      client.responses.add(response);
      final before = client.posts.length;
      await expectLater(
          repository.submitPm(
              compose: form, recipientUid: '901', title: 'Title', body: 'Body'),
          throwsA(isA<ForumRequestException>()
              .having((e) => e.kind, 'kind', kind)));
      expect(client.posts.length, before + 1);
    }
  });

  test(
      'mark unread uses only its server link once without re-opening incoming detail',
      () async {
    final client = _PmClient()..responses.addAll([_inbox, _detail, _inbox]);
    final repository = ForumRepository(client: client);
    final page = await repository.fetchPmBox(ForumPmBox.inbox);
    final detail = await repository.fetchPmDetail(page.messages.first);
    final result = await repository.markPmUnread(detail);
    expect(result.message, '标记未读完成');
    expect(client.getPaths, [
      'message.php?action-receivebox.html',
      'message.php?action-read-mid-701.html',
      'message.php?action-unread-mid-701-verify-fixture-token.html',
    ]);
    expect(client.posts, isEmpty);
  });

  test(
      'single delete refreshes list token and capability, never deletes another box copy',
      () async {
    final client = _PmClient()
      ..responses.addAll([
        _sendbox('fixture-old'),
        _sendbox('fixture-fresh'),
        _successSendbox
      ]);
    final repository = ForumRepository(client: client);
    final page = await repository.fetchPmBox(ForumPmBox.sendbox);
    final message = page.messages.single;
    final result = await repository.deletePm(message);
    expect(result.refreshPath, 'message.php?action=sendbox');
    expect(client.posts.single.$1, 'message.php');
    expect(client.posts.single.$2, {
      'verify': 'fixture-fresh',
      'delid[]': '802',
      'towhere': 'sendbox',
      'action': 'del'
    });
    client.responses.add(_sendbox('fixture-fresher', selectable: false));
    await expectLater(
        repository.deletePm(message), throwsA(isA<ForumRequestException>()));
    expect(client.posts, hasLength(1));
    final scoutClient = _PmClient()
      ..responses.addAll([
        _scout,
        _detail
            .replaceAll('701', '801')
            .replaceAll('towhere-receivebox', 'towhere-scout'),
        _successScout,
      ]);
    final scoutRepository = ForumRepository(client: scoutClient);
    final scout = await scoutRepository.fetchPmBox(ForumPmBox.scout);
    expect(scout.messages.single.recipientRead, true);
    expect(scout.messages.single.editPath, isNull);
    expect(scout.messages.single.canDelete, false);
    final supplied = await scoutRepository.fetchPmDetail(scout.messages.single);
    await scoutRepository.deletePm(scout.messages.single, detail: supplied);
    expect(scoutClient.getPaths.last, supplied.deletePath);
    expect(scoutClient.posts, isEmpty);
  });

  test('broadcast identity cannot delete a same-mid personal copy via delids',
      () async {
    const broadcast = ForumPmSummary(
        box: ForumPmBox.inbox,
        type: ForumPmType.broadcast,
        id: '701',
        peer: 'system',
        title: '',
        time: '',
        detailPath: 'message.php?action-readpub-mid-701.html');
    final client = _PmClient()..responses.add(_successInbox);
    final detail = ForumPmDetail(
        summary: broadcast,
        sender: 'system',
        title: '',
        time: '',
        content: '',
        deletePath:
            'message.php?action-del-towhere-receivebox-delids-701-verify-fixture-token.html');
    await expectLater(
        ForumRepository(client: client).deletePm(broadcast, detail: detail),
        throwsA(isA<ForumRepositoryException>()));
    expect(client.getPaths, isEmpty);
    expect(client.posts, isEmpty);
  });

  test(
      'empty boxes are explicit; malformed and blocked pages are never empty lists',
      () async {
    for (final box in ForumPmBox.values) {
      final client = _PmClient()..responses.add(_emptyBox(box));
      final page = await ForumRepository(client: client).fetchPmBox(box);
      expect(page.messages, isEmpty);
      expect(page.hasUnread, false);
    }
    for (final (response, kind) in [
      ('<body>Fixture unknown</body>', ForumRequestKind.server),
      (
        '<form method="post" action="message.php"><input name="towhere" value="receivebox"><input name="verify" value="fixture-token"></form>',
        ForumRequestKind.server
      ),
      ('<body>请先登录</body>', ForumRequestKind.loginRequired),
      ('<body>没有权限</body>', ForumRequestKind.forbidden),
      ('<body>刷新不要快于3秒</body>', ForumRequestKind.rateLimited),
    ]) {
      final client = _PmClient()..responses.add(response);
      await expectLater(
          ForumRepository(client: client).fetchPmBox(ForumPmBox.inbox),
          throwsA(isA<ForumRequestException>()
              .having((e) => e.kind, 'kind', kind)));
    }
  });

  test('private message text is not mistaken for a forum error page', () async {
    final client = _PmClient()
      ..responses.addAll([
        _inbox.replaceAll('Fixture personal', '请先登录'),
        _detail.replaceAll('First line', '没有权限 刷新不要快于3秒'),
        _compose.replaceAll(
            '[quote]Fixture body[/quote]', '[quote]请先登录[/quote]'),
        _chatlog.replaceAll('Fixture history<br>', '没有权限<br>'),
      ]);
    final repository = ForumRepository(client: client);
    final page = await repository.fetchPmBox(ForumPmBox.inbox);
    expect(page.messages.first.title, '请先登录');
    final detail = await repository.fetchPmDetail(page.messages.first);
    expect(detail.content, startsWith('没有权限 刷新不要快于3秒'));
    final form = await repository.fetchPmCompose(
        path: 'message.php?action-write-edmid-801.html');
    expect(form.body, '[quote]请先登录[/quote]');
    final log = await repository
        .fetchPmChatlog('message.php?action-chatlog-withuid-901.html');
    expect(log.records.single.content, startsWith('没有权限'));
  });

  test(
      'safe route boundaries reject off-site, side-effects and arbitrary GET before requests',
      () async {
    final client = _PmClient();
    final repository = ForumRepository(client: client);
    for (final path in [
      'https://example.invalid/message.php?action=receivebox',
      '//example.invalid/message.php?action=receivebox',
      'http://south-plus.net/message.php?action=receivebox',
      'https://fixture-user@south-plus.net/message.php?action=receivebox',
      'javascript:message.php?action=receivebox',
      'message.php?action=clear&verify=fixture-token',
      'message.php?action=down',
      'message.php?action=receivebox&action=del',
      'message.php?action=receivebox&verify=fixture-token',
      'message.php?action-unread-mid-701-verify-fixture-token.html',
      'message.php?action-del-towhere-scout-delids-801-verify-fixture-token.html',
      'message.php?action=receivebox#action=del',
      'profile.php?action=receivebox',
    ]) {
      await expectLater(repository.fetchPmBox(ForumPmBox.inbox, pagePath: path),
          throwsA(isA<ForumRequestException>()));
      await expectLater(repository.fetchPmCompose(path: path),
          throwsA(isA<ForumRequestException>()));
    }
    expect(client.getPaths, isEmpty);
    expect(client.posts, isEmpty);
  });

  test(
      'a loaded PM form cannot adopt newly installed credentials before username publication',
      () async {
    final client = _PmClient()
      ..responses.addAll([
        _compose,
        _compose.replaceAll('fixture-token', 'fresh-credential-token'),
        _successInbox
      ]);
    final repository = ForumRepository(client: client);
    final old = await repository.fetchPmCompose(
        path: 'message.php?action-write-edmid-801.html');
    client.credentialOverride = client.credentialGeneration + 1;
    await expectLater(
        repository.submitPm(
            compose: old,
            recipientUid: '901',
            title: 'Title',
            body: 'Private body'),
        throwsA(isA<ForumRequestException>().having(
            (error) => error.kind, 'kind', ForumRequestKind.loginRequired)));
    expect(client.posts, isEmpty);
    final fresh = await repository.fetchPmCompose(
        path: 'message.php?action-write-edmid-801.html');
    await repository.submitPm(
        compose: fresh,
        recipientUid: '901',
        title: 'Title',
        body: 'Fresh body');
    expect(client.posts.single.$2['verify'], 'fresh-credential-token');
  });

  test('a compose form belongs to its loading session, never the next account',
      () async {
    final client = _PmClient()
      ..responses.addAll([
        _compose,
        _compose.replaceAll('fixture-token', 'new-session-token'),
        _successInbox,
      ]);
    final repository = ForumRepository(client: client);
    final old = await repository.fetchPmCompose(
        path: 'message.php?action-write-edmid-801.html');
    await repository.clearSession();
    client.loggedIn = true;
    await expectLater(
        repository.submitPm(
            compose: old,
            recipientUid: '901',
            title: 'Old title',
            body: 'Old private body'),
        throwsA(isA<ForumRequestException>().having(
            (error) => error.kind, 'kind', ForumRequestKind.loginRequired)));
    expect(client.posts, isEmpty);
    final fresh = await repository.fetchPmCompose(
        path: 'message.php?action-write-edmid-801.html');
    final fabricated = ForumPmCompose(
        actionPath: fresh.actionPath,
        fields: fresh.fields,
        isEdit: fresh.isEdit);
    await expectLater(
        repository.submitPm(
            compose: fabricated,
            recipientUid: '901',
            title: 'Title',
            body: 'Body'),
        throwsA(isA<ForumRequestException>().having(
            (error) => error.kind, 'kind', ForumRequestKind.invalidInput)));
    await repository.submitPm(
        compose: fresh,
        recipientUid: '901',
        title: 'New title',
        body: 'New body');
    expect(client.posts, hasLength(1));
    expect(client.posts.single.$2['verify'], 'new-session-token');
    expect(client.posts.single.$2['atc_content'], 'New body');
  });

  test('loaded PM summaries and detail action links retire with their session',
      () async {
    final client = _PmClient()..responses.addAll([_inbox, _detail]);
    final repository = ForumRepository(client: client);
    final page = await repository.fetchPmBox(ForumPmBox.inbox);
    final detail = await repository.fetchPmDetail(page.messages.first);
    final before = client.getPaths.length;
    await repository.clearSession();
    client.loggedIn = true;
    final actions = <Future<Object> Function()>[
      () => repository.fetchPmDetail(page.messages.first),
      () => repository.markPmUnread(detail),
      () => repository.deletePm(page.messages.first),
      () => repository.deletePm(detail.summary, detail: detail),
    ];
    for (final action in actions) {
      await expectLater(
          action(),
          throwsA(isA<ForumRequestException>().having(
              (error) => error.kind, 'kind', ForumRequestKind.loginRequired)));
    }
    expect(client.getPaths, hasLength(before));
    expect(client.posts, isEmpty);
  });

  test('a PM read begun during login cannot settle under a new identity',
      () async {
    final client = _PmClient()..responses.add(_inbox);
    final repository = ForumRepository(client: client);
    await repository.submitLogin(
        username: 'synthetic-A',
        password: 'synthetic-password',
        captcha: 'synthetic-captcha',
        fields: {});
    expect(repository.currentUsername, 'synthetic-A');
    client.loginGate = Completer<void>();
    client.responseGate = Completer<void>();
    final login = repository.submitLogin(
        username: 'synthetic-B',
        password: 'synthetic-password',
        captcha: 'synthetic-captcha',
        fields: {});
    await client.loginReached.future;
    final pending = repository.fetchPmBox(ForumPmBox.inbox);
    await client.reachedGate.future;
    client.loginGate!.complete();
    await login;
    expect(repository.currentUsername, 'synthetic-B');
    client.responseGate!.complete();
    await expectLater(
        pending,
        throwsA(isA<ForumRequestException>().having(
            (error) => error.kind, 'kind', ForumRequestKind.loginRequired)));
  });

  test('in-flight PM reads cannot publish into a replacement session',
      () async {
    for (final mode in ['box', 'detail', 'compose', 'chatlog']) {
      final response = switch (mode) {
        'box' => _inbox,
        'detail' => _detail,
        'compose' => _compose,
        _ => _chatlog,
      };
      final client = _PmClient()
        ..responses.add(response)
        ..responseGate = Completer<void>();
      final repository = ForumRepository(client: client);
      final pending = switch (mode) {
        'box' => repository.fetchPmBox(ForumPmBox.inbox),
        'detail' => repository.fetchPmDetail(const ForumPmSummary(
            box: ForumPmBox.inbox,
            type: ForumPmType.personal,
            id: '701',
            peer: '',
            title: '',
            time: '',
            detailPath: 'message.php?action-read-mid-701.html')),
        'compose' => repository.fetchPmCompose(
            path: 'message.php?action-write-edmid-801.html'),
        _ => repository
            .fetchPmChatlog('message.php?action-chatlog-withuid-901.html'),
      };
      await client.reachedGate.future;
      await repository.clearSession();
      client.loggedIn = true;
      client.responseGate!.complete();
      await expectLater(
          pending,
          throwsA(isA<ForumRequestException>().having(
              (error) => error.kind, 'kind', ForumRequestKind.loginRequired)),
          reason: mode);
    }
  });

  test('chatlog reads records and only same-peer server pages, never dellog',
      () async {
    final client = _PmClient()..responses.add(_chatlog);
    final repository = ForumRepository(client: client);
    final log = await repository
        .fetchPmChatlog('message.php?action-chatlog-withuid-901.html');
    expect(log.records, hasLength(1));
    expect(log.records.single.sender, isEmpty,
        reason: 'observed chatlog records have no sender field');
    expect(log.records.single.title, 'Fixture history title');
    expect(log.records.single.time, '2020-01-01 10:00');
    expect(log.records.single.content, 'Fixture history\nsecond line');
    expect(log.composePath, 'message.php?action-write-touid-901.html');
    expect(log.currentPage, 1);
    expect(
        log.nextPagePath, 'message.php?action-chatlog-withuid-901-page-2.html');
    expect(log.pageLinks.map((l) => l.path),
        ['message.php?action-chatlog-withuid-901-page-2.html']);
    expect(client.posts, isEmpty);
    await expectLater(
        repository.fetchPmChatlog('message.php?action=dellog&withuid=901'),
        throwsA(isA<ForumRequestException>()));
    expect(client.getPaths, ['message.php?action-chatlog-withuid-901.html']);
  });

  test('chatlog continuation keeps the peer and never guesses a missing next',
      () async {
    final client = _PmClient()
      ..responses.addAll([
        _chatlog.replaceAll('withuid-901-page-2', 'withuid-901-page-3'),
        _chatlog.replaceAll('withuid-902-page-2', 'withuid-902-page-4'),
      ]);
    final repository = ForumRepository(client: client);
    final second = await repository
        .fetchPmChatlog('message.php?action=chatlog&withuid=901&page=2');
    expect(second.currentPage, 2);
    expect(second.nextPagePath,
        'message.php?action-chatlog-withuid-901-page-3.html');
    final third = await repository.fetchPmChatlog(second.nextPagePath!);
    expect(third.currentPage, 3);
    expect(third.nextPagePath, isNull);
    expect(third.pageLinks.map((link) => link.path),
        ['message.php?action-chatlog-withuid-901-page-2.html']);
    expect(client.getPaths, [
      'message.php?action=chatlog&withuid=901&page=2',
      'message.php?action-chatlog-withuid-901-page-3.html',
    ]);
    expect(client.posts, isEmpty);
  });
}

class _PmClient extends ForumClient {
  final responses = <String>[];
  final getPaths = <String>[];
  final posts = <(String, Map<String, String>)>[];
  bool loggedIn = true;
  int? credentialOverride;
  @override
  int get credentialGeneration =>
      credentialOverride ?? super.credentialGeneration;
  @override
  bool isCredentialCurrent(int generation) => credentialOverride == null
      ? super.isCredentialCurrent(generation)
      : generation == credentialOverride;
  Completer<void>? responseGate;
  final reachedGate = Completer<void>();
  Completer<void>? loginGate;
  final loginReached = Completer<void>();

  @override
  bool get isLoggedIn => loggedIn;

  @override
  Future<String> getForm(String path,
      {void Function()? requireCurrentSession,
      bool followRedirects = true}) async {
    requireCurrentSession?.call();
    getPaths.add(path);
    final response = responses.removeAt(0);
    if (responseGate != null) {
      reachedGate.complete();
      await responseGate!.future;
    }
    requireCurrentSession?.call();
    return response;
  }

  @override
  Future<String> postForm(String path, List<MapEntry<String, String>> fields,
      {bool multipart = false,
      List<ForumFormFile> files = const [],
      void Function()? requireCurrentSession}) async {
    requireCurrentSession?.call();
    posts.add((path, Map.fromEntries(fields)));
    return responses.removeAt(0);
  }

  @override
  Future<String> get(String path) async =>
      throw StateError('PM must use guarded requests');

  @override
  Future<String> getOnce(String path) => get(path);

  @override
  Future<
      ({
        String response,
        int credentialGeneration,
        bool installedCredentials
      })> postLogin(Map<String, String> form) async {
    final response = await post('login.php', form);
    return (
      response: response,
      credentialGeneration: credentialGeneration,
      installedCredentials: isLoggedIn
    );
  }

  @override
  Future<String> post(String path, Map<String, String> form) async {
    if (path != 'login.php') return get(path);
    if (loginGate != null) {
      loginReached.complete();
      await loginGate!.future;
    }
    return '<div id="user-login"><a href="u.php">${form['pwuser']}</a></div>';
  }

  @override
  Future<void> clearSession() async {
    loggedIn = false;
  }
}

String _emptyBox(ForumPmBox box) => '''
<html><body><img src="images/colorImagination/no-shortmail.gif"><form method="post" action="message.php">
<input name="towhere" value="${box.wireName}" type="hidden"><input name="verify" value="fixture-token" type="hidden">
<table><tr><td>ID</td><td>发件人</td><td>标题</td><td>时间</td><td>选择</td></tr></table>
</form></body></html>
''';

const _chatlog = '''
<html><body><form method="post" action="message.php">
<input type="hidden" name="action" value="dellog"><input name="verify" value="fixture-token" type="hidden"><input name="withuid" value="901" type="hidden">
<table class="set-table2"><tr><td><div>
<span class="fr gray">2020-01-01 10:00<input type="checkbox" name="selid[]" value="1001"></span>
<span class="s2"><b>Fixture history title</b></span><br>Fixture history<br><span class="s2"><b>second line</b></span>
</div></td></tr></table>
<input type="submit" value="删 除"></form>
<a href="message.php?action-write-touid-901.html">回复</a>
<div class="pages"><a href="message.php?action-chatlog-withuid-901-page-2.html">下一页</a>
<a href="message.php?action-chatlog-withuid-902-page-2.html">其他通信</a>
<a href="message.php?action=dellog&amp;withuid=901">删除</a></div>
</body></html>
''';

String _sendbox(String token, {bool selectable = true}) => '''
<html><body><form action="message.php" method="post">
<input name="verify" value="$token" type="hidden"><input name="towhere" value="sendbox" type="hidden">
<table><tr><td>ID</td><td>收件人</td><td>标题</td><td>时间</td><td>选择</td></tr>
<tr><td>1</td><td>Fixture peer</td><td><a href="message.php?action-readsnd-mid-802.html">Fixture saved</a></td>
<td>2020-01-01 10:00</td><td>${selectable ? '<input type="checkbox" name="delid[]" value="802">' : ''}</td></tr></table>
</form></body></html>
''';

const _scout = '''
<html><body><form action="message.php" method="post">
<input name="verify" value="fixture-token" type="hidden"><input name="towhere" value="scout" type="hidden">
<table><tr><td>ID</td><td>收件人</td><td>标题</td><td>时间</td><td>已读</td><td>选择</td><td>编辑</td></tr>
<tr><td>1</td><td>Fixture peer</td><td><a href="message.php?action-readscout-mid-801.html">Fixture sent</a></td>
<td>2020-01-01 10:00</td><td>是</td><td></td><td></td></tr></table>
</form></body></html>
''';
const _successSendbox =
    '<html><head><meta http-equiv="refresh" content="1;url=message.php?action=sendbox"></head><body>操作完成</body></html>';
const _successScout =
    '<html><head><meta http-equiv="refresh" content="1;url=message.php?action=scout"></head><body>操作完成</body></html>';

const _successInbox =
    '<html><head><meta http-equiv="refresh" content="1;url=message.php?action=receivebox"></head><body>操作完成</body></html>';

const _compose = '''
<html><body><form method="POST" action="message.php">
<input type="hidden" name="action" value="write"><input type="hidden" name="step" value="2">
<input type="hidden" name="verify" value="fixture-token"><input type="hidden" name="edmid" value="801">
<input name="touidmsg" value="Fixture nickname"><input name="msg_title" value="Re: Fixture title">
<input name="font" value="Fixture font"><input name="size" value="3"><input name="color" value="blue">
<textarea name="atc_content">[quote]Fixture body[/quote]</textarea>
<input type="checkbox" name="ifsave" value="Y" checked>
</form></body></html>
''';

const _detail = '''
<html><body><img src="images/colorImagination/no-shortmail.gif">
<table class="set-table2">
<tr><td>发件人:</td><td><a href="u.php?action-show-uid-901.html">Fixture peer</a></td></tr>
<tr><td>标题:</td><td>Fixture detail</td></tr>
<tr><td>时间:</td><td>2020-01-01 10:00</td></tr>
<tr><td>内容:</td><td>First line<br>Second line<div><img src="https://example.invalid/private.png" alt="Fixture image"></div><p>Last line</p><script>do not show</script></td></tr>
<tr><td>选项:</td><td>
<a href="message.php?action-chatlog-withuid-901.html">通信记录</a>
<a href="message.php?action-write-remid-701.html">回复</a>
<a href="message.php?action-write-transmit-701.html">转发</a>
<a href="message.php?action-unread-mid-701-verify-fixture-token.html">标记未读</a>
<a href="message.php?action-del-towhere-receivebox-delids-701-verify-fixture-token.html">删除</a>
<a href="message.php?action-del-towhere-scout-delids-701-verify-fixture-token.html">错误箱删除</a>
<a href="https://example.invalid/message.php?action-write-edmid-701.html">外站编辑</a>
<a href="javascript:location='message.php?action-clear-verify-fixture.html'">脚本</a>
</td></tr></table></body></html>
''';

const _inbox = '''
<html><body><img src="images/colorImagination/shortmail.gif">
<form method="post" action="message.php">
<input type="hidden" name="verify" value="fixture-token">
<input type="hidden" name="towhere" value="receivebox">
<table><tr><td>ID</td><td>发件人</td><td>标题</td><td>时间</td><td>选择</td></tr>
<tr><td>1</td><td><a href="u.php?action-show-uid-901.html">Fixture peer</a></td>
<td><a class="b" href="message.php?action-read-mid-701.html">Fixture personal</a></td>
<td>2020-01-01 10:00</td><td><input type="checkbox" name="delid[]" value="701"></td></tr></table>
<table><tr><td>ID</td><td>发件人</td><td>标题</td><td>时间</td><td>选择</td></tr>
<tr><td>1</td><td>Fixture system</td>
<td><a href="message.php?action-readpub-mid-701.html">Fixture broadcast</a></td>
<td>2020-01-01 11:00</td><td><input type="checkbox" name="pdelid[]" value="701"></td></tr></table>
</form><div class="pages">
<a href="message.php?action-receivebox-page-2.html">下一页</a>
<a href="message.php?action-del-towhere-receivebox-delids-701-verify-fixture.html">危险</a>
<a href="https://example.invalid/message.php?action-receivebox-page-3.html">外站</a>
<a href="message.php?action-sendbox-page-2.html">错误箱</a>
</div></body></html>
''';
