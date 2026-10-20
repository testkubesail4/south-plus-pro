import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../../models/forum_friend_models.dart';
import '../../models/forum_models.dart';
import '../forum_request_exception.dart';
import '../forum_url_resolver.dart';
import 'forum_response_parser.dart';

class NativeFriendPage {
  const NativeFriendPage(this.page, this.fields, this.jobs, this.complete);
  final ForumFriendPage page;
  final List<MapEntry<String, String>> fields;
  final Set<String> jobs;
  final bool complete;
}

class NativeFriendRequest {
  const NativeFriendRequest(this.request, this.fields);
  final ForumFriendRequest request;
  final List<MapEntry<String, String>> fields;
}

class ForumFriendsParser {
  ForumFriendsParser({required this.urls});
  final ForumUrlResolver urls;
  static final _uid = RegExp(r'^[1-9]\d*$');
  static const _response = ForumResponseParser();

  dom.Document document(String response) =>
      html.parse(_response.ajaxPayload(response) ?? response);

  NativeFriendPage parsePage(
    String response, {
    required String owner,
    required bool pending,
    required int page,
  }) {
    final doc = document(response);
    final forms = doc.querySelectorAll('form').where((form) {
      final uri = _formUri(form, 'u.php');
      return uri != null && uri.queryParameters['action'] == 'friend';
    });
    if (forms.length != 1) _invalid();
    final form = forms.single;
    if (form.querySelector('.u-table') == null) _invalid();
    final fields = _hidden(form);
    if (_value(fields, 'uid') != owner || !_token(_value(fields, 'verify'))) {
      _invalid();
    }
    final jobs = form
        .querySelectorAll('input[name="job"]')
        .map((input) => input.attributes['value'] ?? '')
        .toSet();
    if (pending
        ? !jobs.containsAll({'acceptadd', 'accept', 'refuse'})
        : !jobs.contains('delete')) _invalid();
    final items = <ForumFriend>[];
    final seen = <String>{};
    for (final checkbox in form.querySelectorAll('input[name="selid[]"]')) {
      final uid = checkbox.attributes['value'] ?? '';
      if (!_uid.hasMatch(uid) || !seen.add(uid)) _invalid();
      final row = _ancestor(checkbox, 'tr');
      if (row == null) _invalid();
      final links = row.querySelectorAll('a[href]').where(
            (link) =>
                urls.isForumUrl(link.attributes['href']!) &&
                urls.uidFromUrl(link.attributes['href']!) == uid,
          );
      final nameLink =
          links.where((link) => link.text.trim().isNotEmpty).firstOrNull;
      if (nameLink == null) _invalid();
      final image = row.querySelector('img[src]');
      final date = RegExp(
        r'\d{4}-\d{2}-\d{2}(?:\s+\d{2}:\d{2}(?::\d{2})?)?',
      ).firstMatch(row.text)?.group(0);
      final memberCell = _ancestor(nameLink, 'td');
      final extra = memberCell?.clone(true);
      extra
          ?.querySelectorAll('a, img, input, b')
          .forEach((element) => element.remove());
      final verification = clean(extra?.text ?? '');
      items.add(
        ForumFriend(
          uid: uid,
          name: clean(nameLink.text),
          url: urls.userTabUrl(uid, UserProfileTab.profile),
          avatarUrl: _image(image?.attributes['src']),
          joinedAt: date,
          verificationMessage:
              pending && verification.isNotEmpty ? verification : null,
        ),
      );
    }
    var total = page;
    final pager = doc.querySelector('.pages, .pagesone');
    var complete = page == 1 && pager == null;
    if (pager != null) {
      final counter = RegExp(
        r'Pages:\s*(\d+)\s*/\s*(\d+)',
        caseSensitive: false,
      ).firstMatch(pager.text);
      final current = int.tryParse(counter?.group(1) ?? '');
      final count = int.tryParse(counter?.group(2) ?? '');
      complete = page == 1 && current == 1 && count == 1;
      if (count != null && count >= page) total = count;
      for (final link in pager.querySelectorAll('a[href]')) {
        final raw = link.attributes['href']!;
        final uri = Uri.tryParse(urls.absoluteUrl(raw));
        final query = uri?.query ?? '';
        final linkOwner = urls.uidFromUrl(raw);
        final friendRoute = uri?.path == '/u.php' &&
            (uri?.queryParameters['action'] == 'friend' ||
                query.startsWith('action-friend-'));
        final linkPending =
            uri?.queryParameters['o'] == 'check' || query.contains('-o-check');
        if (!urls.isForumUrl(raw) ||
            !friendRoute ||
            linkOwner != owner ||
            linkPending != pending) {
          complete = false;
          continue;
        }
        final value = uri?.queryParameters['page'] ??
            RegExp(r'(?:^|-)page-(\d+)').firstMatch(query)?.group(1);
        final number = int.tryParse(value ?? '');
        if (number != null && number > total) total = number;
        if (number == null || number != 1) complete = false;
      }
    }
    return NativeFriendPage(
      ForumFriendPage(
        items: List.unmodifiable(items),
        pending: pending,
        page: page,
        pageCount: total,
      ),
      fields,
      jobs,
      complete,
    );
  }

  NativeFriendRequest? parseRequest(String response, String uid) {
    final doc = document(response);
    final forms = doc.querySelectorAll('form').where((form) {
      final uri = _formUri(form, 'pw_ajax.php');
      return uri != null && uri.queryParameters['action'] == 'addfriend';
    });
    if (forms.isEmpty) return null;
    if (forms.length != 1) _invalid();
    final form = forms.single;
    final fields = _hidden(form);
    if (_value(fields, 'touid') != uid ||
        _value(fields, 'job') != 'add' ||
        _value(fields, 'step') != '2' ||
        !_token(_value(fields, 'verify'))) _invalid();
    final input = form.querySelector('[name="checkmsg"]');
    if (input == null || input.attributes.containsKey('disabled')) _invalid();
    final maxLength = int.tryParse(input.attributes['maxlength'] ?? '');
    return NativeFriendRequest(
      ForumFriendRequest(
        uid: uid,
        maxLength: maxLength != null && maxLength > 0 ? maxLength : null,
      ),
      fields,
    );
  }

  ForumFriendAddResult addResult(String response) {
    final message = clean(document(response).body?.text ?? '');
    final status = message.contains('成功将对方加为好友')
        ? ForumFriendAddStatus.added
        : message.contains('正在等待好友验证') || message.contains('等待对方验证')
            ? ForumFriendAddStatus.pending
            : rejection(response) != null
                ? ForumFriendAddStatus.rejected
                : ForumFriendAddStatus.unknown;
    return ForumFriendAddResult(
      status: status,
      message:
          status == ForumFriendAddStatus.unknown ? '结果未确认，请刷新好友列表核对' : message,
    );
  }

  String? rejection(String response) {
    final doc = document(response);
    // User names and verification messages are not response status messages.
    if (doc.querySelector('form') != null) return null;
    final message = clean(doc.body?.text ?? '');
    return RegExp(
      r'非法|拒绝|失败|错误|权限|上限|不能|不允许|已经|已是|不存在|验证.*(?:过期|不正确)|请先登录|登录后',
    ).hasMatch(message)
        ? message
        : null;
  }

  Uri? _formUri(dom.Element form, String path) {
    final raw = form.attributes['action'] ?? '';
    final uri = Uri.tryParse(raw);
    final target = uri == null ? null : urls.baseUri.resolveUri(uri);
    return target?.origin == urls.baseUri.origin &&
            target?.userInfo.isEmpty == true &&
            target?.path == '/$path' &&
            (form.attributes['method'] ?? '').toLowerCase() == 'post'
        ? target
        : null;
  }

  dom.Element? _ancestor(dom.Element element, String tag) {
    for (var parent = element.parent; parent != null; parent = parent.parent) {
      if (parent.localName == tag) return parent;
    }
    return null;
  }

  List<MapEntry<String, String>> _hidden(dom.Element form) => form
      .querySelectorAll('input[type="hidden"][name]')
      .where((input) => !input.attributes.containsKey('disabled'))
      .map(
        (input) => MapEntry(
          input.attributes['name']!,
          input.attributes['value'] ?? '',
        ),
      )
      .toList();
  String? _value(List<MapEntry<String, String>> fields, String name) {
    final values = fields.where((field) => field.key == name).toList();
    return values.length == 1 ? values.single.value : null;
  }

  bool _token(String? value) =>
      value != null &&
      value.isNotEmpty &&
      !RegExp(r'[\x00-\x20\x7f]').hasMatch(value);
  String? _image(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final uri = Uri.tryParse(urls.absoluteUrl(raw));
    return uri != null &&
            {'http', 'https'}.contains(uri.scheme) &&
            uri.userInfo.isEmpty
        ? uri.toString()
        : null;
  }

  String clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();
  Never _invalid() => throw const ForumRequestException(
        ForumRequestKind.server,
        '无法识别论坛好友页面，请刷新后重试',
      );
}
