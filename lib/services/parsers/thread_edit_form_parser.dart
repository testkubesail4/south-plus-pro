import 'package:html/dom.dart' as dom;

import '../../models/forum_models.dart';
import '../forum_request_exception.dart';
import '../forum_url_resolver.dart';
import 'forum_form_parser.dart';
import 'forum_response_parser.dart';

class ThreadEditFormParser {
  ThreadEditFormParser(this.urls);
  final ForumUrlResolver urls;

  ({String path, Map<String, String> fields})? editTarget(String value) {
    final target = _postTarget(value);
    if (target == null || target.fields['action'] != 'modify') return null;
    final fields = target.fields;
    if (!_positive(fields['fid']) ||
        !_positive(fields['tid']) ||
        !_postId(fields['pid']) ||
        (fields['article'] != null &&
            !RegExp(r'^\d+$').hasMatch(fields['article']!))) return null;
    return target;
  }

  ThreadEditDraft parse(dom.Document document, ThreadActionLink link) {
    final target = editTarget(link.url);
    if (target == null) _invalid();
    final forms = document.querySelectorAll('form').where(
          (form) =>
              form.querySelector('textarea[name="atc_content"]') != null &&
              form.querySelector('input[name="action"][value="modify"]') !=
                  null,
        );
    if (forms.length != 1) _invalid();
    final form = forms.single;
    if ((form.attributes['method'] ?? '').toLowerCase() != 'post' ||
        form.querySelector('input[name="atc_title"]') == null) _invalid();
    final action = _postTarget(form.attributes['action'] ?? '');
    if (action == null) _invalid();
    final encoding = (form.attributes['enctype'] ?? '').toLowerCase();
    if (!const {'', 'application/x-www-form-urlencoded', 'multipart/form-data'}
        .contains(encoding)) _invalid();
    final controls = const ForumFormParser().defaultEntries(form);
    final fields = Map<String, String>.fromEntries(controls);
    for (final key in [
      'action',
      'step',
      'fid',
      'tid',
      'pid',
      'article',
      'atc_title',
      'atc_content'
    ]) {
      if (controls.where((entry) => entry.key == key).length != 1) _invalid();
    }
    if (fields['action'] != 'modify' || fields['step'] != '2') _invalid();
    for (final key in ['fid', 'tid', 'pid', 'article']) {
      if (target.fields.containsKey(key) && target.fields[key] != fields[key])
        _invalid();
    }
    for (final entry in action.fields.entries) {
      if (fields[entry.key] != entry.value) _invalid();
    }
    return ThreadEditDraft(
      title: fields['atc_title'] ?? '',
      content: fields['atc_content'] ?? '',
      fields: fields,
      controls: controls,
      actionPath: action.path,
      multipart: encoding == 'multipart/form-data',
    );
  }

  ReplyResult parseResult(dom.Document document, ThreadEditDraft draft) {
    final text = '${document.querySelector('title')?.text ?? ''}\n'
        '${document.body?.text ?? ''}';
    if (RegExp(r'错误|失败|不能为空|权限|认证码|验证码|灌水').hasMatch(text)) {
      return ReplyResult(
          success: false,
          message: const ForumResponseParser().pageMessage(text));
    }
    final refreshes = document.querySelectorAll('meta[http-equiv]').where(
        (meta) => meta.attributes['http-equiv']!.toLowerCase() == 'refresh');
    if (text.contains('发帖完毕') && refreshes.length == 1) {
      final match = RegExp(r'^\s*\d+(?:\.\d+)?\s*;\s*url\s*=\s*(.+)$',
              caseSensitive: false)
          .firstMatch(refreshes.single.attributes['content'] ?? '');
      var target = match?.group(1)?.trim() ?? '';
      if (target.length >= 2 &&
          ((target.startsWith('"') && target.endsWith('"')) ||
              (target.startsWith("'") && target.endsWith("'")))) {
        target = target.substring(1, target.length - 1);
      }
      final parsed = Uri.tryParse(target);
      final uri = parsed == null ? null : urls.baseUri.resolveUri(parsed);
      if (target.isNotEmpty &&
          uri != null &&
          uri.userInfo.isEmpty &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.origin == urls.baseUri.origin &&
          uri.path == '/read.php' &&
          urls.tidFromUrl(uri.toString()) == draft.fields['tid'] &&
          uri.fragment == draft.fields['pid']) {
        return const ReplyResult(success: true, message: '编辑已保存');
      }
    }
    return const ReplyResult(success: false, message: '提交结果未确认，请刷新帖子确认后重新打开编辑');
  }

  ({String path, Map<String, String> fields})? _postTarget(String value) {
    if (value.isEmpty || !urls.isForumUrl(value)) return null;
    final uri = Uri.tryParse(urls.absoluteUrl(value));
    if (uri == null || uri.path != '/post.php' || uri.hasFragment) return null;
    final fields = <String, String>{};
    if (uri.query.isNotEmpty) {
      if (uri.query.contains('=')) {
        for (final entry in uri.queryParametersAll.entries) {
          if (entry.value.length != 1) return null;
          fields[entry.key] = entry.value.single;
        }
      } else {
        final parts = uri.query.replaceFirst(RegExp(r'\.html$'), '').split('-');
        if (parts.length.isOdd) return null;
        for (var i = 0; i < parts.length; i += 2) {
          if (fields.containsKey(parts[i])) return null;
          fields[parts[i]] = parts[i + 1];
        }
      }
    }
    if (fields.keys.any(
      (key) => !const {'action', 'fid', 'tid', 'pid', 'article'}.contains(key),
    )) return null;
    return (path: urls.relativePath(uri.toString()), fields: fields);
  }

  bool _positive(String? value) => RegExp(r'^[1-9]\d*$').hasMatch(value ?? '');
  bool _postId(String? value) => value == 'tpc' || _positive(value);
  Never _invalid() => throw const ForumRequestException(
        ForumRequestKind.invalidInput,
        '编辑表单无效，请重新打开编辑',
      );
}
