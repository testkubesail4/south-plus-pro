import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:south_plus_rewrite/services/forum_url_resolver.dart';
import 'package:south_plus_rewrite/services/parsers/forum_reply_notice_parser.dart';

const _empty = '<?xml version="1.0" encoding="utf-8"?>'
    '<ajax><![CDATA[您的回复列表为空]]></ajax>';

const _list = '''<table><tr><th class="h">回复提醒</th></tr>
<tr class="tr3"><td><a href="thread.php?fid=42">Fixture board</a></td>
<td class="tal"><a href="read.php?tid=123">Fixture title..</a></td>
<td><a>2026-01-01</a></td><td><img></td></tr></table>''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('notice list and delete use index verification and confirm removal',
      () async {
    await runZoned(() async {
      final client = _NoticeClient();
      final repository = ForumRepository(client: client);
      final notices = await repository.fetchReplyNotices();
      expect(notices.single.tid, 123);
      expect(notices.single.title, 'Fixture title..');
      expect(notices.single.board, 'Fixture board');
      expect(notices.single.date, '2026-01-01');
      expect(notices.single.threadUrl, endsWith('read.php?tid=123'));
      expect(client.gets, ['index.php']);
      expect(repository.noticeFlags.value.replyNotice, isTrue);
      expect(repository.noticeFlags.value.unreadPm, isTrue);
      await repository.deleteReplyNotice(notices.single);
      expect(repository.noticeFlags.value.replyNotice, isFalse);
      expect(repository.noticeFlags.value.unreadPm, isTrue);
      expect(client.forms, [
        {'action': 'newrp'},
        {'action': 'delnewrp', 'tid': '123'},
        {'action': 'newrp'},
      ]);
      for (var i = 1; i < client.postTimes.length; i++) {
        expect(client.postTimes[i].difference(client.postTimes[i - 1]),
            greaterThanOrEqualTo(const Duration(milliseconds: 1500)));
      }
      for (final path in client.posts) {
        final uri = Uri.parse(path);
        expect(uri.path, 'pw_ajax.php');
        expect(uri.queryParameters['verify'], 'a1b2c3d4');
        expect(int.tryParse(uri.queryParameters['nowtime']!), isNotNull);
      }
    },
        zoneSpecification: ZoneSpecification(
          // Model an early timer wake without weakening the minimum wire interval.
          createTimer: (self, parent, zone, duration, callback) =>
              parent.createTimer(
            zone,
            duration > const Duration(milliseconds: 100)
                ? duration - const Duration(milliseconds: 50)
                : duration,
            callback,
          ),
        ));
  });

  test('home publishes unread flags and reuses its verification token',
      () async {
    final client = _NoticeClient();
    final repository = ForumRepository(client: client);
    final home = await repository.fetchHome();
    expect(home.hasUnreadPm, isTrue);
    expect(home.hasReplyNotice, isFalse);
    expect(repository.noticeFlags.value.unreadPm, isTrue);
    await repository.fetchReplyNotices();
    expect(client.gets, ['simple/index.php', 'index.php']);
  });

  test('delete failure is not reported as success while notice remains',
      () async {
    final client = _NoticeClient()..removeOnDelete = false;
    final repository = ForumRepository(client: client);
    final notices = await repository.fetchReplyNotices();
    await expectLater(repository.deleteReplyNotice(notices.single),
        throwsA(isA<ForumRequestException>()));
  });

  test(
      'missing token blocks POST and session clearing invalidates cached token',
      () async {
    final client = _NoticeClient();
    final repository = ForumRepository(client: client);
    await repository.fetchReplyNotices();
    await repository.clearSession();
    expect(repository.noticeFlags.value.replyNotice, isFalse);
    expect(repository.noticeFlags.value.unreadPm, isFalse);
    client.index = '<html>Fixture missing token</html>';
    await expectLater(
        repository.fetchReplyNotices(), throwsA(isA<ForumRequestException>()));
    expect(client.posts, hasLength(1));
    expect(client.gets, ['index.php', 'index.php']);
  });

  test('login and malformed HTML are not interpreted as empty notices',
      () async {
    final client = _NoticeClient();
    final repository = ForumRepository(client: client);
    await repository.fetchReplyNotices();
    for (final response in [
      '请先登录',
      '验证码错误',
      'undefined',
      '',
      '<html>Unexpected response</html>'
    ]) {
      client.list = response;
      await expectLater(repository.fetchReplyNotices(),
          throwsA(isA<ForumRequestException>()));
      expect(repository.noticeFlags.value.replyNotice, isTrue);
    }
  });

  test('a list response from a cleared session cannot repopulate unread state',
      () async {
    final client = _NoticeClient()..pending = Completer<String>();
    final repository = ForumRepository(client: client);
    final pending = repository.fetchReplyNotices();
    await Future<void>.delayed(Duration.zero);
    await repository.clearSession();
    final assertion =
        expectLater(pending, throwsA(isA<ForumRequestException>()));
    client.pending!.complete(_list);
    await assertion;
    expect(repository.noticeFlags.value.replyNotice, isFalse);
  });

  test(
      'header unread markers are boolean and unrelated mail images do not count',
      () {
    final parser = ForumReplyNoticeParser(urls: ForumUrlResolver());
    final marked = html.parse('<a id="newrp">您的文章有人回复</a>');
    final mail = html.parse('<table><tr><td id="td_msg">'
        '<img src="images/colorImagination/shortmail.gif"></td></tr></table>');
    expect(parser.hasReplyNotice(marked), isTrue);
    expect(parser.hasUnreadPm(mail), isTrue);
    final plain =
        html.parse('<img src="shortmail.gif"><a href="message.php">消息</a>');
    expect(parser.hasReplyNotice(plain), isFalse);
    expect(parser.hasUnreadPm(plain), isFalse);
    expect(
        parser.hasUnreadPm(html.parse('<a id="td_msg" href="message.php">'
            '<img src="images/colorImagination/no-shortmail.gif"></a>')),
        isFalse);
  });
}

class _NoticeClient extends ForumClient {
  String index = "<head><script>var verifyhash = 'a1b2c3d4';</script></head>"
      '<body><a href="message.php">您有新的消息</a></body>';
  String list = _list;
  bool removeOnDelete = true;
  Completer<String>? pending;
  final gets = <String>[];
  final posts = <String>[];
  final postTimes = <DateTime>[];
  final forms = <Map<String, String>>[];

  @override
  Future<String> get(String path) async {
    gets.add(path);
    if (path == 'simple/index.php') {
      return '<a href="read.php?tid-123.html">Fixture title</a>'
          '<table><tr><th><h2>Fixture section</h2></th></tr><tr><th>'
          '<h3><a href="thread.php?fid-42.html">Fixture board</a></h3>'
          '</th><td>1 / 2</td></tr></table>';
    }
    return index;
  }

  @override
  Future<void> clearSession() async {}

  @override
  Future<String> post(String path, Map<String, String> fields) async {
    posts.add(path);
    postTimes.add(DateTime.now());
    forms.add(Map.of(fields));
    if (fields['action'] == 'delnewrp') {
      if (removeOnDelete) list = _empty;
      return '';
    }
    if (pending != null) return pending!.future;
    if (list == _list) return '<ajax><![CDATA[$list]]></ajax>';
    return list;
  }
}
