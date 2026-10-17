import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../models/forum_account_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../common/cached_forum_image.dart';
import '../common/grouped_list.dart';
import '../common/native_form_fields.dart';
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
  });

  final ForumRepository repository;
  final AvatarPicker avatarPicker;

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
      builder: (context, c) {
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

class _AvatarSection extends StatefulWidget {
  const _AvatarSection({
    required this.controller,
    required this.repository,
    required this.picker,
    required this.avatarUrl,
  });

  final NativeFormController controller;
  final ForumRepository repository;
  final AvatarPicker picker;
  final String? avatarUrl;

  @override
  State<_AvatarSection> createState() => _AvatarSectionState();
}

class _AvatarSectionState extends State<_AvatarSection> {
  var _picking = false;
  var _more = false;
  String? _problem;

  NativeFormController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_reconcile);
  }

  @override
  void dispose() {
    _c.removeListener(_reconcile);
    super.dispose();
  }

  // shortcut: the mode is found by its native label (上传/系统); use a native mode key once be-account exposes one.
  ForumAccountOption? _mode(String word) {
    final options = _c.form.field('facetype')?.options ?? const [];
    for (final o in options) {
      if (o.label.contains(word)) return o;
    }
    return null;
  }

  /// A picked file and a changed system picture each belong to one mode; the
  /// forum refuses either under another, so leaving a mode drops its edit.
  void _reconcile() {
    if (_c.retired) return;
    final mode = _c.value('facetype');
    if (mode.isEmpty) return;
    if (mode != _mode('上传')?.value && _c.upload != null) {
      _c.setUpload(null);
    }
    if (mode != _mode('系统')?.value && _c.isEdited('proicon')) {
      _c.revert('proicon');
    }
  }

  Future<void> _pick() async {
    final field = _c.form.field('upload');
    if (field == null || _picking) return;
    setState(() => _picking = true);
    // Saving waits until the file is in hand.
    _c.setBusy(true);
    try {
      final upload = await widget.picker();
      if (!mounted || upload == null || _c.retired) return;
      final problem = avatarUploadProblem(upload, field);
      setState(() => _problem = problem);
      if (problem != null) return;
      // The mode first, so the file is not dropped as belonging to another one.
      final up = _mode('上传');
      if (up != null) _c.set('facetype', [up.value]);
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
    final chosen = await showModalBottomSheet<String>(
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
    // The mode first; leaving upload mode drops a picked file.
    final sys = _mode('系统');
    if (sys != null) _c.set('facetype', [sys.value]);
    _c.set('proicon', [chosen]);
    _c.setUpload(null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upload = _c.upload;
    final field = _c.form.field('upload');
    final more = [
      for (final f in _c.form.fields)
        if (f.group == 'avatar' &&
            f.name != 'facetype' &&
            f.name != 'proicon' &&
            f.type != 'file')
          f.name,
    ];
    final limits = field == null
        ? null
        : [
            if (nativeHintText(field) != null) nativeHintText(field)!,
            if (field.accept != null && field.accept!.trim().isNotEmpty)
              '支持格式：${{
                for (final e in field.accept!.split(','))
                  if (e.trim().isNotEmpty) acceptLabel(e)
              }.join('、')}',
          ].join('；');
    return AppGroup(
      label: '头像',
      dividerIndent: AppSpace.lg,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Row(
            children: [
              if (upload != null)
                ClipOval(
                  // Decoded no larger than the thumbnail needs, whatever the file.
                  child: Image(
                    image: ResizeImage(
                      MemoryImage(upload.bytes),
                      width:
                          (112 * MediaQuery.devicePixelRatioOf(context)).ceil(),
                      height:
                          (112 * MediaQuery.devicePixelRatioOf(context)).ceil(),
                      policy: ResizeImagePolicy.fit,
                    ),
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    semanticLabel: '新头像预览',
                    errorBuilder: (_, __, ___) => Container(
                      width: 56,
                      height: 56,
                      color: AppColors.inkSoft,
                      child: Icon(Icons.broken_image_outlined,
                          color: AppColors.textFaint),
                    ),
                  ),
                )
              else
                AccountAvatar(avatarUrl: widget.avatarUrl, size: 56),
              const SizedBox(width: AppSpace.lg),
              Expanded(
                child: Text(
                  upload == null
                      ? '当前头像'
                      : '新头像，保存后生效\n${upload.fileName} · ${_size(upload.bytes.length)}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        NativeFieldRow(controller: _c, name: 'facetype'),
        if (_c.has('proicon'))
          AppRow(
            title: const Text('系统头像'),
            value: systemAvatarValue(
                _c.form.field('proicon'), _c.value('proicon')),
            onTap: _chooseSystem,
          ),
        if (field != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppRow(
                icon: Icons.image_outlined,
                title: Text(upload == null ? '上传图片' : '重新选择图片'),
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
              if (_problem != null || (limits ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpace.lg, 0, AppSpace.lg, AppSpace.md),
                  child: Semantics(
                    liveRegion: _problem != null,
                    child: Text(
                      _problem ?? limits!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _problem != null
                            ? theme.colorScheme.error
                            : AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        if (more.isNotEmpty)
          AppRow(
            title: const Text('链接与尺寸'),
            value: _more ? '收起' : '展开',
            trailing: Icon(_more ? Icons.expand_less : Icons.expand_more,
                color: AppColors.textFaint),
            onTap: () => setState(() => _more = !_more),
          ),
        if (_more)
          for (final name in more) NativeFieldRow(controller: _c, name: name),
      ],
    );
  }
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

  Future<ForumAccountAvatarPage> _fetch(int page) =>
      widget.repository.fetchAccountSystemAvatars(page: page);

  void _go(int page) => setState(() {
        _page = page;
        _future = _fetch(page);
      });

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
                          : _grid(data.options),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: data?.previousPage == null
                          ? null
                          : () => _go(data!.previousPage!),
                      child: const Text('上一页'),
                    ),
                    Text(data == null ? '' : '第 ${data.page} 页',
                        style: theme.textTheme.bodySmall),
                    TextButton(
                      onPressed: data?.nextPage == null
                          ? null
                          : () => _go(data!.nextPage!),
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

  Widget _grid(List<ForumAccountOption> options, {bool loading = false}) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpace.lg),
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
              onTap: () => Navigator.of(context).pop(option.value),
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
  }
}
