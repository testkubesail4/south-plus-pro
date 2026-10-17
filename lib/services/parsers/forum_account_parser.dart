import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../models/forum_account_models.dart';
import '../forum_request_exception.dart';

const forumPreferenceNames = {
  'tpskin',
  'editor',
  'timedf',
  'd_type',
  'date_f',
  'time_f',
  't_num',
  'p_num',
  'proreceivemail',
  'friendcheck',
  'msggroups[]',
  'banidinfo',
};
const forumProfileNames = {
  'field_1',
  'progender',
  'proyear',
  'promonth',
  'proday',
  'profrom',
  'prohomepage',
  'prohonor',
  'prointroduce',
  'facetype',
  'proicon',
  'httpurl[0]',
  'httpurl[1]',
  'httpurl[2]',
  'uploadurl[1]',
  'uploadurl[2]',
};

class ForumAccountSnapshot {
  ForumAccountSnapshot({
    required this.form,
    required this.action,
    required this.multipart,
    required List<MapEntry<String, String>> controls,
    required Set<String> fileFields,
    required Set<MapEntry<String, String>> fixedControls,
  })  : controls = List.unmodifiable(controls),
        fileFields = Set.unmodifiable(fileFields),
        fixedControls = Set.unmodifiable(fixedControls);
  final ForumAccountForm form;
  final String action;
  final bool multipart;
  final List<MapEntry<String, String>> controls;
  final Set<String> fileFields;
  final Set<MapEntry<String, String>> fixedControls;
}

class ForumAccountParser {
  const ForumAccountParser();

  ForumAccountSnapshot parse(String html, ForumAccountFormKind kind, Uri base) {
    final document = html_parser.parse(html);
    final action =
        kind == ForumAccountFormKind.preferences ? 'bbsset' : 'modify';
    final allowed = kind == ForumAccountFormKind.preferences
        ? forumPreferenceNames
        : forumProfileNames;
    dom.Element? form;
    for (final candidate in document.querySelectorAll('form')) {
      final target = Uri.tryParse(candidate.attributes['action'] ?? '');
      if (target == null) continue;
      final uri = base.resolveUri(target);
      if (uri.scheme != base.scheme ||
          uri.host != base.host ||
          uri.port != base.port ||
          uri.userInfo.isNotEmpty ||
          uri.path != '/profile.php' ||
          uri.hasFragment ||
          uri.query.split('&').where((part) => part.isNotEmpty).length != 1 ||
          uri.queryParametersAll['action']?.length != 1 ||
          uri.queryParameters['action'] != action ||
          (candidate.attributes['method'] ?? '').toLowerCase() != 'post') {
        continue;
      }
      if (form != null) _invalid('论坛返回了多个设置表单，请刷新重试');
      form = candidate;
    }
    if (form == null) {
      final text = document.body?.text ?? '';
      if (forumTextNeedsLogin(text) ||
          document.querySelector('input[name=pwpwd]') != null) {
        throw const ForumRequestException(
            ForumRequestKind.loginRequired, '请先登录');
      }
      if (forumTextIsForbidden(text)) {
        throw const ForumRequestException(
            ForumRequestKind.forbidden, '没有权限修改设置');
      }
      if (forumTextIsRateLimited(text)) {
        throw const ForumRequestException(
            ForumRequestKind.rateLimited, '请求过于频繁');
      }
      _invalid('无法读取完整的论坛设置表单');
    }
    final elements =
        document.querySelectorAll('input, select, textarea').where((element) {
      final owner = element.attributes['form'];
      return owner != null
          ? owner == form!.id && owner.isNotEmpty
          : _ancestor(element, 'form') == form;
    }).toList();
    final lastCheckedRadio = <String, dom.Element>{};
    for (final element in elements) {
      if (element.localName == 'input' &&
          (element.attributes['type'] ?? '').toLowerCase() == 'radio' &&
          element.attributes.containsKey('checked')) {
        lastCheckedRadio[element.attributes['name'] ?? ''] = element;
      }
    }
    final scripts =
        document.querySelectorAll('script').map((e) => e.text).join('\n');
    final controls = <MapEntry<String, String>>[];
    final fixedControls = <MapEntry<String, String>>{};
    final editable = <String, List<dom.Element>>{};
    final fileFields = <String>{};
    for (final element in elements) {
      final name = element.attributes['name'] ?? '';
      if (name.isEmpty || _disabled(element) || _password(element, name))
        continue;
      final type = (element.attributes['type'] ?? 'text').toLowerCase();
      if (element.localName == 'input' &&
          {'button', 'reset', 'submit', 'image'}.contains(type)) continue;
      if (element.localName == 'input' && type == 'file') {
        fileFields.add(name);
        if (name == 'upload' && kind == ForumAccountFormKind.profile) {
          editable.putIfAbsent(name, () => []).add(element);
        }
        continue;
      }
      final readOnly = element.attributes.containsKey('readonly') &&
          (element.localName == 'textarea' ||
              (element.localName == 'input' &&
                  {
                    'text',
                    'search',
                    'url',
                    'tel',
                    'email',
                    'date',
                    'month',
                    'week',
                    'time',
                    'datetime-local',
                    'number'
                  }.contains(type)));
      final canEdit = allowed.contains(name) &&
          (type != 'hidden' || name == 'proicon') &&
          !readOnly;
      if (canEdit) editable.putIfAbsent(name, () => []).add(element);
      final successfulValues =
          type == 'radio' && lastCheckedRadio[name] != element
              ? const <String>[]
              : _values(element);
      for (final value in successfulValues) {
        if (type == 'radio') {
          controls.removeWhere(
              (entry) => entry.key == name && !fixedControls.contains(entry));
        }
        final entry = MapEntry(name, value);
        controls.add(entry);
        if (!canEdit) fixedControls.add(entry);
      }
    }
    if (kind == ForumAccountFormKind.profile) {
      final initialized = RegExp(r'''CkFaceType\(\s*['"]([123])['"]\s*\)''')
          .allMatches(scripts)
          .lastOrNull
          ?.group(1);
      if (initialized != null) {
        controls.removeWhere((e) => e.key == 'facetype');
        if (elements.any((e) =>
            e.attributes['name'] == 'facetype' &&
            e.attributes['value'] == initialized &&
            !_disabled(e))) {
          controls.add(MapEntry('facetype', initialized));
        }
      }
    }
    String value(String name) =>
        controls.where((e) => e.key == name).map((e) => e.value).join();
    if (value('verify').isEmpty ||
        value('step').isEmpty ||
        (kind == ForumAccountFormKind.preferences &&
            !elements.any((e) => e.attributes['name'] == 'banidinfo')) ||
        (kind == ForumAccountFormKind.profile &&
            (!elements.any((e) => e.attributes['name'] == 'prosign') ||
                !elements.any((e) => e.attributes['name'] == 'proemail')))) {
      _invalid('论坛设置表单不完整，未提交任何更改');
    }
    final fields = <ForumAccountField>[];
    for (final entry in editable.entries) {
      final element = entry.value.first;
      final inputType = (element.attributes['type'] ?? 'text').toLowerCase();
      final nativeType = element.localName == 'select'
          ? (element.attributes.containsKey('multiple')
              ? 'multiselect'
              : 'select')
          : element.localName == 'textarea'
              ? 'textarea'
              : inputType;
      final options = <ForumAccountOption>[];
      if (element.localName == 'select') {
        for (final option in element.querySelectorAll('option')) {
          if (_disabledOption(option)) continue;
          options.add(ForumAccountOption(
              value: _optionValue(option), label: _clean(option.text)));
        }
      } else if (nativeType == 'radio' || nativeType == 'checkbox') {
        for (final option in entry.value) {
          options.add(ForumAccountOption(
              value: option.attributes['value'] ?? 'on',
              label: _label(document, option, nameFallback: false)));
        }
      }
      final attributes = element.attributes;
      final description = _fieldHint(element, entry.key);
      final dimension =
          RegExp(r'^(?:httpurl|uploadurl)\[([12])\]$').firstMatch(entry.key);
      final dimensionLabel = dimension?.group(1) == '1' ? '头像宽度' : '头像高度';
      final range = dimension == null
          ? null
          : RegExp(r'(\d+)\s*(?:--|[-–—~至])\s*(\d+)').firstMatch(description);
      final introLimit = entry.key != 'prointroduce'
          ? null
          : RegExp(r'prointroduce\.value\.length\s*>\s*(\d+)')
              .firstMatch(scripts)
              ?.group(1);
      fields.add(ForumAccountField(
        name: entry.key,
        label: _fieldLabels[entry.key] ??
            (dimension != null ? dimensionLabel : _label(document, element)),
        type: entry.key == 'proicon'
            ? 'system-avatar'
            : range != null
                ? 'number'
                : nativeType,
        values: controls
            .where((e) => e.key == entry.key && !fixedControls.contains(e))
            .map((e) => e.value)
            .toList(),
        options: options,
        required: attributes.containsKey('required'),
        maxLength: int.tryParse(attributes['maxlength'] ?? introLimit ?? ''),
        min: num.tryParse(attributes['min'] ?? range?.group(1) ?? ''),
        max: num.tryParse(attributes['max'] ?? range?.group(2) ?? ''),
        pattern: attributes['pattern'],
        accept: attributes['accept'],
        hint: description,
        group: kind == ForumAccountFormKind.preferences
            ? ({'msggroups[]', 'banidinfo'}.contains(entry.key)
                ? 'pm'
                : entry.key == 'friendcheck'
                    ? 'friend'
                    : 'personal')
            : (entry.key == 'field_1'
                ? 'nickname'
                : entry.key == 'prohonor'
                    ? 'signature'
                    : entry.key == 'prointroduce'
                        ? 'introduction'
                        : {
                            'facetype',
                            'proicon',
                            'httpurl[0]',
                            'httpurl[1]',
                            'httpurl[2]',
                            'upload',
                            'uploadurl[1]',
                            'uploadurl[2]'
                          }.contains(entry.key)
                            ? 'avatar'
                            : 'basic'),
      ));
    }
    return ForumAccountSnapshot(
      form: ForumAccountForm(kind: kind, fields: fields),
      action: 'profile.php?action=$action${action == 'modify' ? '&' : ''}',
      multipart: (form.attributes['enctype'] ?? '').toLowerCase() ==
          'multipart/form-data',
      controls: controls,
      fileFields: fileFields,
      fixedControls: fixedControls,
    );
  }

  ForumAccountAvatarPage parseAvatarPage(String response, int page, Uri base) {
    final payload =
        RegExp(r'<ajax>\s*<!\[CDATA\[(.*?)\]\]>\s*</ajax>', dotAll: true)
            .firstMatch(response)
            ?.group(1);
    if (payload == null) _invalid('无法读取论坛头像列表');
    final document = html_parser.parse(payload);
    final options = <ForumAccountOption>[];
    int? nextPage;
    int? previousPage;
    for (final element in document.querySelectorAll('[onclick]')) {
      final onclick = element.attributes['onclick'] ?? '';
      final choice = RegExp(
              r'''^\s*showimage\(\s*(['"])([^'"\\]*)\1\s*,\s*(['"])([^'"\\]*)\3\s*\)\s*;?\s*$''')
          .firstMatch(onclick);
      if (choice != null) {
        final path = choice.group(2)!;
        final value = choice.group(4)!;
        if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.-]*$').hasMatch(value) ||
            path.split('/').contains('..')) continue;
        final image = base.resolve('$path/face/$value');
        if (image.scheme != base.scheme ||
            image.host != base.host ||
            image.port != base.port ||
            image.userInfo.isNotEmpty) continue;
        final img = element.querySelector('img');
        options.add(ForumAccountOption(
            value: value,
            label: img?.attributes['alt']?.trim().isNotEmpty == true
                ? img!.attributes['alt']!
                : value,
            imageUrl: image.toString()));
      }
      final navigation = RegExp(
              r'''^\s*sendmsg\(\s*(['"])pw_ajax\.php\1\s*,\s*(['"])action=showface&page=(\d+)\2\s*,\s*(['"])[a-zA-Z0-9_-]+\4\s*\)\s*;?\s*$''')
          .firstMatch(onclick);
      final linked = int.tryParse(navigation?.group(3) ?? '');
      if (linked == page + 1) nextPage = linked;
      if (linked == page - 1 && linked! > 0) previousPage = linked;
    }
    if (options.isEmpty) _invalid('论坛头像列表为空或格式已更改');
    return ForumAccountAvatarPage(
        page: page,
        options: options,
        nextPage: nextPage,
        previousPage: previousPage);
  }

  String parseUploadedAvatar(String response, Uri base) {
    final document = html_parser.parse(response);
    final scripts = document.querySelectorAll('script');
    final callbacks = scripts
        .where((script) => RegExp(r'\bfacepath\s*\(').hasMatch(script.text))
        .toList();
    final source = scripts.isEmpty
        ? response
        : callbacks.length == 1
            ? callbacks.single.text
            : '';
    // Native responses include unrelated common-header scripts; inspect one isolated literal callback.
    final failure = RegExp(
            r'''^\s*(?:(?:window\.)?parent\.)?facepath\(\s*(['"])\1\s*,\s*(['"])\2\s*,\s*(['"])([^'"\\\r\n]+)\3\s*,\s*(['"])\5\s*,\s*(['"])\6\s*\)\s*;?\s*$''')
        .firstMatch(source);
    final error = failure?.group(4);
    if (error != null &&
        error.startsWith('上传附件失败') &&
        error.length <= 160 &&
        !RegExp(r'[<>\x00-\x1f\x7f]').hasMatch(error)) {
      throw ForumAccountValidationException('upload', error);
    }
    // Accept only the native callback's literal arguments, never execute returned JavaScript.
    final callback = RegExp(
            r'''^\s*(?:(?:window\.)?parent\.)?facepath\(\s*(['"])([^'"\\\r\n]+)\1\s*,\s*(['"])([^'"\\\r\n]+)\3\s*,\s*(['"])success\5(?:\s*,\s*(?:\d+|['"]\d+['"]|undefined|false)\s*,\s*(?:\d+|['"]\d+['"]|undefined|false))?\s*\)\s*;?\s*$''')
        .firstMatch(source);
    if (callback == null) _invalid('论坛未确认头像上传成功，请刷新后重试');
    final iconUrl = Uri.tryParse(callback.group(2)!);
    final location = iconUrl == null ? null : base.resolveUri(iconUrl);
    if (location == null ||
        location.scheme != base.scheme ||
        location.host != base.host ||
        location.port != base.port ||
        location.userInfo.isNotEmpty ||
        location.hasQuery ||
        location.hasFragment ||
        !location.path.endsWith('/') ||
        iconUrl!.pathSegments
            .any((e) => e == '..' || e.contains('\\') || e.contains('/'))) {
      _invalid('论坛返回了不安全的头像地址');
    }
    final value = callback.group(4)!;
    final uri = Uri.tryParse(value);
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_./-]*$').hasMatch(value) ||
        uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasQuery ||
        uri.hasFragment ||
        value.startsWith('/') ||
        value.contains('\\') ||
        value.contains(RegExp(r'[\x00-\x20]')) ||
        uri.pathSegments.any((e) => e.isEmpty || e == '.' || e == '..')) {
      _invalid('论坛返回了无效的头像标识');
    }
    return value;
  }

  List<String> _values(dom.Element element) {
    if (element.localName == 'textarea') return [element.text];
    if (element.localName == 'select') {
      final options = element.querySelectorAll('option');
      var selected =
          options.where((e) => e.attributes.containsKey('selected')).toList();
      final multiple = element.attributes.containsKey('multiple');
      if (!multiple) {
        if (selected.isNotEmpty) {
          selected = [selected.last];
        } else if (int.tryParse(element.attributes['size'] ?? '1') == 1) {
          selected = options.where((e) => !_disabledOption(e)).take(1).toList();
        }
      }
      return selected
          .where((e) => !_disabledOption(e))
          .map(_optionValue)
          .toList();
    }
    final type = (element.attributes['type'] ?? 'text').toLowerCase();
    if ((type == 'checkbox' || type == 'radio') &&
        !element.attributes.containsKey('checked')) return [];
    return [
      element.attributes['value'] ??
          (type == 'checkbox' || type == 'radio' ? 'on' : '')
    ];
  }

  bool _password(dom.Element element, String name) =>
      (element.attributes['type'] ?? '').toLowerCase() == 'password' ||
      {'oldpwd', 'propwd', 'check_pwd'}.contains(name.toLowerCase());

  bool _disabled(dom.Element element) {
    if (element.attributes.containsKey('disabled')) return true;
    for (var parent = element.parent; parent != null; parent = parent.parent) {
      if (parent.localName != 'fieldset' ||
          !parent.attributes.containsKey('disabled')) continue;
      final legends = parent.children.where((e) => e.localName == 'legend');
      if (legends.isNotEmpty && _inside(element, legends.first)) continue;
      return true;
    }
    return false;
  }

  bool _inside(dom.Element element, dom.Element parent) {
    for (dom.Element? current = element;
        current != null;
        current = current.parent) {
      if (current == parent) return true;
    }
    return false;
  }

  bool _disabledOption(dom.Element option) =>
      option.attributes.containsKey('disabled') ||
      (option.parent?.localName == 'optgroup' &&
          option.parent!.attributes.containsKey('disabled'));

  String _optionValue(dom.Element option) =>
      option.attributes['value'] ?? _clean(option.text);

  static const _fieldLabels = {
    'tpskin': '原站网页风格',
    'editor': '原站默认编辑器',
    'timedf': '时区',
    'd_type': '日期格式',
    'date_f': '自定义日期格式',
    'time_f': '时间格式',
    't_num': '每页主题数',
    'p_num': '每页文章数',
    'proreceivemail': '接收论坛邮件',
    'friendcheck': '好友验证',
    'banidinfo': '私信黑名单',
    'facetype': '头像类型',
    'proicon': '系统头像',
    'httpurl[0]': '头像链接',
    'upload': '头像文件',
  };

  String _fieldHint(dom.Element element, String name) {
    final question = _ancestor(element, 'tr')?.querySelector('td, th');
    if (name == 'banidinfo') return _clean(question?.text ?? '');
    if (name == 'date_f') return _clean(question?.text ?? '');
    if (name == 'editor') return '设置原站发帖时默认使用的编辑器。';
    if (name == 'tpskin') return '设置原站网页使用的风格。';
    if (name == 'friendcheck') return '设置其他用户添加您为好友时的验证方式。';
    if (name == 'proreceivemail') return '设置是否接收论坛邮件，不会修改邮箱地址。';
    if (name == 'd_type') return '使用论坛默认日期格式，或选择自定义格式。';
    if (name == 'time_f') return '24 小时制或 12 小时制。';
    if (name == 't_num' || name == 'p_num') return '设置为 0 时使用论坛默认。';
    if (name == 'facetype' || name == 'proicon') return '';
    final text = StringBuffer();
    final siblings = element.parentNode?.nodes ?? const <dom.Node>[];
    final type = (element.attributes['type'] ?? '').toLowerCase();
    for (final next in {'radio', 'checkbox'}.contains(type)
        ? const <dom.Node>[]
        : siblings.skip(siblings.indexOf(element) + 1)) {
      if (next is dom.Element &&
          (next.localName == 'br' ||
              {'input', 'select', 'textarea', 'button', 'a'}
                  .contains(next.localName) ||
              next.querySelector('input, select, textarea, button') != null))
        break;
      text.write(next.text);
    }
    final nearby = _clean(text.toString());
    if (nearby.isNotEmpty) return nearby;
    if (name == 'upload') return '';
    if (question == null || _inside(element, question)) return '';
    final lines = <String>[];
    var line = StringBuffer();
    for (final node in question.nodes) {
      if (node is dom.Element && node.localName == 'br') {
        lines.add(_clean(line.toString()));
        line = StringBuffer();
      } else {
        line.write(node.text);
      }
    }
    lines.add(_clean(line.toString()));
    return lines.skip(1).where((line) => line.isNotEmpty).join(' ');
  }

  String _label(dom.Document document, dom.Element element,
      {bool nameFallback = true}) {
    if (nameFallback) {
      final question = _ancestor(element, 'tr')?.querySelector('td, th');
      if (question != null &&
          !_inside(element, question) &&
          _clean(question.text).isNotEmpty) {
        return _clean(question.text);
      }
      final fieldset = _ancestor(element, 'fieldset');
      final legend = fieldset?.children
          .where((child) => child.localName == 'legend')
          .firstOrNull;
      if (legend != null &&
          _clean(legend.text).isNotEmpty &&
          fieldset!
              .querySelectorAll('input[name], select[name], textarea[name]')
              .every((control) =>
                  control.attributes['name'] == element.attributes['name'])) {
        return _clean(legend.text);
      }
    }
    if (element.id.isNotEmpty) {
      for (final label in document.querySelectorAll('label[for]')) {
        if (label.attributes['for'] == element.id) return _clean(label.text);
      }
    }
    final enclosing = _ancestor(element, 'label');
    if (enclosing != null) return _clean(enclosing.text);
    if (!nameFallback) {
      final text = StringBuffer();
      final siblings = element.parentNode?.nodes ?? const <dom.Node>[];
      final index = siblings.indexOf(element);
      for (final next in siblings.skip(index + 1)) {
        if (next is dom.Element &&
            (next.localName == 'input' || next.querySelector('input') != null))
          break;
        text.write(next.text);
      }
      if (_clean(text.toString()).isNotEmpty) return _clean(text.toString());
    }
    final cell = _ancestor(element, 'tr')?.querySelector('td, th');
    if (_clean(cell?.text ?? '').isNotEmpty) return _clean(cell!.text);
    final siblings = element.parentNode?.nodes ?? const <dom.Node>[];
    for (final previous
        in siblings.take(siblings.indexOf(element)).toList().reversed) {
      final text = _clean(previous.text ?? '');
      if (text.isNotEmpty) return text;
    }
    return element.attributes['name'] ?? '';
  }

  dom.Element? _ancestor(dom.Element element, String tag) {
    for (dom.Element? parent = element;
        parent != null;
        parent = parent.parent) {
      if (parent.localName == tag) return parent;
    }
    return null;
  }

  String _clean(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

  Never _invalid(String message) =>
      throw ForumRequestException(ForumRequestKind.server, message);
}
