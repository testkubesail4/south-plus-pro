import 'dart:typed_data';

import 'package:html/parser.dart' as html_parser;

import '../models/forum_account_models.dart';
import 'forum_client.dart';
import 'forum_request_exception.dart';
import 'native_date_validator.dart';
import 'parsers/forum_account_parser.dart';

class ForumAccountService {
  ForumAccountService({
    required ForumClient Function() client,
    required int Function() sessionEpoch,
    required bool Function() isLoggedIn,
  })  : _client = client,
        _sessionEpoch = sessionEpoch,
        _isLoggedIn = isLoggedIn;

  final ForumClient Function() _client;
  final int Function() _sessionEpoch;
  final bool Function() _isLoggedIn;
  static const _birthdayNames = ['proyear', 'promonth', 'proday'];
  final _parser = const ForumAccountParser();
  final _loaded = Expando<_AccountSession>();
  bool _saving = false;
  _AccountSession? _avatarSession;
  final _avatarChoices = <String, int>{};
  final _avatarPages = <int>{1};

  Future<ForumAccountAvatarPage> fetchAccountSystemAvatars(
      {int page = 1}) async {
    final session = _captureSession();
    if (page < 1 || !_avatarPages.contains(page)) {
      _invalid('请通过论坛头像列表翻页');
    }
    return _readAvatarPage(page, session);
  }

  Future<ForumAccountAvatarPage> _readAvatarPage(
      int page, _AccountSession session) async {
    _checkSession(session);
    final response = await session.client.getForm(
        'pw_ajax.php?action=showface${page == 1 ? '' : '&page=$page'}',
        requireCurrentSession: () => _checkSession(session));
    _checkSession(session);
    final result =
        _parser.parseAvatarPage(response, page, session.client.baseUri);
    for (final option in result.options) {
      _avatarChoices[option.value] = page;
    }
    if (result.nextPage != null) _avatarPages.add(result.nextPage!);
    if (result.previousPage != null) _avatarPages.add(result.previousPage!);
    return result;
  }

  Future<ForumAccountForm> fetchForumPreferences() =>
      _fetch(ForumAccountFormKind.preferences);

  Future<ForumAccountForm> fetchAccountProfileForm() =>
      _fetch(ForumAccountFormKind.profile);

  Future<ForumAccountForm> _fetch(ForumAccountFormKind kind) async {
    final session = _captureSession();
    final snapshot = await _read(kind, session);
    _loaded[snapshot.form] = session;
    return snapshot.form;
  }

  Future<void> saveForumPreferences(
    ForumAccountForm form,
    Map<String, List<String>> changes,
  ) =>
      _save(form, ForumAccountFormKind.preferences, changes);

  Future<void> saveAccountProfileForm(
    ForumAccountForm form,
    Map<String, List<String>> changes, {
    ForumAccountUpload? avatar,
  }) =>
      _save(form, ForumAccountFormKind.profile, changes, avatar: avatar);

  Future<void> _save(
    ForumAccountForm form,
    ForumAccountFormKind kind,
    Map<String, List<String>> changes, {
    ForumAccountUpload? avatar,
  }) async {
    final session = _loaded[form];
    if (session == null || form.kind != kind) {
      _invalid('请重新打开设置页面后再保存');
    }
    _checkSession(session);
    if (_saving) _invalid('正在保存，请稍候');
    final patch = {
      for (final entry in changes.entries)
        entry.key: List<String>.of(entry.value)
    };
    // Edited birthdays claim the full tuple; untouched ones stay fresh native controls.
    if (kind == ForumAccountFormKind.profile &&
        _birthdayNames.any(patch.containsKey) &&
        _birthdayNames.every((name) => form.field(name)?.type == 'select')) {
      for (final name in _birthdayNames) {
        patch.putIfAbsent(
            name, () => List<String>.of(form.field(name)!.values));
      }
    }
    _validate(form, patch, avatar);
    if (patch.isEmpty && avatar == null) return;
    _saving = true;
    try {
      // Read again so unrelated settings and sensitive fields keep their latest values.
      var fresh = await _read(kind, session);
      _validate(fresh.form, patch, avatar);
      _checkConflicts(form, fresh.form, patch);
      if (patch.containsKey('proicon') &&
          !_same(form.field('proicon')!.values, patch['proicon']!)) {
        final selected = patch['proicon']!.single;
        final page = _avatarChoices[selected];
        if (page == null) _invalidField('proicon', '请从论坛头像列表选择图片');
        final observed = await _readAvatarPage(page, session);
        if (!observed.options.any((o) => o.value == selected)) {
          _invalidField('proicon', '头像列表已更改，请重新选择');
        }
      }
      String? uploadedIcon;
      if (avatar != null) {
        if (!fresh.multipart || !fresh.fileFields.contains('upload')) {
          _invalidField('upload', '论坛表单未提供文件上传');
        }
        final limits =
            fresh.controls.where((e) => e.key.toUpperCase() == 'MAX_FILE_SIZE');
        for (final limit in limits) {
          final bytes = int.tryParse(limit.value);
          if (bytes != null && bytes > 0 && avatar.bytes.length > bytes) {
            _invalidField('upload', '头像文件超过论坛允许大小');
          }
        }
        final response = await session.client.postForm(
          'profile.php?action=ajaxface',
          _merge(fresh, patch),
          multipart: true,
          files: _files(fresh, avatar),
          requireCurrentSession: () => _checkSession(session),
        );
        _checkSession(session);
        uploadedIcon =
            _parser.parseUploadedAvatar(response, session.client.baseUri);
        fresh = await _read(kind, session);
        _validate(fresh.form, patch, avatar);
        _checkConflicts(form, fresh.form, patch);
      }
      final fields = _merge(fresh, patch);
      if (uploadedIcon != null) {
        fields.removeWhere((e) => e.key == 'proicon');
        fields.add(MapEntry('proicon', uploadedIcon));
      }
      _checkSession(session);
      final response = await session.client.postForm(
        fresh.action,
        fields,
        multipart: fresh.multipart,
        files: fresh.multipart ? _files(fresh, null) : const [],
        requireCurrentSession: () => _checkSession(session),
      );
      _checkSession(session);
      if (!_checkSuccess(response)) {
        final confirmed = await _read(kind, session);
        for (final entry in patch.entries) {
          final field = confirmed.form.field(entry.key);
          final actual = List<String>.of(field?.values ?? const []);
          final expected = List<String>.of(entry.value);
          if (field?.type == 'checkbox' || field?.type == 'multiselect') {
            actual.sort();
            expected.sort();
          }
          if (field == null || !_same(expected, actual)) _unconfirmed();
        }
        if (uploadedIcon != null &&
            confirmed.form.field('proicon')?.value != uploadedIcon) {
          _unconfirmed();
        }
      }
      // A successful submit consumes the form capability; callers reload before editing again.
      _loaded[form] = null;
    } finally {
      _saving = false;
    }
  }

  Future<ForumAccountSnapshot> _read(
      ForumAccountFormKind kind, _AccountSession session) async {
    _checkSession(session);
    final response = await session.client.getForm(
        kind == ForumAccountFormKind.preferences
            ? 'profile.php?action-bbsset-info_type-msg.html'
            : 'profile.php?action-modify.html',
        requireCurrentSession: () => _checkSession(session));
    _checkSession(session);
    return _parser.parse(response, kind, session.client.baseUri);
  }

  _AccountSession _captureSession() {
    final session = _AccountSession(_client(), _sessionEpoch());
    _checkSession(session);
    if (_avatarSession == null ||
        !identical(_avatarSession!.client, session.client) ||
        _avatarSession!.epoch != session.epoch) {
      _avatarSession = session;
      _avatarChoices.clear();
      _avatarPages
        ..clear()
        ..add(1);
    }
    return session;
  }

  List<MapEntry<String, String>> _merge(
      ForumAccountSnapshot fresh, Map<String, List<String>> patch) {
    final fields = fresh.controls
        .where(
            (e) => !patch.containsKey(e.key) || fresh.fixedControls.contains(e))
        .toList();
    for (final entry in patch.entries) {
      fields.addAll(entry.value.map((value) => MapEntry(entry.key, value)));
    }
    return fields;
  }

  List<ForumFormFile> _files(
          ForumAccountSnapshot fresh, ForumAccountUpload? avatar) =>
      fresh.fileFields.map((name) {
        final selected = name == 'upload' ? avatar : null;
        return ForumFormFile(
            name: name,
            fileName: selected?.fileName ?? '',
            mimeType: selected?.mimeType ?? 'application/octet-stream',
            bytes: selected?.bytes ?? Uint8List(0));
      }).toList();

  void _checkConflicts(ForumAccountForm previous, ForumAccountForm current,
      Map<String, List<String>> patch) {
    for (final name in patch.keys) {
      if (!_same(previous.field(name)!.values, current.field(name)!.values) &&
          !_same(patch[name]!, current.field(name)!.values)) {
        _invalidField(name, '设置已在其他页面更改，请刷新后重试');
      }
    }
  }

  void _checkSession(_AccountSession session) {
    if (!_isLoggedIn() ||
        !identical(session.client, _client()) ||
        session.epoch != _sessionEpoch()) {
      throw const ForumRequestException(
          ForumRequestKind.loginRequired, '登录状态已变更，请重新打开设置');
    }
  }

  void _validate(ForumAccountForm form, Map<String, List<String>> patch,
      ForumAccountUpload? avatar) {
    final birthday = [for (final name in _birthdayNames) form.field(name)];
    if (form.kind == ForumAccountFormKind.profile &&
        _birthdayNames.any(patch.containsKey) &&
        birthday.every((field) =>
            field != null &&
            field.type == 'select' &&
            field.options.isNotEmpty &&
            field.options.every((option) =>
                option.value.isEmpty ||
                RegExp(r'^[0-9]+$').hasMatch(option.value)))) {
      String selected(String name) =>
          (patch[name] ?? form.field(name)!.values).firstOrNull ?? '';
      final error = validateNativeDate(
        year: selected('proyear'),
        month: selected('promonth'),
        day: selected('proday'),
        yearOptions: birthday[0]!.options.map((option) => option.value),
        monthOptions: birthday[1]!.options.map((option) => option.value),
        dayOptions: birthday[2]!.options.map((option) => option.value),
      );
      if (error != null) _invalidField('proyear', error);
    }
    for (final entry in patch.entries) {
      final field = form.field(entry.key);
      if (field == null || field.type == 'file') _invalid('此资料项目不能修改');
      final values = entry.value;
      final multiple = field.type == 'checkbox' || field.type == 'multiselect';
      if ((!multiple && values.length != 1) ||
          (multiple &&
              values.any((value) =>
                  values.where((v) => v == value).length >
                  field.options
                      .where((option) => option.value == value)
                      .length))) {
        _invalidField(field.name, '${field.label}的值无效');
      }
      if (field.required &&
          (values.isEmpty || values.every((v) => v.isEmpty))) {
        _invalidField(field.name, '${field.label}不能为空');
      }
      for (final value in values) {
        if (value.contains('\u0000'))
          _invalidField(field.name, '${field.label}包含无效字符');
        if (field.maxLength != null &&
            field.maxLength! >= 0 &&
            value.length > field.maxLength!) {
          _invalidField(field.name, '${field.label}超过论坛长度限制');
        }
        if (field.options.isNotEmpty &&
            !field.options.any((o) => o.value == value)) {
          _invalidField(field.name, '${field.label}不是论坛提供的选项');
        }
        if ({'select', 'multiselect', 'radio', 'checkbox'}
                .contains(field.type) &&
            field.options.isEmpty &&
            values.isNotEmpty) {
          _invalidField(field.name, '${field.label}没有可用选项');
        }
        if (value.isNotEmpty &&
            (field.min != null ||
                field.max != null ||
                field.type == 'number')) {
          final number = num.tryParse(value);
          if (number == null ||
              !number.isFinite ||
              (field.min != null && number < field.min!) ||
              (field.max != null && number > field.max!)) {
            _invalidField(field.name, '${field.label}超出论坛允许范围');
          }
        }
        if (field.pattern != null && value.isNotEmpty) {
          late final RegExp pattern;
          try {
            pattern = RegExp('^(?:${field.pattern})\$');
          } on FormatException {
            _invalid('论坛输入规则暂不受支持，请使用原站修改');
          }
          if (!pattern.hasMatch(value))
            _invalidField(field.name, '${field.label}格式不正确');
        }
      }
      if (field.type == 'system-avatar' &&
          !_same(field.values, values) &&
          !_avatarChoices.containsKey(values.single)) {
        _invalidField(field.name, '请从论坛头像列表选择图片');
      }
      if (entry.key == 'banidinfo' &&
          values.single.trim().isNotEmpty &&
          !RegExp(r'^\s*[1-9]\d*\s*(?:,\s*[1-9]\d*\s*)*$')
              .hasMatch(values.single)) {
        _invalidField(entry.key, '私信黑名单请填写逗号分隔的数字 UID，而不是昵称');
      }
      if (entry.key == 'prohomepage' || entry.key == 'httpurl[0]') {
        final value = values.single.trim();
        final uri = Uri.tryParse(value);
        if (value.isNotEmpty &&
            (uri == null ||
                !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
                uri.host.isEmpty ||
                uri.userInfo.isNotEmpty)) {
          _invalidField(entry.key, '请输入有效的 http 或 https 链接');
        }
      }
    }
    final avatarChanged = avatar != null ||
        patch.keys.any((name) => {
              'facetype',
              'proicon',
              'httpurl[0]',
              'httpurl[1]',
              'httpurl[2]',
              'uploadurl[1]',
              'uploadurl[2]'
            }.contains(name));
    String value(String name) =>
        (patch[name] ?? form.field(name)?.values ?? const ['']).firstOrNull ??
        '';
    if (form.kind == ForumAccountFormKind.profile && avatarChanged) {
      final mode = value('facetype');
      if (mode == '2') {
        if (value('httpurl[0]').trim().isEmpty)
          _invalidField('httpurl[0]', '请输入头像链接');
        _validateDimension(form, 'httpurl[1]', value('httpurl[1]'),
            required: true);
        _validateDimension(form, 'httpurl[2]', value('httpurl[2]'),
            required: false);
      } else if (mode == '3') {
        _validateDimension(form, 'uploadurl[1]', value('uploadurl[1]'),
            required: true);
        _validateDimension(form, 'uploadurl[2]', value('uploadurl[2]'),
            required: false);
        if (form.field('facetype')?.value != '3' && avatar == null) {
          _invalidField('upload', '请选择要上传的头像');
        }
      }
      if (avatar != null && mode != '3')
        _invalidField('facetype', '请切换到头像上传模式');
      if (patch.containsKey('proicon') && mode != '1') {
        _invalidField('facetype', '请切换到系统头像模式');
      }
    }
    if (avatar != null) {
      final upload = form.field('upload');
      if (upload == null ||
          upload.type != 'file' ||
          avatar.bytes.isEmpty ||
          avatar.fileName.isEmpty ||
          avatar.fileName.contains(RegExp(r'[\x00-\x1f/\\]')) ||
          _rasterMime(avatar.bytes) != avatar.mimeType.toLowerCase()) {
        _invalidField('upload', '请选择有效的头像图片');
      }
      final accept = upload.accept;
      if (accept != null && accept.trim().isNotEmpty) {
        final accepted = accept.split(',').map((e) => e.trim().toLowerCase());
        if (!accepted.any((e) =>
            e == 'image/*' ||
            e == avatar.mimeType.toLowerCase() ||
            (e.startsWith('.') && avatar.fileName.toLowerCase().endsWith(e)))) {
          _invalidField('upload', '头像格式不符合论坛要求');
        }
      }
    }
  }

  void _validateDimension(ForumAccountForm form, String name, String value,
      {required bool required}) {
    if (!required && value.isEmpty) return;
    final field = form.field(name);
    final number = int.tryParse(value);
    if (field?.min == null || field?.max == null) {
      _invalidField(name, '无法识别论坛头像尺寸限制，请刷新后重试');
    }
    if (!RegExp(r'^[1-9]\d*$').hasMatch(value) ||
        number == null ||
        number < field!.min! ||
        number > field.max!) {
      _invalidField(name, '头像尺寸必须是 ${field!.min}–${field.max} 之间的整数');
    }
  }

  String? _rasterMime(Uint8List bytes) {
    bool prefix(List<int> value, [int offset = 0]) {
      if (bytes.length < offset + value.length) return false;
      for (var i = 0; i < value.length; i++) {
        if (bytes[offset + i] != value[i]) return false;
      }
      return true;
    }

    if (prefix([137, 80, 78, 71, 13, 10, 26, 10])) return 'image/png';
    if (prefix([255, 216, 255])) return 'image/jpeg';
    if (prefix([71, 73, 70, 56, 55, 97]) || prefix([71, 73, 70, 56, 57, 97]))
      return 'image/gif';
    if (prefix([82, 73, 70, 70]) && prefix([87, 69, 66, 80], 8))
      return 'image/webp';
    if (prefix([66, 77])) return 'image/bmp';
    return null;
  }

  bool _checkSuccess(String response) {
    final document = html_parser.parse(response);
    for (final element
        in document.querySelectorAll('script, style, textarea, input')) {
      element.remove();
    }
    final text = document.body?.text ?? '';
    if (forumTextNeedsLogin(text)) {
      throw const ForumRequestException(
          ForumRequestKind.loginRequired, '请重新登录后保存');
    }
    if (forumTextIsForbidden(text)) {
      throw const ForumRequestException(ForumRequestKind.forbidden, '没有权限修改设置');
    }
    if (forumTextIsRateLimited(text)) {
      throw const ForumRequestException(ForumRequestKind.rateLimited, '请求过于频繁');
    }
    if (RegExp(r'认证码|驗證碼|验证码|错误|錯誤|失败|失敗|不能|不允许|不允許|不合法|非法|不足')
        .hasMatch(text)) {
      _unconfirmed();
    }
    return document.querySelector('form') == null &&
        RegExp(r'操作完成|修改成功|修改完成|更新成功|设置成功|設置成功').hasMatch(text);
  }

  Never _unconfirmed() => throw const ForumRequestException(
      ForumRequestKind.server, '论坛未确认保存成功，请刷新资料确认后重试');

  bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Never _invalidField(String field, String message) =>
      throw ForumAccountValidationException(field, message);

  Never _invalid(String message) =>
      throw ForumRequestException(ForumRequestKind.invalidInput, message);
}

class _AccountSession {
  const _AccountSession(this.client, this.epoch);
  final ForumClient client;
  final int epoch;
}
