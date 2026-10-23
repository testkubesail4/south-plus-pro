import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../models/forum_account_models.dart';
import '../../services/forum_repository.dart';
import '../../services/loading_preferences.dart';
import '../../theme/app_theme.dart';
import '../common/app_switcher.dart';
import '../common/async_state_view.dart';
import '../common/cached_forum_image.dart';
import '../common/grouped_list.dart';
import '../common/more_pages.dart';
import '../common/native_form_fields.dart';
import '../common/page_end.dart';
import 'account_birthday_field.dart';
import 'avatar_crop.dart';
import 'account_screen.dart';

/// Opens the system file chooser for a picture; null when cancelled.
typedef AvatarPicker = Future<ForumAccountUpload?> Function();

const _imageTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
};

const _readLimit = 20 * 1024 * 1024;

String _extension(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// An accept entry (MIME type or extension) in plain words; others unchanged.
String acceptLabel(String entry) {
  final e = entry.trim().toLowerCase();
  if (e == 'image/*') return '图片';
  final ext = e.startsWith('.')
      ? e.substring(1)
      : _imageTypes.entries
          .where((t) => t.value == e)
          .map((t) => t.key)
          .firstOrNull;
  return ext != null && _imageTypes.containsKey(ext)
      ? (ext == 'jpeg' ? 'JPG' : ext.toUpperCase())
      : entry.trim();
}

/// The system avatar row's value: the forum's own sentinel (an empty value or
/// a `none` image) reads as unset, and a file name is never shown.
String systemAvatarValue(ForumAccountField? field, String value) {
  final v = value.trim();
  final name = v.split('/').last;
  final dot = name.lastIndexOf('.');
  final stem = (dot < 0 ? name : name.substring(0, dot)).toLowerCase();
  if (v.isEmpty || stem == 'none') return '未选择';
  final label = field?.options
      .where((o) => o.value == value && o.label.trim().isNotEmpty)
      .map((o) => o.label.trim())
      .firstOrNull;
  return label ?? '已选择';
}

Future<ForumAccountUpload?> pickAvatarFile() async {
  final file = await openFile(acceptedTypeGroups: [
    XTypeGroup(
      label: '图片',
      extensions: _imageTypes.keys.toList(),
      mimeTypes: _imageTypes.values.toSet().toList(),
      uniformTypeIdentifiers: const ['public.image'],
    ),
  ]);
  if (file == null) return null;
  // Memory guard before reading; the forum states no limit of its own.
  if (await file.length() > _readLimit) {
    throw const FormatException('图片太大');
  }
  return ForumAccountUpload(
    bytes: await file.readAsBytes(),
    fileName: file.name,
    mimeType: _imageTypes[_extension(file.name)] ??
        file.mimeType ??
        'application/octet-stream',
  );
}

/// Why [upload] cannot be sent, judged by the forum's own limits; null when fine.
String? avatarUploadProblem(
    ForumAccountUpload upload, ForumAccountField field) {
  if (upload.bytes.isEmpty) return '这个文件是空的';
  final extension = _extension(upload.fileName);
  final accept = field.accept?.trim() ?? '';
  final accepted = accept.isEmpty
      ? null
      : accept.toLowerCase().split(',').map((e) => e.trim()).toList();
  final typeOk = accepted == null
      ? _imageTypes.containsKey(extension) &&
          upload.mimeType.startsWith('image/')
      : accepted.any((e) =>
          e == 'image/*' && upload.mimeType.startsWith('image/') ||
          e == upload.mimeType.toLowerCase() ||
          e == '.$extension');
  if (!typeOk) {
    return accepted == null
        ? '请选择 jpg、png、gif 或 webp 图片'
        : '论坛只接受 ${accepted.join('、')}';
  }
  // The forum states its size limit in plain text beside the field.
  final limit = RegExp(r'(\d+(?:\.\d+)?)\s*(KB|K|MB|M)\b', caseSensitive: false)
      .firstMatch(field.hint);
  if (limit != null) {
    final unit = limit.group(2)!.toLowerCase();
    final bytes = double.parse(limit.group(1)!) *
        (unit.startsWith('m') ? 1024 * 1024 : 1024);
    if (upload.bytes.length > bytes) return '图片超过论坛限制 ${limit.group(0)}';
  }
  return null;
}

String _size(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).ceil()} KB'
    : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

/// 编辑资料: nickname, basic details, signature, introduction and avatar,
/// as the forum's own profile form defines them.
class AccountProfileEditScreen extends StatefulWidget {
  const AccountProfileEditScreen({
    super.key,
    required this.repository,
    this.avatarPicker = pickAvatarFile,
    this.avatarCropper = cropAvatar,
  });

  final ForumRepository repository;
  final AvatarPicker avatarPicker;
  final AvatarCropper avatarCropper;

  @override
  State<AccountProfileEditScreen> createState() =>
      _AccountProfileEditScreenState();
}

class _AccountProfileEditScreenState extends State<AccountProfileEditScreen> {
  late final String? _openedAvatar =
      widget.repository.accountIdentity.value?.avatarUrl;

  /// A new picture keeps its old address, so the cached one must go.
  Future<void> _refreshAvatar() async {
    final urls = <String>{
      if (_openedAvatar != null) _openedAvatar,
      if (widget.repository.accountIdentity.value?.avatarUrl != null)
        widget.repository.accountIdentity.value!.avatarUrl!,
    };
    for (final url in urls) {
      try {
        await CachedNetworkImage.evictFromCache(url,
            cacheManager: ForumImageCache.manager);
      } catch (_) {
        // A stale picture is cosmetic; the next cache expiry replaces it.
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return NativeFormPage(
      title: '编辑资料',
      sessionEpoch: widget.repository.sessionEpoch,
      load: widget.repository.fetchAccountProfileForm,
      save: (form, changes, upload) => widget.repository
          .saveAccountProfileForm(form, changes, avatar: upload),
      onSaved: _refreshAvatar,
      activeField: avatarFieldActive,
      fieldCheck: birthdayFieldCheck,
      builder: (context, c) {
        final birthday = hasNativeBirthday(c.form);
        List<String> names(String group) => [
              for (final f in c.form.fields)
                if (f.group == group) f.name,
            ];
        Widget group(String label, String key) {
          final fields = names(key);
          if (fields.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xl),
            child: AppGroup(
              label: label,
              dividerIndent: AppSpace.lg,
              children: [
                for (final name in fields)
                  // The three birthday selects read as one date, in the
                  // year's place; without all three, one row each.
                  if (birthday && name == birthdayYear)
                    NativeBirthdayRow(controller: c)
                  else if (!birthday || !birthdayFields.contains(name))
                    NativeFieldRow(controller: c, name: name),
              ],
            ),
          );
        }

        final known = {
          'avatar',
          'nickname',
          'basic',
          'signature',
          'introduction'
        };
        return [
          _AvatarSection(
            controller: c,
            repository: widget.repository,
            picker: widget.avatarPicker,
            cropper: widget.avatarCropper,
            avatarUrl: widget.repository.accountIdentity.value?.avatarUrl,
          ),
          const SizedBox(height: AppSpace.xl),
          group('昵称', 'nickname'),
          group('基本资料', 'basic'),
          group('个人签名', 'signature'),
          group('个人简介', 'introduction'),
          // A group the forum adds later still shows up.
          Builder(builder: (context) {
            final other = [
              for (final f in c.form.fields)
                if (!known.contains(f.group)) f.name,
            ];
            return other.isEmpty
                ? const SizedBox.shrink()
                : AppGroup(
                    label: '其他',
                    dividerIndent: AppSpace.lg,
                    children: [
                      for (final n in other)
                        NativeFieldRow(controller: c, name: n),
                    ],
                  );
          }),
        ];
      },
    );
  }
}

enum _AvatarMode { system, link, upload }

/// The avatar mode a `facetype` value stands for: the option's own words,
/// then the forum's fixed numbers 1/2/3.
_AvatarMode? _modeOf(ForumAccountForm form, String value) {
  if (value.isEmpty) return null;
  final label = (form.field('facetype')?.options ?? const [])
      .where((o) => o.value == value)
      .map((o) => o.label)
      .firstOrNull;
  if (label != null) {
    if (label.contains('上传')) return _AvatarMode.upload;
    if (label.contains('系统')) return _AvatarMode.system;
    if (label.contains('链接')) return _AvatarMode.link;
  }
  return switch (value) {
    '1' => _AvatarMode.system,
    '2' => _AvatarMode.link,
    '3' => _AvatarMode.upload,
    _ => null,
  };
}

ForumAccountOption? _modeOption(NativeFormController c, _AvatarMode mode) {
  for (final o in c.form.field('facetype')?.options ?? const []) {
    if (_modeOf(c.form, o.value) == mode) return o;
  }
  return null;
}

/// Only the chosen avatar mode's fields leave the form; the others stay as
/// drafts, so a switch of mode never sends fields the forum would refuse.
bool avatarFieldActive(NativeFormController c, String name) {
  final mode = _modeOf(c.form, c.value('facetype'));
  if (mode == null) return true;
  return switch (name) {
    'proicon' => mode == _AvatarMode.system,
    'httpurl[0]' || 'httpurl[1]' || 'httpurl[2]' => mode == _AvatarMode.link,
    'upload' || 'uploadurl[1]' || 'uploadurl[2]' => mode == _AvatarMode.upload,
    _ => true,
  };
}

bool _pngAllowed(ForumAccountField field) {
  final accept = (field.accept ?? '').trim().toLowerCase();
  return accept.isEmpty ||
      accept
          .split(',')
          .map((e) => e.trim())
          .any((e) => e == 'image/*' || e == 'image/png' || e == '.png');
}

String? _rangeText(ForumAccountField? f) =>
    f?.min != null && f?.max != null ? '${f!.min} – ${f.max} 的整数' : null;

class _AvatarSection extends StatefulWidget {
  const _AvatarSection({
    required this.controller,
    required this.repository,
    required this.picker,
    required this.cropper,
    required this.avatarUrl,
  });

  final NativeFormController controller;
  final ForumRepository repository;
  final AvatarPicker picker;
  final AvatarCropper cropper;
  final String? avatarUrl;

  @override
  State<_AvatarSection> createState() => _AvatarSectionState();
}

class _AvatarSectionState extends State<_AvatarSection> {
  var _picking = false;
  var _more = false;
  String? _problem;

  /// The picture of the last system choice and the last link previewed.
  ForumAccountOption? _systemChoice;
  String? _linkPreview;

  NativeFormController get _c => widget.controller;

  _AvatarMode? _lastMode;

  @override
  void initState() {
    super.initState();
    _lastMode = _modeOf(_c.form, _c.value('facetype'));
    _c.addListener(_onForm);
  }

  @override
  void dispose() {
    _c.removeListener(_onForm);
    super.dispose();
  }

  void _onForm() {
    if (_c.retired) return;
    final mode = _modeOf(_c.form, _c.value('facetype'));
    if (mode == _lastMode) return;
    _lastMode = mode;
    if (mode == _AvatarMode.link) _defaultWidth('httpurl[1]');
  }

  /// The forum needs a display width in these modes: a blank one starts at the
  /// widest the forum allows. A width the user or the forum set stays.
  void _defaultWidth(String name) {
    final f = _c.form.field(name);
    final max = f?.max?.toInt();
    if (f == null ||
        _c.value(name).trim().isNotEmpty ||
        max == null ||
        max < 1 ||
        (f.min != null && max < f.min!)) {
      return;
    }
    _c.set(name, ['$max']);
  }

  Future<void> _pick() async {
    final field = _c.form.field('upload');
    if (field == null || _picking) return;
    setState(() => _picking = true);
    // Saving waits until the file is in hand and cropped.
    _c.setBusy(true);
    try {
      var upload = await widget.picker();
      if (!mounted || upload == null || _c.retired) return;
      if (_pngAllowed(field)) {
        // The crop reads and bounds the source; the forum's limits judge the
        // file that results. Cancelling leaves everything as it was.
        final cropped = await widget.cropper(context, upload, _c);
        if (!mounted || cropped == null || _c.retired) return;
        upload = cropped;
      }
      final problem = avatarUploadProblem(upload, field);
      setState(() => _problem = problem);
      if (problem != null) return;
      // The mode first, so the file belongs to the active one.
      final up = _modeOption(_c, _AvatarMode.upload);
      if (up != null) _c.set('facetype', [up.value]);
      _defaultWidth('uploadurl[1]');
      _c.setUpload(upload);
    } on FormatException {
      if (mounted && !_c.retired) {
        setState(() => _problem = '图片超过应用读取上限 20 MB，请换一张');
      }
    } catch (_) {
      if (mounted && !_c.retired) {
        setState(() => _problem = '无法读取所选文件');
      }
    } finally {
      // A retired form is silent, so this reaches nothing that replaced it.
      _c.setBusy(false);
      if (mounted && !_c.retired) setState(() => _picking = false);
    }
  }

  void _clear() {
    setState(() => _problem = null);
    _c.setUpload(null);
  }

  Future<void> _chooseSystem() async {
    final chosen = await showModalBottomSheet<ForumAccountOption>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => NativeFormOverlay(
        controller: _c,
        child: _SystemAvatarSheet(
          repository: widget.repository,
          current: _c.value('proicon'),
        ),
      ),
    );
    if (chosen == null || !mounted || _c.retired) return;
    final sys = _modeOption(_c, _AvatarMode.system);
    if (sys != null) _c.set('facetype', [sys.value]);
    _c.set('proicon', [chosen.value]);
    setState(() => _systemChoice = chosen);
  }

  /// A web address the forum can show; anything else is not previewed.
  Uri? get _typedLink {
    final uri = Uri.tryParse(_c.value('httpurl[0]').trim());
    return uri != null &&
            (uri.scheme == 'http' || uri.scheme == 'https') &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? uri
        : null;
  }

  Widget _frame(Widget child) => ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: SizedBox(width: 64, height: 64, child: child),
      );

  Widget _picture(ForumAccountUpload upload) {
    final edge = (128 * MediaQuery.devicePixelRatioOf(context)).ceil();
    return _frame(Image(
      image: ResizeImage(
        MemoryImage(upload.bytes),
        width: edge,
        height: edge,
        policy: ResizeImagePolicy.fit,
      ),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      semanticLabel: '新头像预览',
      errorBuilder: (_, __, ___) => Container(
        color: AppColors.inkSoft,
        child: Icon(Icons.broken_image_outlined, color: AppColors.textFaint),
      ),
    ));
  }

  Widget _netPicture(String url, String label) => Semantics(
        label: label,
        image: true,
        child: _frame(CachedForumImage(
          url: url,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          bypassLoadPolicy: true,
          errorWidget: (_) => Container(
            color: AppColors.inkSoft,
            child:
                Icon(Icons.broken_image_outlined, color: AppColors.textFaint),
          ),
        )),
      );

  /// What the avatar will be after saving, or the current one.
  (Widget, String) _preview(_AvatarMode? mode) {
    final upload = _c.draftUpload;
    if (mode == _AvatarMode.upload && upload != null) {
      return (
        _picture(upload),
        '新头像\n${upload.fileName} · ${_size(upload.bytes.length)}'
      );
    }
    final system = _systemChoice;
    if (mode == _AvatarMode.system &&
        _c.isEdited('proicon') &&
        system?.imageUrl != null) {
      return (_netPicture(system!.imageUrl!, '新系统头像预览'), '新头像');
    }
    final link = _linkPreview;
    // Only the address that was previewed; an edited one needs a new preview.
    if (mode == _AvatarMode.link &&
        link != null &&
        link == _typedLink?.toString()) {
      return (_netPicture(link, '链接图片预览'), '新头像');
    }
    return (
      AccountAvatar(avatarUrl: widget.avatarUrl, size: 64),
      '当前头像',
    );
  }

  Widget _sizeRows(List<String> names) {
    final shown = [
      for (final n in names)
        if (_c.has(n)) n,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    // The forum needs a width in these modes, so a blank one stays in view.
    final widthBlank = _c.value(shown.first).trim().isEmpty;
    // A blank width or a field the forum or the limits rejected stays in view.
    final forced = widthBlank || shown.any((n) => _c.error(n) != null);
    // Once forced open it stays open, so typing the first digit of a blank
    // width does not fold the field away under the cursor.
    if (forced) _more = true;
    final open = _more;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppRow(
          title: const Text('显示尺寸'),
          subtitle: Text(widthBlank ? '需填写宽度' : '宽度 ${_c.value(shown.first)}'),
          value: open ? '收起' : '展开',
          trailing: Icon(open ? Icons.expand_less : Icons.expand_more,
              color: AppColors.textFaint),
          onTap: forced ? null : () => setState(() => _more = !_more),
        ),
        if (open)
          for (final n in shown)
            NativeFieldRow(
              key: ValueKey(n),
              controller: _c,
              name: n,
              title: n.endsWith('[1]') ? '显示宽度' : '显示高度',
              helper: [
                if (n.endsWith('[1]')) '必填',
                _rangeText(_c.form.field(n)),
                if (n.endsWith('[2]')) '选填',
              ].whereType<String>().join('；').nullIfEmpty,
              keyboardType: TextInputType.number,
            ),
      ],
    );
  }

  List<Widget> _modeRows(_AvatarMode? mode) {
    final theme = Theme.of(context);
    final field = _c.form.field('upload');
    switch (mode) {
      case _AvatarMode.system:
        return [
          if (_c.has('proicon'))
            AppRow(
              title: const Text('系统头像'),
              value: systemAvatarValue(
                  _c.form.field('proicon'), _c.value('proicon')),
              onTap: _chooseSystem,
            ),
        ];
      case _AvatarMode.link:
        final typed = _typedLink;
        return [
          NativeFieldRow(
            key: const ValueKey('httpurl[0]'),
            controller: _c,
            name: 'httpurl[0]',
            title: '头像链接',
            keyboardType: TextInputType.url,
          ),
          AppRow(
            icon: Icons.visibility_outlined,
            title: const Text('预览链接中的图片'),
            onTap: typed == null
                ? null
                : () => setState(() => _linkPreview = typed.toString()),
          ),
          _sizeRows(const ['httpurl[1]', 'httpurl[2]']),
        ];
      case _AvatarMode.upload:
        if (field == null) return const [];
        final cropping = _pngAllowed(field);
        final formats = {
          for (final e in (field.accept ?? '').split(','))
            if (e.trim().isNotEmpty) acceptLabel(e)
        }.join('、');
        // Without PNG the picture cannot be cropped and goes up as is.
        final note = [
          if (!cropping) '原图上传',
          if (formats.isNotEmpty) formats,
        ].join(' · ');
        final upload = _c.draftUpload;
        return [
          AppRow(
            icon: Icons.image_outlined,
            title: Text(upload == null ? '选择图片' : '重新选择图片'),
            value: _picking ? '正在读取…' : null,
            onTap: _picking ? null : _pick,
            trailing: upload == null
                ? null
                : IconButton(
                    tooltip: '移除所选图片',
                    onPressed: _clear,
                    icon: const Icon(Icons.close),
                  ),
          ),
          if (_problem != null || note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg, 0, AppSpace.lg, AppSpace.md),
              child: Semantics(
                liveRegion: _problem != null,
                child: Text(
                  _problem ?? note,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _problem != null
                        ? theme.colorScheme.error
                        : AppColors.textMuted,
                  ),
                ),
              ),
            ),
          _sizeRows(const ['uploadurl[1]', 'uploadurl[2]']),
        ];
      case null:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mode = _modeOf(_c.form, _c.value('facetype'));
    final (picture, caption) = _preview(mode);
    final rows = _modeRows(mode);
    return AppGroup(
      label: '头像',
      dividerIndent: AppSpace.lg,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Row(
            children: [
              picture,
              const SizedBox(width: AppSpace.lg),
              Expanded(child: Text(caption, style: theme.textTheme.bodyMedium)),
            ],
          ),
        ),
        NativeFieldRow(controller: _c, name: 'facetype'),
        // Another mode's rows cross-fade in.
        if (rows.isNotEmpty)
          AppSwitcher(
            id: mode,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, row) in rows.indexed) ...[
                  if (i > 0) const Divider(indent: AppSpace.lg),
                  row,
                ],
              ],
            ),
          ),
      ],
    );
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

/// The forum's own picture set, one native page at a time.
class _SystemAvatarSheet extends StatefulWidget {
  const _SystemAvatarSheet({required this.repository, required this.current});

  final ForumRepository repository;
  final String current;

  @override
  State<_SystemAvatarSheet> createState() => _SystemAvatarSheetState();
}

class _SystemAvatarSheetState extends State<_SystemAvatarSheet> {
  var _page = 1;
  late Future<ForumAccountAvatarPage> _future = _fetch(1);
  // The page the grid starts with, once read.
  ForumAccountAvatarPage? _first;
  int _reads = 0;
  final _scroll = ScrollController();
  late final _more = MorePages<ForumAccountAvatarPage>(
    domain: LoadingDomain.avatars,
    fetch: (page) =>
        widget.repository.fetchAccountSystemAvatars(page: int.parse(page)),
    nextOf: (page) => page.nextPage?.toString(),
    idsOf: (page) => [for (final option in page.options) option.value],
    changed: () {
      if (mounted) setState(() {});
    },
  );

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    LoadingPreferences.notifier.addListener(_onLoadingModeChanged);
    if (!LoadingPreferences.isReady) LoadingPreferences.load().ignore();
  }

  @override
  void dispose() {
    LoadingPreferences.notifier.removeListener(_onLoadingModeChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() => _more.maybeLoad(_first, _scroll);

  // 自动接续 starts at the next scroll to the end, never by itself.
  void _onLoadingModeChanged() {
    if (mounted) setState(() {});
  }

  Future<ForumAccountAvatarPage> _fetch(int page) {
    final read = ++_reads;
    _first = null;
    _more.reset();
    return widget.repository.fetchAccountSystemAvatars(page: page).then((data) {
      if (mounted && read == _reads) {
        _first = data;
        // A grid too short to scroll reads on by itself.
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
      }
      return data;
    });
  }

  /// Another page alone, from its top.
  void _go(int page) {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {
      _page = page;
      _future = _fetch(page);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: SafeArea(
        child: FutureBuilder<ForumAccountAvatarPage>(
          future: _future,
          builder: (context, snapshot) {
            final data = snapshot.data;
            final last = data == null
                ? null
                : _more.pages.isEmpty
                    ? data
                    : _more.pages.last;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpace.lg, 0, AppSpace.lg, AppSpace.sm),
                  child: Semantics(
                    header: true,
                    child: Text('系统头像', style: theme.textTheme.titleMedium),
                  ),
                ),
                Expanded(
                  child: snapshot.hasError
                      ? AsyncErrorView(
                          title: '头像加载失败',
                          message: nativeFormErrorText(snapshot.error),
                          onRetry: () => _go(_page),
                        )
                      : data == null
                          ? _grid(const [], loading: true)
                          : _pages(data),
                ),
                // 自动接续 reads on below the grid instead.
                // It turns from the last page shown, appended ones included.
                if (!_more.continuous || data == null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: last?.previousPage == null
                            ? null
                            : () => _go(last!.previousPage!),
                        child: const Text('上一页'),
                      ),
                      Text(last == null ? '' : '第 ${last.page} 页',
                          style: theme.textTheme.bodySmall),
                      TextButton(
                        onPressed: last?.nextPage == null
                            ? null
                            : () => _go(last!.nextPage!),
                        child: const Text('下一页'),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The first page, then those 自动接续 appended, each picture once.
  Widget _pages(ForumAccountAvatarPage first) {
    final pages = [first, ..._more.pages];
    final next = pages.last.nextPage;
    final seen = <String>{};
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        for (final (i, page) in pages.indexed) ...[
          if (i > 0)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
              sliver: SliverToBoxAdapter(child: PageBoundary(page: page.page)),
            ),
          SliverPadding(
            padding: const EdgeInsets.all(AppSpace.lg),
            sliver: _grid([
              for (final option in page.options)
                if (!MorePages.repeats(seen, option.value)) option,
            ]),
          ),
        ],
        if (_more.continuous && (next != null || pages.length > 1))
          SliverToBoxAdapter(
            child: PageEndFooter(
              next: next,
              // The forum gives no page count, so no end is claimed.
              endConfirmed: false,
              loading: _more.loading,
              failed: _more.error != null,
              error: _more.error,
              paused: _more.paused,
              onNext: next == null ? null : () => _more.retry(first, _scroll),
            ),
          ),
      ],
    );
  }

  Widget _grid(List<ForumAccountOption> options, {bool loading = false}) {
    final grid = SliverGrid.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 80,
        mainAxisSpacing: AppSpace.md,
        crossAxisSpacing: AppSpace.md,
      ),
      itemCount: loading ? 20 : options.length,
      itemBuilder: (context, index) {
        if (loading) {
          return const SkeletonBlock(
              width: 64, height: 64, borderRadius: AppRadius.sm);
        }
        final option = options[index];
        final selected = option.value == widget.current;
        Widget placeholder(BuildContext _) => Container(
              alignment: Alignment.center,
              color: AppColors.inkSoft,
              child: Icon(Icons.person_outline, color: AppColors.textFaint),
            );
        return Semantics(
          button: true,
          selected: selected,
          label: '头像 ${index + 1}',
          child: Tooltip(
            message: option.label.isEmpty ? option.value : option.label,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () => Navigator.of(context).pop(option),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: option.imageUrl == null
                        ? placeholder(context)
                        : CachedForumImage(
                            url: option.imageUrl!,
                            fit: BoxFit.cover,
                            bypassLoadPolicy: true,
                            errorWidget: placeholder,
                          ),
                  ),
                  if (selected)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: AppColors.brand, width: 2),
                      ),
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Icon(Icons.check_circle,
                            size: 18, color: AppColors.brand),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (!loading) return grid;
    return CustomScrollView(slivers: [
      SliverPadding(padding: const EdgeInsets.all(AppSpace.lg), sliver: grid),
    ]);
  }
}
