import 'package:html/dom.dart' as dom;

import '../../models/forum_models.dart';
import '../forum_request_exception.dart';
import '../forum_url_resolver.dart';
import 'forum_form_parser.dart';

class ThreadTransactionParser {
  ThreadTransactionParser(this.urls);
  final ForumUrlResolver urls;

  ThreadComposeDraft compose(dom.Document document, String fid) {
    final forms = document
        .querySelectorAll('form[name="FORM"]')
        .where((f) => f.querySelector('textarea[name="atc_content"]') != null);
    if (forms.length != 1) invalid();
    final form = forms.single;
    final action = actionPath(form, '/post.php');
    final controls = const ForumFormParser().defaultEntries(form);
    final fields = Map<String, String>.fromEntries(controls);
    if (fields['fid'] != fid ||
        fields['action'] == 'modify' ||
        fields['action'] == 'reply') invalid();
    for (final key in [
      'fid',
      'verify',
      'special',
      'bonus[best]',
      'bonus[active]',
      'ctype[best]',
      'ctype[active]',
      'p_type'
    ]) {
      if (controls.where((e) => e.key == key).length > 1) invalid();
    }
    final categories = <ThreadComposeCategory>[
      for (final option
          in form.querySelectorAll('select[name="p_type"] option'))
        if ((option.attributes['value'] ?? '').isNotEmpty &&
            !option.attributes.containsKey('disabled'))
          ThreadComposeCategory(
              value: option.attributes['value']!, label: clean(option.text)),
    ];
    final bounty = fields['special'] == '3' ||
        fields.containsKey('bonus[best]') ||
        fields.containsKey('bonus[active]');
    final best = int.tryParse(fields['bonus[best]'] ?? '');
    final helpful = int.tryParse(fields['bonus[active]'] ?? '');
    if (bounty &&
        (fields['special'] != '3' ||
            fields['ctype[best]'] != 'money' ||
            fields['ctype[active]'] != 'money' ||
            best == null ||
            best < 20 ||
            helpful == null ||
            helpful < 10)) invalid();
    final text = clean(form.text);
    int? minimum(String label) => int.tryParse(
        RegExp('$label.*?最少\\s*(\\d+)').firstMatch(text)?.group(1) ?? '');
    return ThreadComposeDraft(
        categories: List.unmodifiable(categories),
        selectedCategory: fields['p_type'],
        bountySupported: bounty,
        controls: List.unmodifiable(controls),
        actionPath: action,
        fid: fid,
        multipart: (form.attributes['enctype'] ?? '').toLowerCase() ==
            'multipart/form-data',
        defaultBestAmount: best,
        defaultHelpfulAmount: helpful,
        minBestAmount: bounty ? minimum('最佳答案') ?? best : null,
        minHelpfulAmount: bounty ? minimum('热心助人') ?? helpful : null,
        bountyCurrency: bounty
            ? clean(form
                    .querySelector(
                        'select[name="ctype[best]"] option[value="money"]')
                    ?.text ??
                'SP币')
            : null);
  }

  ThreadRewardDraft reward(dom.Document document, ThreadRewardAction target) {
    final forms = document
        .querySelectorAll('form')
        .where((f) => f.querySelector('input[name="step"][value="3"]') != null);
    if (forms.length != 1) invalid();
    final form = forms.single;
    if (form.attributes['name'] != 'FORM' ||
        !const {
          '',
          'application/x-www-form-urlencoded'
        }.contains((form.attributes['enctype'] ?? '').toLowerCase())) invalid();
    for (final entry in {
      'type': {'1', '2'},
      'ifmsg': {'0', '1'}
    }.entries) {
      final radios =
          form.querySelectorAll('input[type="radio"][name="${entry.key}"]');
      if (radios.length != 2 ||
          radios.any((r) => r.attributes.containsKey('disabled')) ||
          radios
              .map((r) => r.attributes['value'])
              .toSet()
              .difference(entry.value)
              .isNotEmpty ||
          !entry.value.every(
              (value) => radios.any((r) => r.attributes['value'] == value)))
        invalid();
    }
    final path = actionPath(form, '/job.php');
    final uri = Uri.parse(path);
    if (uri.query != 'action=reward') invalid();
    final controls = const ForumFormParser().defaultEntries(form);
    final fields = Map<String, String>.fromEntries(controls);
    const expected = {'verify', 'type', 'ifmsg', 'page', 'pid', 'tid', 'step'};
    if (fields.keys.toSet().difference(expected).isNotEmpty ||
        expected
            .any((key) => controls.where((e) => e.key == key).length != 1) ||
        fields['verify']!.isEmpty ||
        fields['tid'] != target.tid ||
        fields['pid'] != target.pid ||
        fields['type'] !=
            (target.kind == ThreadRewardKind.bestAnswer ? '1' : '2') ||
        !const {'0', '1'}.contains(fields['ifmsg'])) invalid();
    final rules = form.querySelector('tr.tr2')?.text;
    return ThreadRewardDraft(
        action: target,
        controls: List.unmodifiable(controls),
        actionPath: path,
        nativeRules: rules == null ? null : clean(rules),
        notifyDefault: fields['ifmsg'] == '1');
  }

  bool rewardAcknowledged(dom.Document document, String tid) {
    final text = clean(document.body?.text ?? '');
    if (document.querySelector('table.js-post, form') != null ||
        !text.contains('操作完成') ||
        RegExp(r'失败|错误|权限|认证码|验证码').hasMatch(text)) return false;
    final refreshes = document
        .querySelectorAll('meta[http-equiv]')
        .where((m) => m.attributes['http-equiv']!.toLowerCase() == 'refresh')
        .toList();
    if (refreshes.length != 1) return false;
    final value = RegExp(
            r'^\s*\d+(?:\.\d+)?\s*;\s*url\s*=\s*["\x27]?([^"\x27]+?)["\x27]?\s*$',
            caseSensitive: false)
        .firstMatch(refreshes.single.attributes['content'] ?? '')
        ?.group(1);
    if (value == null || !urls.isForumUrl(value)) return false;
    final uri = Uri.tryParse(urls.absoluteUrl(value));
    return uri != null &&
        uri.path == '/read.php' &&
        uri.userInfo.isEmpty &&
        urls.tidFromUrl(value) == tid;
  }

  String actionPath(dom.Element form, String endpoint) {
    if ((form.attributes['method'] ?? '').toLowerCase() != 'post') invalid();
    final value = form.attributes['action'] ?? '';
    if (value.isEmpty || !urls.isForumUrl(value)) invalid();
    final uri = Uri.tryParse(urls.absoluteUrl(value));
    if (uri == null ||
        uri.path != endpoint ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) invalid();
    final encoding = (form.attributes['enctype'] ?? '').toLowerCase();
    if (!const {'', 'application/x-www-form-urlencoded', 'multipart/form-data'}
        .contains(encoding)) invalid();
    return urls.relativePath(uri.toString());
  }

  String clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();
  Never invalid() => throw const ForumRequestException(
      ForumRequestKind.invalidInput, '论坛表单无效，请刷新后重新打开');
}
