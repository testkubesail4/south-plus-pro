import 'dart:async';
import 'dart:convert';

import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

// Sanitized native sidebar/content ancestry and forms; all account/thread values are fictional.
String nativeFavoriteHtml(
    {List<String> categories = const ['A', 'B'],
    List<({String id, String tid, String category})> rows = const [
      (id: '501', tid: '701', category: ''),
      (id: '502', tid: '702', category: 'A')
    ],
    String token = 'fixture-token',
    String? filter,
    int pageCount = 1,
    int page = 1,
    bool missingTable = false}) {
  const escape = HtmlEscape(HtmlEscapeMode.attribute);
  String e(String value) => escape.convert(value);
  String categoryName(String id) =>
      id == '0' ? '' : categories[int.parse(id) - 1];
  final visible = rows
      .where((row) => filter == null || row.category == categoryName(filter));
  return '''<html><head><title>南+ South Plus</title></head><body>
<div id="u-content"><div id="u-contentside"><div id="u-fav-cate"><table class="u-table">
<tr><td id="uf_forum" class="fav forum"><a href="u.php?action-favor-uid-901-type-forum.html">收藏的版块</a></td></tr>
<tr><td id="uf_all" class="fav"><a href="u.php?action-favor-uid-901.html">收藏的帖子</a></td></tr>
<tr><td id="uf_0" class="fav"><a href="u.php?action-favor-uid-901-type-0.html">默认分类</a></td></tr>
${[
    for (var i = 0; i < categories.length; i++)
      '''<tr><td id="uf_${i + 1}" class="fav"><a href="u.php?action-favor-job-deltype-type-${i + 1}-uid-901-verify-${e(token)}.html" class="fr" onclick="return Checkinfo();" title="删除目录"><img src="images/colorImagination/tips-close.png"></a><a href="u.php?action-favor-uid-901-type-${i + 1}.html">${e(categories[i])}</a></td></tr>'''
  ].join()}
<tr><td><form method="post" name="form" action="u.php?action=favor&amp;"><input type="hidden" name="verify" value="${e(token)}"><input type="hidden" name="job" value="addtype"><strong>添加收藏分类</strong><div style="padding:.5em 0">名称 <input class="input" type="text" name="type" size="6"><input class="btn" type="submit" value="提 交"></div></form></td></tr>
</table></div></div><div id="u-contentmain"><form method="post" action="u.php?action=favor&amp;">
<input type="hidden" name="verify" value="${e(token)}">
${missingTable ? '' : '''<table class="u-table"><tr><td>标题</td><td>作者</td><td>目录</td><td></td></tr>
${visible.map((row) => '''<tr><th><a href="read.php?tid-${row.tid}.html">Synthetic ${row.tid}</a></th><td><a href="u.php?uid-902.html">Synthetic author</a></td><td>${e(row.category)}</td><td><input type="checkbox" name="selid[]" value="${row.id}"></td></tr>''').join()}
</table>'''}
<input type="radio" name="job" value="change" checked>&nbsp;目录转换 <select name="type"><option value="0"></option>${[
    for (var i = 0; i < categories.length; i++)
      '<option value="${i + 1}">${e(categories[i])}</option>'
  ].join()}</select>
<input type="radio" name="job" value="clear">&nbsp;删除 <input class="btn" type="button" name="chkall" value="全 选" onclick="CheckAll(this.form)"><input class="btn" type="submit" value="提 交"></form>
${pageCount == 1 ? '' : '<ul class="pages"><li class="pagesone">Pages: $page&nbsp; / $pageCount</li></ul>'}
</div></div></body></html>''';
}

const nativeFavoriteAck =
    '<html><head><meta http-equiv="refresh" content="1;url=u.php?action=favor"></head>'
    '<body><div id="main"><div class="t"><div class="f_one"><center>操作完成</center></div></div></div></body></html>';

class NativeFavoriteClient extends ForumClient {
  List<String> categories = ['A', 'B'];
  List<({String id, String tid, String category})> rows = [
    (id: '501', tid: '701', category: ''),
    (id: '502', tid: '702', category: 'A')
  ];
  final reads = <Uri>[];
  final writes = <(String, List<MapEntry<String, String>>)>[];
  bool loggedIn = true;
  int pageCount = 1;
  bool missingTable = false;
  bool applyWrite = true;
  bool throwAfterWrite = false;
  bool failReadback = false;
  bool failDestination = false;
  String postResponse = nativeFavoriteAck;
  void Function()? beforeNextRead;
  String Function(String)? pageTransform;
  Completer<void>? readGate;
  Completer<void>? writeGate;
  final writeStarted = Completer<void>();
  String? favoriteResponse;
  int tokenNumber = 0;
  Set<String>? applyOnlyIds;

  @override
  bool get isLoggedIn => loggedIn;
  @override
  Future<void> clearSession() async {
    loggedIn = false;
  }

  @override
  Future<String> getOnce(String path) => get(path);
  @override
  Future<String> get(String path) async {
    if (path == 'u.php')
      return '<a href="u.php?action-show-uid-901.html">Synthetic account</a>';
    if (path.contains('action-show'))
      return '<div id="u-top"><h1 class="u-h1">Synthetic account</h1></div>';
    return getForm(path);
  }

  @override
  Future<String> getForm(String path,
      {void Function()? requireCurrentSession,
      bool followRedirects = true}) async {
    requireCurrentSession?.call();
    final uri = Uri.parse(path);
    reads.add(uri);
    if (uri.path == 'pw_ajax.php') {
      if (uri.queryParameters['type'] == null)
        return '<ajax><![CDATA[unknown]]></ajax>';
      writes.add((path, const []));
      if (!writeStarted.isCompleted) writeStarted.complete();
      final tid = uri.queryParameters['tid']!;
      final already = rows.any((row) => row.tid == tid);
      if (applyWrite && !already) {
        final type = uri.queryParameters['type']!;
        rows.add((
          id: tid,
          tid: tid,
          category: type == '0' ? '' : categories[int.parse(type) - 1]
        ));
      }
      if (writeGate != null) await writeGate!.future;
      requireCurrentSession?.call();
      if (throwAfterWrite)
        throw const ForumRequestException(
            ForumRequestKind.rateLimited, '请求过于频繁');
      return favoriteResponse ??
          '<ajax><![CDATA[${already ? '您已经收藏了该主题' : '帖子收藏成功!'}]]></ajax>';
    }
    final change = beforeNextRead;
    beforeNextRead = null;
    change?.call();
    if (readGate != null) await readGate!.future;
    requireCurrentSession?.call();
    if (failReadback && writes.isNotEmpty ||
        failDestination && uri.queryParameters.containsKey('type')) {
      throw const ForumRequestException(
          ForumRequestKind.network, 'fixture readback failed');
    }
    final html = nativeFavoriteHtml(
        categories: categories,
        rows: rows,
        token: 'token-${++tokenNumber}',
        filter: uri.queryParameters['type'],
        pageCount: pageCount,
        missingTable: missingTable);
    return pageTransform?.call(html) ?? html;
  }

  @override
  Future<String> postForm(String path, List<MapEntry<String, String>> fields,
      {bool multipart = false,
      List<ForumFormFile> files = const [],
      void Function()? requireCurrentSession}) async {
    requireCurrentSession?.call();
    writes.add((path, List.of(fields)));
    if (!writeStarted.isCompleted) writeStarted.complete();
    String value(String name) =>
        fields.firstWhere((entry) => entry.key == name).value;
    final ids = fields
        .where((entry) => entry.key == 'selid[]')
        .map((entry) => entry.value)
        .toSet();
    final appliedIds =
        applyOnlyIds == null ? ids : ids.intersection(applyOnlyIds!);
    if (applyWrite) {
      switch (value('job')) {
        case 'addtype':
          categories.add(value('type'));
        case 'deltype':
          final label = categories.removeAt(int.parse(value('type')) - 1);
          rows = rows
              .map((row) => row.category == label
                  ? (id: row.id, tid: row.tid, category: '')
                  : row)
              .toList();
        case 'change':
          final type = value('type');
          final category = type == '0' ? '' : categories[int.parse(type) - 1];
          rows = rows
              .map((row) => appliedIds.contains(row.id)
                  ? (id: row.id, tid: row.tid, category: category)
                  : row)
              .toList();
        case 'clear':
          rows.removeWhere((row) => appliedIds.contains(row.id));
      }
    }
    if (writeGate != null) await writeGate!.future;
    requireCurrentSession?.call();
    if (throwAfterWrite)
      throw const ForumRequestException(ForumRequestKind.rateLimited, '请求过于频繁');
    return postResponse;
  }
}
