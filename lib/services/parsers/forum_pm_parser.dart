import 'package:html/dom.dart' as dom;

import '../../models/forum_models.dart';
import '../../models/forum_pm_models.dart';
import '../forum_network_config.dart';
import '../forum_request_exception.dart';
import 'forum_form_parser.dart';
import 'thread_content_parser.dart';
import '../forum_url_resolver.dart';

class ForumPmRoute {
  const ForumPmRoute(this.path, this.action, this.fields);
  final String path;
  final String action;
  final Map<String, String> fields;
}

class ForumPmParser {
  ForumPmParser({required this.baseUri});
  final Uri baseUri;

  static final _positive = RegExp(r'^[1-9]\d*$');
  static final _token = RegExp(r'^[\w~-]+$');

  String? _peerUid(dom.Element cell) {
    final urls = ForumUrlResolver(baseUri: baseUri);
    final uids = <String>{};
    for (final link in cell.querySelectorAll('a[href]')) {
      final target = urls.forumLinkTarget(link.attributes['href']!);
      if (target is! ForumUserLinkTarget) continue;
      final uid = urls.uidFromUrl(target.userUrl);
      if (uid != null) uids.add(uid);
    }
    return uids.length == 1 ? uids.single : null;
  }

  ForumPmRoute? route(String? href, Set<String> actions) {
    if (href == null || href.trim().isEmpty) return null;
    try {
      final uri = baseUri.resolve(href.trim());
      final host = uri.host.replaceFirst(RegExp(r'^www\.'), '');
      final baseHost = baseUri.host.replaceFirst(RegExp(r'^www\.'), '');
      if (uri.scheme != baseUri.scheme ||
          uri.port != baseUri.port ||
          uri.userInfo.isNotEmpty ||
          uri.hasFragment ||
          uri.path != '/message.php' ||
          (host != baseHost &&
              !ForumNetworkConfig.sites.any((s) => s.host == host))) {
        return null;
      }
      final fields = <String, String>{};
      if (uri.query.isEmpty) {
        fields['action'] = 'receivebox';
      } else if (uri.query.contains('=')) {
        for (final entry in uri.queryParametersAll.entries) {
          if (entry.value.length != 1) return null;
          fields[entry.key] = entry.value.single;
        }
      } else {
        final patterns = <RegExp>[
          RegExp(r'^(receivebox|sendbox|scout)(?:-page-([1-9]\d*))?\.html$'),
          RegExp(r'^(read|readpub|readsnd|readscout)-mid-([1-9]\d*)\.html$'),
          RegExp(r'^write(?:-(touid|remid|transmit|edmid)-([1-9]\d*))?\.html$'),
          RegExp(r'^chatlog-withuid-([1-9]\d*)(?:-page-([1-9]\d*))?\.html$'),
          RegExp(r'^unread-mid-([1-9]\d*)-verify-([\w~-]+)\.html$'),
          RegExp(
              r'^del-towhere-(receivebox|sendbox|scout)-delids-([1-9]\d*)-verify-([\w~-]+)\.html$'),
        ];
        if (!uri.query.startsWith('action-')) return null;
        final query = uri.query.substring(7);
        var matched = false;
        for (var i = 0; i < patterns.length; i++) {
          final match = patterns[i].firstMatch(query);
          if (match == null) continue;
          matched = true;
          switch (i) {
            case 0:
              fields['action'] = match[1]!;
              if (match[2] != null) fields['page'] = match[2]!;
            case 1:
              fields.addAll({'action': match[1]!, 'mid': match[2]!});
            case 2:
              fields['action'] = 'write';
              if (match[1] != null) fields[match[1]!] = match[2]!;
            case 3:
              fields.addAll({'action': 'chatlog', 'withuid': match[1]!});
              if (match[2] != null) fields['page'] = match[2]!;
            case 4:
              fields.addAll(
                  {'action': 'unread', 'mid': match[1]!, 'verify': match[2]!});
            case 5:
              fields.addAll({
                'action': 'del',
                'towhere': match[1]!,
                'delids': match[2]!,
                'verify': match[3]!
              });
          }
          break;
        }
        if (!matched) return null;
      }
      final action = fields['action'];
      if (action == null || !actions.contains(action)) return null;
      final allowed = switch (action) {
        'receivebox' || 'sendbox' || 'scout' => {'action', 'page'},
        'read' || 'readpub' || 'readsnd' || 'readscout' => {'action', 'mid'},
        'write' => {'action', 'touid', 'remid', 'transmit', 'edmid'},
        'chatlog' => {'action', 'withuid', 'page'},
        'unread' => {'action', 'mid', 'verify'},
        'del' => {'action', 'towhere', 'delids', 'verify'},
        _ => <String>{},
      };
      if (fields.keys.any((key) => !allowed.contains(key))) return null;
      for (final key in [
        'page',
        'mid',
        'touid',
        'remid',
        'transmit',
        'edmid',
        'withuid',
        'delids'
      ]) {
        if (fields.containsKey(key) && !_positive.hasMatch(fields[key]!))
          return null;
      }
      if (['read', 'readpub', 'readsnd', 'readscout', 'unread']
              .contains(action) &&
          !fields.containsKey('mid')) return null;
      if (action == 'chatlog' && !fields.containsKey('withuid')) return null;
      if (action == 'write' && fields.length > 2) return null;
      if (['unread', 'del'].contains(action) &&
          !_token.hasMatch(fields['verify'] ?? '')) return null;
      if (action == 'del' &&
          (!fields.containsKey('delids') ||
              !ForumPmBox.values.any((b) => b.wireName == fields['towhere'])))
        return null;
      return ForumPmRoute(
          'message.php${uri.hasQuery ? '?${uri.query}' : ''}', action, fields);
    } on FormatException {
      return null;
    }
  }

  ForumPmRoute requireRoute(String href, Set<String> actions) =>
      route(href, actions) ??
      (throw const ForumRequestException(
          ForumRequestKind.server, '不是安全的私讯操作入口'));

  Set<String> detailActions(ForumPmBox box) => switch (box) {
        ForumPmBox.inbox => {'read', 'readpub'},
        ForumPmBox.sendbox => {'readsnd'},
        ForumPmBox.scout => {'readscout'},
      };

  dom.Element? listForm(dom.Document document, ForumPmBox box) {
    for (final form in document.querySelectorAll('form')) {
      if ((form.attributes['method'] ?? '').toLowerCase() != 'post') continue;
      final target =
          route(form.attributes['action'], {'receivebox', box.wireName});
      if (target == null || target.fields.length != 1) continue;
      if (form.querySelector('input[name="towhere"]')?.attributes['value'] ==
              box.wireName &&
          form.querySelector('input[name="verify"]') != null) return form;
    }
    return null;
  }

  ForumPmPage parseBox(dom.Document document, ForumPmBox box,
      {int currentPage = 1}) {
    final messages = <ForumPmSummary>[];
    for (final row in document.querySelectorAll('tr')) {
      dom.Element? titleLink;
      ForumPmRoute? detail;
      for (final link in row.querySelectorAll('a[href]')) {
        final candidate = route(link.attributes['href'], detailActions(box));
        if (candidate != null) {
          titleLink = link;
          detail = candidate;
          break;
        }
      }
      if (titleLink == null || detail == null) continue;
      final cells = row.children.where((e) => e.localName == 'td').toList();
      final titleIndex = cells.indexWhere((cell) => cell.contains(titleLink!));
      if (titleIndex < 1 || titleIndex + 1 >= cells.length) continue;
      final peerCell = cells[titleIndex - 1];
      final id = detail.fields['mid']!;
      final type = switch (detail.action) {
        'readpub' => ForumPmType.broadcast,
        'readsnd' => ForumPmType.sent,
        'readscout' => ForumPmType.tracked,
        _ => ForumPmType.personal,
      };
      String? edit;
      for (final link in row.querySelectorAll('a[href]')) {
        final candidate = route(link.attributes['href'], {'write'});
        if (candidate?.fields['edmid'] == id) edit = candidate!.path;
      }
      final checkbox =
          row.querySelector('input[name="delid[]"][type="checkbox"]');
      final readText = titleIndex + 2 < cells.length
          ? clean(cells[titleIndex + 2].text)
          : '';
      messages.add(ForumPmSummary(
        box: box,
        type: type,
        id: id,
        peer: clean(peerCell.text),
        peerUid: _peerUid(peerCell),
        title: clean(titleLink.text),
        time: clean(cells[titleIndex + 1].text),
        unread: titleLink.classes.contains('b'),
        recipientRead: box == ForumPmBox.scout
            ? switch (readText) { '是' => true, '否' => false, _ => null }
            : null,
        detailPath: detail.path,
        editPath: edit,
        canDelete: checkbox?.attributes['value'] == id &&
            !checkbox!.attributes.containsKey('disabled'),
      ));
    }
    final form = listForm(document, box);
    final hasHeader = form?.querySelectorAll('tr').any((row) {
          final labels = row.children.map((cell) => clean(cell.text)).toSet();
          return labels.contains('标题') && labels.contains('时间');
        }) ??
        false;
    if (messages.isEmpty && !hasHeader) {
      throw const ForumRequestException(ForumRequestKind.server, '没有识别到私讯列表');
    }
    final links = pageLinks(document, {box.wireName});
    final next = _nextPage(links, currentPage, {box.wireName});
    final pagers = document.querySelectorAll('.pages, .pagination');
    final markers = <int>{};
    var missingForward = false;
    for (final pager in pagers) {
      final pageText = pager.nodes.map((node) => node.text ?? '').join(' ');
      final pages = RegExp(r'Pages:\s*(\d+)\s*/\s*(\d+)').firstMatch(clean(pageText));
      if (pages != null) {
        markers.add(int.parse(pages[1]!));
        if (int.parse(pages[2]!) > currentPage && next == null) missingForward = true;
      }
      for (final selected in pager.querySelectorAll('b, strong, .current')) {
        final number = int.tryParse(clean(selected.text));
        if (number != null) markers.add(number);
      }
    }
    final paginationKnown = !missingForward && (pagers.isEmpty ? currentPage == 1 :
        markers.isNotEmpty ? markers.length == 1 && markers.single == currentPage :
        currentPage == 1 && links.isNotEmpty);
    return ForumPmPage(
        box: box,
        messages: List.unmodifiable(messages),
        pageLinks: links,
        hasUnread: hasUnread(document),
        currentPage: currentPage,
        nextPagePath: next,
        paginationKnown: paginationKnown);
  }

  ForumPmRoute requireDetail(ForumPmSummary message) {
    final expected = switch (message.type) {
      ForumPmType.personal => 'read',
      ForumPmType.broadcast => 'readpub',
      ForumPmType.sent => 'readsnd',
      ForumPmType.tracked => 'readscout',
    };
    final target = requireRoute(message.detailPath, detailActions(message.box));
    if (target.action != expected || target.fields['mid'] != message.id) {
      throw const ForumRequestException(ForumRequestKind.server, '私讯身份与所属箱不一致');
    }
    return target;
  }

  ForumPmDetail parseDetail(dom.Document document, ForumPmSummary message) {
    final rows = <String, dom.Element>{};
    for (final row in document.querySelectorAll('table.set-table2 tr')) {
      final cells = row.children.where((e) => e.localName == 'td').toList();
      if (cells.length < 2) continue;
      rows[clean(cells.first.text).replaceAll(RegExp(r'[:：]'), '')] = cells[1];
    }
    final sender = rows['发件人'] ?? rows['收件人'];
    final content = rows['内容'];
    final options = rows['选项'];
    if (sender == null ||
        content == null ||
        options == null ||
        rows['标题'] == null ||
        rows['时间'] == null) {
      throw const ForumRequestException(ForumRequestKind.server, '没有识别到私讯详情');
    }
    final nativeUid = _peerUid(sender);
    final peerUid = message.peerUid == null || message.peerUid == nativeUid
        ? nativeUid
        : null;
    String? reply, forward, edit, chatlog, unread, delete;
    for (final link in options.querySelectorAll('a[href]')) {
      final target =
          route(link.attributes['href'], {'write', 'chatlog', 'unread', 'del'});
      if (target == null) continue;
      final fields = target.fields;
      switch (target.action) {
        case 'write':
          if ((fields['remid'] == message.id &&
                  message.type == ForumPmType.personal) ||
              (fields.containsKey('touid') &&
                  (message.peerUid == null ||
                      fields['touid'] == message.peerUid))) reply = target.path;
          if (fields['transmit'] == message.id) forward = target.path;
          if (fields['edmid'] == message.id && message.box == ForumPmBox.scout)
            edit = target.path;
        case 'chatlog':
          chatlog = target.path;
        case 'unread':
          if (fields['mid'] == message.id &&
              message.type == ForumPmType.personal) unread = target.path;
        case 'del':
          if (message.type != ForumPmType.broadcast &&
              fields['delids'] == message.id &&
              fields['towhere'] == message.box.wireName) delete = target.path;
      }
    }
    return ForumPmDetail(
        summary: ForumPmSummary(
          box: message.box,
          type: message.type,
          id: message.id,
          peer: clean(sender.text),
          peerUid: peerUid,
          title: clean(rows['标题']!.text),
          time: clean(rows['时间']!.text),
          unread: false,
          recipientRead: message.recipientRead,
          detailPath: message.detailPath,
          editPath: edit,
          canDelete: message.canDelete,
        ),
        sender: clean(sender.text),
        title: clean(rows['标题']!.text),
        time: clean(rows['时间']!.text),
        content: plainText(content),
        segments: ThreadContentParser(urls: ForumUrlResolver(baseUri: baseUri))
            .extractInlineSegments(content),
        replyPath: reply,
        forwardPath: forward,
        editPath: edit,
        chatlogPath: chatlog,
        markUnreadPath: unread,
        deletePath: delete,
        hasUnread: hasUnread(document));
  }

  ForumPmCompose parseCompose(dom.Document document, ForumPmRoute source) {
    for (final form in document.querySelectorAll('form')) {
      if ((form.attributes['method'] ?? '').toLowerCase() != 'post') continue;
      final action = route(form.attributes['action'], {'receivebox'});
      if (action == null || Uri.parse(action.path).query.isNotEmpty) continue;
      final fields = const ForumFormParser().defaults(form);
      if (fields['action'] != 'write' ||
          fields['step'] != '2' ||
          !_token.hasMatch(fields['verify'] ?? '') ||
          form.querySelector('[name="touidmsg"]') == null ||
          form.querySelector('[name="msg_title"]') == null ||
          form.querySelector('textarea[name="atc_content"]') == null ||
          fields['edmid'] != source.fields['edmid']) continue;
      return ForumPmCompose(
          actionPath: action.path,
          fields: fields,
          recipientUid: fields['touidmsg'] ?? '',
          title: fields['msg_title'] ?? '',
          body: fields['atc_content'] ?? '',
          saveToSendbox: fields['ifsave'] == 'Y',
          isEdit: fields.containsKey('edmid'));
    }
    throw const ForumRequestException(ForumRequestKind.server, '没有识别到私讯写信表单');
  }

  void validateCompose(ForumPmCompose compose) {
    final target = requireRoute(compose.actionPath, {'receivebox'});
    if (Uri.parse(target.path).query.isNotEmpty ||
        compose.fields['action'] != 'write' ||
        compose.fields['step'] != '2' ||
        !_token.hasMatch(compose.fields['verify'] ?? '') ||
        (compose.fields.containsKey('edmid') &&
            !_positive.hasMatch(compose.fields['edmid']!)) ||
        compose.isEdit != compose.fields.containsKey('edmid')) {
      throw const ForumRequestException(
          ForumRequestKind.server, '私讯写信表单无效，请重新载入');
    }
  }

  Map<String, String> singleDeleteFields(
      dom.Document document, ForumPmSummary message) {
    final page = parseBox(document, message.box);
    final allowed = page.messages.any((row) =>
        row.id == message.id && row.type == message.type && row.canDelete);
    final form = listForm(document, message.box);
    final verify =
        form?.querySelector('input[name="verify"]')?.attributes['value'] ?? '';
    if (!allowed || !_token.hasMatch(verify)) {
      throw const ForumRequestException(
          ForumRequestKind.server, '服务器未提供此消息的删除权限，请重新载入');
    }
    return {
      'verify': verify,
      'delid[]': message.id,
      'towhere': message.box.wireName,
      'action': 'del'
    };
  }

  ForumPmActionResult parseUnreadResult(
      dom.Document document, ForumPmSummary message) {
    if (document.querySelector('form, table.set-table2') == null)
      return parseActionResult(document);
    final page = parseBox(document, ForumPmBox.inbox);
    if (page.hasUnread != false &&
        page.messages.any((row) =>
            row.type == ForumPmType.personal &&
            row.id == message.id &&
            row.unread)) {
      return const ForumPmActionResult(message: '标记未读完成');
    }
    throw const ForumRequestException(ForumRequestKind.server, '没有确认标记未读完成');
  }

  ForumPmActionResult parseActionResult(dom.Document document) {
    final text =
        '${document.querySelector('title')?.text ?? ''} ${document.body?.text ?? ''}';
    if (!text.contains('操作完成') ||
        RegExp(r'错误|失敗|失败|非法|认证码|認證碼|不能为空|不能為空').hasMatch(text) ||
        document.querySelector('form, table.set-table2') != null) {
      throw const ForumRequestException(
          ForumRequestKind.server, '没有确认私讯操作完成，请检查服务器状态，勿重复提交');
    }
    String? refresh;
    for (final meta in document.querySelectorAll('meta[http-equiv]')) {
      if (meta.attributes['http-equiv']!.toLowerCase() != 'refresh') continue;
      final match = RegExp(
              r'''^\s*\d+(?:\.\d+)?\s*;\s*url\s*=\s*['"]?([^'"]+)['"]?\s*$''',
              caseSensitive: false)
          .firstMatch(meta.attributes['content'] ?? '');
      refresh =
          route(match?.group(1), {'receivebox', 'sendbox', 'scout'})?.path;
    }
    return ForumPmActionResult(message: '操作完成', refreshPath: refresh);
  }

  ForumPmChatlog parseChatlog(dom.Document document, String withuid,
      {int currentPage = 1}) {
    final table = document.querySelector('table.set-table2');
    final form =
        document.querySelector('input[name="action"][value="dellog"]')?.parent;
    final endpoint =
        form == null ? null : route(form.attributes['action'], {'receivebox'});
    if (table == null ||
        form?.localName != 'form' ||
        endpoint == null ||
        Uri.parse(endpoint.path).query.isNotEmpty ||
        (form!.attributes['method'] ?? '').toLowerCase() != 'post' ||
        form.querySelector('input[name="withuid"]')?.attributes['value'] !=
            withuid) {
      throw const ForumRequestException(ForumRequestKind.server, '没有识别到通信记录');
    }
    final records = <ForumPmChatRecord>[];
    for (final checkbox in table.querySelectorAll('input[name="selid[]"]')) {
      final time = checkbox.parent;
      final record = time?.parent;
      final title = record?.querySelector('span.s2 b');
      if (time == null ||
          !time.classes.containsAll({'fr', 'gray'}) ||
          record?.localName != 'div' ||
          title == null) {
        throw const ForumRequestException(
            ForumRequestKind.server, '通信记录结构无法识别');
      }
      final body = record!.clone(true);
      body.querySelector('span.fr.gray')?.remove();
      body.querySelector('span.s2')?.remove();
      final id = checkbox.attributes['value'];
      records.add(ForumPmChatRecord(
          id: _positive.hasMatch(id ?? '') ? id : null,
          sender: '',
          title: clean(title.text),
          time: clean(time.text),
          content: plainText(body),
          segments:
              ThreadContentParser(urls: ForumUrlResolver(baseUri: baseUri))
                  .extractInlineSegments(body)));
    }
    String? compose;
    for (final link in document.querySelectorAll('a[href]')) {
      if (table.contains(link)) continue;
      final target = route(link.attributes['href'], {'write'});
      if (target?.fields['touid'] == withuid) compose = target!.path;
    }
    final links = pageLinks(document, {'chatlog'}, withuid: withuid);
    return ForumPmChatlog(
        records: List.unmodifiable(records),
        composePath: compose,
        pageLinks: links,
        currentPage: currentPage,
        nextPagePath: _nextPage(links, currentPage, {'chatlog'}));
  }

  String plainText(dom.Element element) {
    final buffer = StringBuffer();
    void walk(dom.Node node) {
      if (node is dom.Text) {
        buffer.write(node.text.replaceAll(RegExp(r'[ \t\r\f]+'), ' '));
        return;
      }
      if (node is! dom.Element) return;
      final tag = node.localName;
      if ({
        'script',
        'style',
        'form',
        'input',
        'button',
        'iframe',
        'object',
        'embed',
        'noscript'
      }.contains(tag)) return;
      if (tag == 'br') {
        buffer.writeln();
        return;
      }
      if (tag == 'img') {
        final alt = clean(node.attributes['alt'] ?? '');
        buffer.write(alt.isEmpty ? '[图片]' : '[图片：$alt]');
        return;
      }
      final block = {
        'p',
        'div',
        'blockquote',
        'pre',
        'li',
        'tr',
        'h1',
        'h2',
        'h3'
      }.contains(tag);
      if (block) buffer.writeln();
      for (final child in node.nodes) {
        walk(child);
      }
      if (block) buffer.writeln();
    }

    for (final node in element.nodes) {
      walk(node);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .trim();
  }

  List<ForumPmPageLink> pageLinks(dom.Document document, Set<String> actions,
      {String? withuid}) {
    final links = <ForumPmPageLink>[];
    final seen = <String>{};
    for (final link
        in document.querySelectorAll('.pages a[href], .pagination a[href]')) {
      final candidate = route(link.attributes['href'], actions);
      if (candidate == null ||
          !candidate.fields.containsKey('page') ||
          (withuid != null && candidate.fields['withuid'] != withuid) ||
          !seen.add(candidate.path)) continue;
      links.add(ForumPmPageLink(label: clean(link.text), path: candidate.path));
    }
    return List.unmodifiable(links);
  }

  String? _nextPage(
      List<ForumPmPageLink> links, int currentPage, Set<String> actions) {
    for (final link in links) {
      if (route(link.path, actions)?.fields['page'] == '${currentPage + 1}') {
        return link.path;
      }
    }
    return null;
  }

  bool? hasUnread(dom.Document document) {
    for (final image in document.querySelectorAll('img[src]')) {
      final file = Uri.tryParse(image.attributes['src']!)?.path.split('/').last;
      if (file == 'shortmail.gif') return true;
      if (file == 'no-shortmail.gif') return false;
    }
    return null;
  }

  String clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();
}
