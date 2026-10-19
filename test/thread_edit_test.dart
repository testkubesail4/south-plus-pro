import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/browsing_history_store.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:south_plus_rewrite/services/parsers/thread_detail_parser.dart';

const _link = ThreadActionLink(
  label: '编辑',
  url: 'post.php?action-modify-fid-6-tid-700-pid-900-article-12.html',
);
const _ack = '<html><head><title>南+ South Plus</title>'
    '<meta http-equiv="refresh" '
    'content="1;url=read.php?tid=700&amp;page=3&amp;toread=1#900">'
    '</head><body>提示信息 [ 发帖完毕点击进入主题列表 ] '
    '如果您的浏览器没有自动跳转,请点击这里 '
    '<a href="read.php?tid=700&amp;page=3&amp;toread=1#900">点击这里</a>'
    '</body></html>';
const _form = '''<form name="FORM" method="post" action="post.php?"
    enctype="multipart/form-data">
  <input name="atc_title" value="Original &amp; title">
  <textarea name="atc_content"> [hide=3]Original [b]BBCode[/b][/hide]
[attachment=17] </textarea>
  <input type="hidden" name="step" value="2">
  <input type="hidden" name="action" value="modify">
  <input type="hidden" name="fid" value="6">
  <input type="hidden" name="tid" value="700">
  <input type="hidden" name="pid" value="900">
  <input type="hidden" name="article" value="12">
  <input type="hidden" name="special" value="0">
  <input type="hidden" name="verify" value="fixture-token">
  <input type="checkbox" name="atc_autourl" value="1" checked>
  <input type="checkbox" name="atc_usesign" value="1" checked>
  <input type="checkbox" name="atc_convert" value="1" checked>
  <input type="checkbox" name="atc_anonymous" value="1">
  <input type="checkbox" name="atc_hide" value="1" checked>
  <input type="checkbox" name="atc_requireenhide" value="1" checked>
  <input type="checkbox" name="atc_requiresell" value="1" checked>
  <input name="atc_rvrc" value="3"><input name="atc_money" value="7">
  <select name="atc_enhidetype"><option>money</option>
    <option selected value="rvrc">声望</option></select>
  <select name="atc_credittype"><option selected value="money">SP</option></select>
  <input type="hidden" name="keep[]" value="17">
  <input type="hidden" name="keep[]" value="18">
  <input type="file" name="attachment[]">
  <input name="disabled" disabled value="must-not-submit">
  <input type="submit" name="Submit" value="native submit">
</form>''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('edit links come only from each floor header, including the OP',
      () async {
    String post(String id, String header, String body) =>
        '<a name="$id"></a><div><table class="js-post"><tr>'
        '<th class="r_two"><a href="u.php?action-show-uid-8.html">Author</a></th>'
        '<th class="r_one" id="td_$id"><div class="tiptop">$header</div>'
        '<div class="tpc_content"><div id="read_$id">$body</div></div>'
        '</th></tr></table></div>';
    final op = _link.url
        .replaceAll('pid-900', 'pid-tpc')
        .replaceAll('article-12', 'article-0');
    final markup = '<form>${post('tpc', '<a href="$op">编辑主文</a>', 'OP')}'
        '${post('900', '<a href="${_link.url}">编辑</a>', 'Reply')}'
        '${post('901', '', '<a href="${_link.url}">not a header action</a>')}'
        '${post('902', '<a href="https://evil.invalid/${_link.url}">编辑</a>', 'Other')}'
        '</form>';
    final cards = ThreadDetailParser().desktopThreadCards(html.parse(markup));
    expect(cards[0].editLink!.label, '编辑主文');
    expect(cards[1].editLink!.url, endsWith(_link.url));
    expect(cards[2].editLink, isNull);
    expect(cards[3].editLink, isNull);
    final client = _EditClient()..threadMarkup = markup;
    final detail = await ForumRepository(
      client: client,
      historyStore: _History(),
    ).fetchThreadDetail(
      const ForumThread(
        title: 'fixture',
        url: 'read.php?tid-700.html',
        replies: 3,
        section: '',
      ),
    );
    expect(detail.bodyEditLink!.url, endsWith(op));
    expect(detail.replies.first.editLink!.url, endsWith(_link.url));
  });

  test(
    'modify preserves original BBCode and every untouched successful control',
    () async {
      final client = _EditClient();
      final repository = ForumRepository(client: client);
      final draft = await repository.fetchEditDraft(_link);
      expect(draft.title, 'Original & title');
      expect(
        draft.content,
        ' [hide=3]Original [b]BBCode[/b][/hide]\n[attachment=17] ',
      );
      expect(draft.fields['atc_enhidetype'], 'rvrc');
      expect(draft.actionPath, 'post.php?');
      final result = await repository.submitEdit(
        draft: draft,
        title: 'Changed',
        content: '${draft.content}\nMore',
      );
      expect(result.success, isTrue);
      expect(client.posts, hasLength(1));
      expect(client.multipart, isTrue);
      final sent = client.posts.single;
      expect(Map.fromEntries(sent), {
        'step': '2',
        'action': 'modify',
        'fid': '6',
        'tid': '700',
        'pid': '900',
        'article': '12',
        'special': '0',
        'verify': 'fixture-token',
        'atc_autourl': '1',
        'atc_usesign': '1',
        'atc_convert': '1',
        'atc_hide': '1',
        'atc_requireenhide': '1',
        'atc_requiresell': '1',
        'atc_rvrc': '3',
        'atc_money': '7',
        'atc_enhidetype': 'rvrc',
        'atc_credittype': 'money',
        'keep[]': '18',
        'atc_title': 'Changed',
        'atc_content': '${draft.content}\nMore',
        'Submit': ' 提 交 ',
      });
      expect(sent.where((e) => e.key == 'keep[]').map((e) => e.value), [
        '17',
        '18',
      ]);
    },
  );

  test('original BBCode may quote forum error phrases without blocking editing',
      () async {
    final client = _EditClient()
      ..form =
          _form.replaceAll('Original [b]BBCode[/b]', '您所在的用户组无法进行此操作，请先登录后再操作');
    final draft = await ForumRepository(client: client).fetchEditDraft(_link);
    expect(draft.content, contains('请先登录'));
  });

  for (final invalid in <String, String>{
    'reply form': _form.replaceAll('value="modify"', 'value="reply"'),
    'foreign action': _form.replaceAll(
      'action="post.php?"',
      'action="https://evil.invalid/post.php"',
    ),
    'wrong action': _form.replaceAll(
      'action="post.php?"',
      'action="post.php?action=reply"',
    ),
    'wrong pid': _form.replaceAll('value="900"', 'value="901"'),
    'wrong tid': _form.replaceAll('value="700"', 'value="701"'),
    'wrong step': _form.replaceAll(
      'name="step" value="2"',
      'name="step" value="1"',
    ),
    'GET form': _form.replaceAll('method="post"', 'method="get"'),
    'unsupported encoding':
        _form.replaceAll('multipart/form-data', 'text/plain'),
    'duplicate content': _form.replaceAll('</form>',
        '<textarea name="atc_content">conflicting body</textarea></form>'),
    'no editor': _form.replaceAll('textarea', 'div'),
    'duplicate identity': _form.replaceAll(
      '</form>',
      '<input name="pid" value="900"></form>',
    ),
  }.entries) {
    test('refuses ${invalid.key} without writing', () async {
      final client = _EditClient()..form = invalid.value;
      await expectLater(
        ForumRepository(client: client).fetchEditDraft(_link),
        throwsA(isA<ForumRequestException>()),
      );
      expect(client.posts, isEmpty);
    });
  }

  test('refuses unsafe edit URLs before requesting a form', () async {
    final client = _EditClient();
    final repository = ForumRepository(client: client);
    for (final url in [
      'https://evil.invalid/${_link.url}',
      _link.url.replaceAll('modify', 'reply'),
      'post.php?action=modify&fid=6&tid=700&pid=900&pid=901',
    ]) {
      await expectLater(
        repository.fetchEditDraft(ThreadActionLink(label: 'edit', url: url)),
        throwsA(isA<ForumRequestException>()),
      );
    }
    expect(client.reads, 0);
  });

  test(
    'draft binds repository and login epoch, including a pending fetch',
    () async {
      final client = _EditClient();
      final repository = ForumRepository(client: client);
      final draft = await repository.fetchEditDraft(_link);
      await expectLater(
        ForumRepository(
          client: client,
        ).submitEdit(draft: draft, title: '', content: 'changed'),
        throwsA(isA<ForumRequestException>()),
      );
      await repository.clearSession();
      await expectLater(
        repository.submitEdit(draft: draft, title: '', content: 'changed'),
        throwsA(isA<ForumRequestException>()),
      );
      final barrier = Completer<void>();
      client.readBarrier = barrier.future;
      final pending = repository.fetchEditDraft(_link);
      await repository.clearSession();
      barrier.complete();
      await expectLater(pending, throwsA(isA<ForumRequestException>()));
      expect(client.posts, isEmpty);
    },
  );

  test('guard rechecks session before a paced write is sent', () async {
    final client = _EditClient();
    final repository = ForumRepository(client: client);
    final draft = await repository.fetchEditDraft(_link);
    final barrier = Completer<void>();
    client.writeBarrier = barrier.future;
    final pending = repository.submitEdit(
      draft: draft,
      title: '',
      content: 'changed',
    );
    await repository.clearSession();
    barrier.complete();
    await expectLater(pending, throwsA(isA<ForumRequestException>()));
    expect(client.posts, isEmpty);
  });

  test('ambiguous writes are not retried and consume the draft', () async {
    final client = _EditClient()
      ..writeError = const ForumRequestException(
        ForumRequestKind.network,
        'unknown result',
      );
    final repository = ForumRepository(client: client);
    final draft = await repository.fetchEditDraft(_link);
    for (var attempt = 0; attempt < 2; attempt++) {
      await expectLater(
        repository.submitEdit(draft: draft, title: '', content: 'changed'),
        throwsA(isA<ForumRequestException>()),
      );
    }
    expect(client.posts, hasLength(1));
  });

  for (final acknowledgement in <String, String>{
    'generic prompt': '<title>南+ South Plus</title><p>提示信息</p>',
    'wording without redirect': '<title>南+ South Plus</title><p>发帖完毕</p>',
    'wrong thread': _ack.replaceAll('tid=700', 'tid=701'),
    'wrong post': _ack.replaceAll('#900', '#901'),
    'foreign origin':
        _ack.replaceAll('read.php?', 'https://evil.invalid/read.php?'),
    'wrong endpoint': _ack.replaceAll('read.php?', 'post.php?'),
    'unsafe scheme': _ack.replaceAll('read.php?', 'javascript:read.php?'),
    'no native wording': _ack.replaceAll('发帖完毕', '操作完成'),
    'conflicting refreshes': _ack.replaceFirst('</head>',
        '<meta http-equiv="refresh" content="1;url=read.php?tid=700#900"></head>'),
  }.entries) {
    test('${acknowledgement.key} remains ambiguous and cannot reuse the draft',
        () async {
      final client = _EditClient()..response = acknowledgement.value;
      final repository = ForumRepository(client: client);
      final draft = await repository.fetchEditDraft(_link);
      final result = await repository.submitEdit(
          draft: draft, title: 'Edited', content: 'Keep my edited text');
      expect(result.success, isFalse);
      expect(result.message, contains('未确认'));
      expect(result.message, contains('重新打开编辑'));
      expect(client.posts, hasLength(1));
      expect(Map.fromEntries(client.posts.single)['atc_content'],
          'Keep my edited text');
      await expectLater(
          repository.submitEdit(
              draft: draft, title: 'Edited', content: 'Keep my edited text'),
          throwsA(isA<ForumRequestException>()));
      expect(client.posts, hasLength(1));
    });
  }

  test(
      'explicit failure beats even a matching refresh and preserves its message',
      () async {
    final client = _EditClient()
      ..response = _ack.replaceAll('发帖完毕', '编辑失败：正文不能为空');
    final repository = ForumRepository(client: client);
    final draft = await repository.fetchEditDraft(_link);
    final result = await repository.submitEdit(
        draft: draft, title: 'Edited', content: 'Keep edited text');
    expect(result.success, isFalse);
    expect(result.message, contains('正文不能为空'));
    expect(client.posts, hasLength(1));
  });

  test('failure message is not treated as edit success', () async {
    final client = _EditClient()..response = '<title>错误：没有编辑权限</title>';
    final repository = ForumRepository(client: client);
    final draft = await repository.fetchEditDraft(_link);
    final result = await repository.submitEdit(
      draft: draft,
      title: '',
      content: 'changed',
    );
    expect(result.success, isFalse);
    expect(result.message, contains('权限'));
  });
}

class _History extends BrowsingHistoryStore {
  @override
  Future<void> recordThread(ForumThread thread, {DateTime? viewedAt}) async {}
}

class _EditClient extends ForumClient {
  String form = _form;
  String threadMarkup = '';
  String response = _ack;
  int reads = 0;
  bool multipart = false;
  final posts = <List<MapEntry<String, String>>>[];
  Future<void>? readBarrier;
  Future<void>? writeBarrier;
  Object? writeError;
  @override
  bool get isLoggedIn => true;
  @override
  Future<void> clearSession() async {}
  @override
  Future<String> get(String path) async => threadMarkup;
  @override
  Future<String> getForm(
    String path, {
    void Function()? requireCurrentSession,
    bool followRedirects = true,
  }) async {
    reads++;
    await readBarrier;
    requireCurrentSession?.call();
    return form;
  }

  @override
  Future<String> postForm(
    String path,
    List<MapEntry<String, String>> fields, {
    bool multipart = false,
    List<ForumFormFile> files = const [],
    void Function()? requireCurrentSession,
  }) async {
    await writeBarrier;
    requireCurrentSession?.call();
    expect(path, 'post.php?');
    this.multipart = multipart;
    posts.add(List.of(fields));
    if (writeError != null) throw writeError!;
    return response;
  }
}
