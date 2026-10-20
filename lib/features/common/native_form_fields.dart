import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/forum_account_models.dart';
import '../../services/forum_request_exception.dart';
import '../../theme/app_theme.dart';
import 'app_switcher.dart';
import 'async_state_view.dart';
import 'content_width.dart';
import 'grouped_list.dart';

/// Edits on top of a native [ForumAccountForm]: only fields the user touched
/// leave this object, everything else stays with the forum's own values.
class NativeFormController extends ChangeNotifier {
  NativeFormController(this.form, {this.activeField, this.fieldCheck});

  final ForumAccountForm form;

  /// Whether a field belongs to what the form currently shows (the chosen
  /// avatar mode). Edits of other fields stay as drafts but are neither saved
  /// nor validated; `upload` names the picked file.
  final bool Function(NativeFormController c, String name)? activeField;

  /// A rule across fields (a date made of three selects): its message for a
  /// touched field, or null. Saving waits until it passes.
  final String? Function(NativeFormController c, String name)? fieldCheck;
  final _edits = <String, List<String>>{};
  final _serverErrors = <String, String>{};
  ForumAccountUpload? _upload;

  bool _active(String name) => activeField?.call(this, name) ?? true;

  /// The file to send: null while another avatar mode is chosen.
  ForumAccountUpload? get upload => _active('upload') ? _upload : null;

  /// The picked file, kept as a draft while another mode is chosen.
  ForumAccountUpload? get draftUpload => _upload;
  bool get dirty => changes.isNotEmpty || upload != null;

  /// Anything unsaved, including drafts of a mode that is not chosen now.
  bool get hasDrafts => _edits.isNotEmpty || _upload != null;

  /// A file is being chosen or read; saving waits for it.
  bool get busy => _busy;
  var _busy = false;

  void setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    notifyListeners();
  }

  /// The form was replaced (another account or a reload); overlays opened
  /// from it close and their results are ignored.
  bool get retired => _retired;
  var _retired = false;

  void retire() {
    if (_retired) return;
    _retired = true;
    _announcing = true;
    notifyListeners();
    _announcing = false;
  }

  var _announcing = false;

  // A retired form announces its retirement once and is silent afterwards, so
  // late results (picker, sheets) cannot touch what replaced it.
  @override
  void notifyListeners() {
    if (_retired && !_announcing) return;
    super.notifyListeners();
  }

  bool isEdited(String name) => _edits.containsKey(name);

  /// Back to the forum's own value.
  void revert(String name) {
    if (_edits.remove(name) != null) notifyListeners();
  }

  /// The touched fields of the active mode and their new values.
  Map<String, List<String>> get changes => {
        for (final e in _edits.entries)
          if (_active(e.key)) e.key: List<String>.of(e.value)
      };

  bool has(String name) => form.field(name) != null;

  List<String> values(String name) =>
      _edits[name] ?? form.field(name)?.values ?? const [];

  String value(String name) {
    final v = values(name);
    return v.isEmpty ? '' : v.first;
  }

  void set(String name, List<String> next) {
    final field = form.field(name);
    if (field == null) return;
    _serverErrors.remove(name);
    if (listEquals(next, field.values)) {
      _edits.remove(name);
    } else {
      _edits[name] = List.unmodifiable(next);
    }
    notifyListeners();
  }

  void setUpload(ForumAccountUpload? next) {
    _upload = next;
    notifyListeners();
  }

  /// Carries the edits of [old] over to this fresher form; edits the forum
  /// already holds drop out. A file already submitted is not carried over.
  /// With [draftsOnly], only what [old] was not submitting (the drafts of a
  /// mode that was not chosen) is carried: the rest was saved and confirmed.
  /// Does not notify.
  void adopt(NativeFormController old, {bool draftsOnly = false}) {
    for (final e in old._edits.entries) {
      final field = form.field(e.key);
      if (draftsOnly && old._active(e.key)) continue;
      if (field != null && !listEquals(e.value, field.values)) {
        _edits[e.key] = e.value;
      }
    }
    // A file that was not being submitted is only a draft, whatever the readback said.
    if (!old._active('upload')) _upload = old._upload;
  }

  /// Inline message for a touched field that breaks its native limits.
  String? error(String name) {
    final field = form.field(name);
    final edited = _edits[name];
    return _serverErrors[name] ??
        (field == null || edited == null
            ? null
            : validateNativeField(field, edited) ??
                fieldCheck?.call(this, name));
  }

  /// Marks the fields the forum rejected until they are edited again.
  void setServerErrors(Map<String, String> errors) {
    _serverErrors
      ..clear()
      ..addAll(errors);
    notifyListeners();
  }

  bool get valid => changes.keys.every((name) => error(name) == null);
}

/// The descriptor limits that can be checked before asking the forum.
String? validateNativeField(ForumAccountField field, List<String> values) {
  final v = values.isEmpty ? '' : values.first;
  if (field.required && values.every((e) => e.trim().isEmpty)) return '必填';
  final max = field.maxLength;
  if (max != null && max >= 0 && v.length > max) return '最多 $max 个字符';
  if (v.isNotEmpty &&
      (field.min != null || field.max != null || field.type == 'number')) {
    final n = num.tryParse(v);
    if (n == null) return '请输入数字';
    if (field.min != null && n < field.min!) return '不能小于 ${field.min}';
    if (field.max != null && n > field.max!) return '不能大于 ${field.max}';
  }
  final pattern = field.pattern;
  if (pattern != null && v.isNotEmpty) {
    try {
      if (!RegExp('^(?:$pattern)\$').hasMatch(v)) return '格式不正确';
    } on FormatException {
      // The forum's own rule is left to the forum when Dart cannot read it.
    }
  }
  return null;
}

/// Whether the forum now holds what was submitted, ignoring the trimming and
/// line-break normalisation it applies on its own.
bool nativeValuesEqual(List<String> a, List<String> b) {
  List<String> norm(List<String> v) =>
      v.map((e) => e.replaceAll('\r\n', '\n').trim()).toList()..sort();
  return listEquals(norm(a), norm(b));
}

/// The descriptor hint without the label it repeats; null when nothing is left.
String? nativeHintText(ForumAccountField field) {
  var hint = field.hint.trim();
  final label = field.label.trim();
  if (label.isNotEmpty && hint.startsWith(label)) {
    hint = hint.substring(label.length).trim();
  }
  return hint.isEmpty || hint == label ? null : hint;
}

/// One native field as a row; the kind of control follows the descriptor type.
/// Fields of unknown kinds (hidden, file) render nothing and stay untouched.
class NativeFieldRow extends StatelessWidget {
  const NativeFieldRow({
    super.key,
    required this.controller,
    required this.name,
    this.title,
    this.helper,
    this.emptyValue = '未设置',
    this.summary,
    this.keyboardType,
    this.optionLabel,
  });

  final NativeFormController controller;
  final String name;

  /// Plain words for a native choice; null keeps the forum's own label.
  final String Function(ForumAccountOption option)? optionLabel;

  /// Replaces the native label.
  final String? title;

  /// A line under the title, in addition to the native hint.
  final String? helper;

  /// The value shown by a choice row with nothing chosen.
  final String emptyValue;

  /// Summarises the chosen options of a multi-choice row.
  final String Function(List<ForumAccountOption> chosen)? summary;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final field = controller.form.field(name);
    if (field == null) return const SizedBox.shrink();
    final label = title ?? field.label;
    switch (field.type) {
      case 'select':
      case 'radio':
        return _ChoiceRow(
          controller: controller,
          field: field,
          title: label,
          helper: helper,
          emptyValue: emptyValue,
          optionLabel: optionLabel,
        );
      case 'checkbox':
      case 'multiselect':
        if (field.type == 'checkbox' && field.options.length == 1) {
          return _SwitchRow(
              controller: controller,
              field: field,
              title: label,
              helper: helper);
        }
        return _MultiChoiceRow(
          controller: controller,
          field: field,
          title: label,
          helper: helper,
          emptyValue: emptyValue,
          summary: summary,
        );
      case 'file':
      case 'hidden':
      // Owned by the avatar section, which pages through the choices.
      case 'system-avatar':
        return const SizedBox.shrink();
      default:
        return _TextRow(
          controller: controller,
          field: field,
          title: label,
          helper: helper,
          multiline: field.type == 'textarea',
          keyboardType: keyboardType ??
              (field.type == 'number' ? TextInputType.number : null),
        );
    }
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.controller,
    required this.field,
    required this.title,
    required this.helper,
    required this.emptyValue,
    this.optionLabel,
  });

  final NativeFormController controller;
  final ForumAccountField field;
  final String title;
  final String? helper;
  final String emptyValue;
  final String Function(ForumAccountOption option)? optionLabel;

  String _label(ForumAccountOption o) => o.label.isEmpty
      ? emptyValue
      : optionLabel == null
          ? o.label
          : optionLabel!(o);

  Future<void> _choose(BuildContext context, String current) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => NativeFormOverlay(
        controller: controller,
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SheetTitle(title, helper),
                for (final o in field.options)
                  AppRow(
                    title: Text(_label(o)),
                    selected: o.value == current,
                    onTap: () => Navigator.of(context).pop(o.value),
                  ),
                const SizedBox(height: AppSpace.sm),
              ],
            ),
          ),
        ),
      ),
    );
    if (chosen != null && !controller.retired) {
      controller.set(field.name, [chosen]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = controller.value(field.name);
    final match = field.options.where((o) => o.value == current);
    return AppRow(
      title: Text(title),
      subtitle: helper == null ? null : Text(helper!),
      value: match.isEmpty ? emptyValue : _label(match.first),
      onTap: () => _choose(context, current),
    );
  }
}

class _MultiChoiceRow extends StatelessWidget {
  const _MultiChoiceRow({
    required this.controller,
    required this.field,
    required this.title,
    required this.helper,
    required this.emptyValue,
    required this.summary,
  });

  final NativeFormController controller;
  final ForumAccountField field;
  final String title;
  final String? helper;
  final String emptyValue;
  final String Function(List<ForumAccountOption> chosen)? summary;

  List<ForumAccountOption> _chosen(Iterable<String> values) => [
        for (final o in field.options)
          if (values.contains(o.value)) o
      ];

  Future<void> _choose(BuildContext context) async {
    final selected = controller.values(field.name).toSet();
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return NativeFormOverlay(
          controller: controller,
          child: StatefulBuilder(
            builder: (context, setSheet) => SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SheetTitle(title, helper),
                    for (final o in field.options)
                      AppRow(
                        title: Text(o.label.isEmpty ? o.value : o.label),
                        trailing: Icon(
                          selected.contains(o.value)
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          color: selected.contains(o.value)
                              ? AppColors.brand
                              : AppColors.textFaint,
                        ),
                        selected: selected.contains(o.value),
                        onTap: () => setSheet(() {
                          if (!selected.remove(o.value)) selected.add(o.value);
                        }),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.sm),
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48)),
                        onPressed: () => Navigator.of(context).pop(selected),
                        child: const Text('完成'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (picked != null && !controller.retired) {
      controller.set(field.name, [for (final o in _chosen(picked)) o.value]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _chosen(controller.values(field.name));
    final text = summary != null
        ? summary!(chosen)
        : chosen.isEmpty
            ? emptyValue
            : chosen.map((o) => o.label).join('、');
    return AppRow(
      title: Text(title),
      subtitle: helper == null ? null : Text(helper!),
      value: text,
      onTap: () => _choose(context),
    );
  }
}

/// Wraps a sheet or dialog opened from a form: it closes itself, and only
/// itself, when the form is retired.
class NativeFormOverlay extends StatefulWidget {
  const NativeFormOverlay(
      {super.key, required this.controller, required this.child});

  final NativeFormController controller;
  final Widget child;

  @override
  State<NativeFormOverlay> createState() => _NativeFormOverlayState();
}

class _NativeFormOverlayState extends State<NativeFormOverlay> {
  @override
  void initState() {
    super.initState();
    // A form retired before this first frame is closed once it is mounted.
    if (widget.controller.retired) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
    } else {
      widget.controller.addListener(_check);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (!widget.controller.retired || !mounted) return;
    setState(() {});
    _close();
  }

  void _close() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.controller.retired ? const SizedBox.shrink() : widget.child;
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.title, this.helper);

  final String title;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
              header: true,
              child: Text(title, style: theme.textTheme.titleMedium)),
          if (helper != null) Text(helper!, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.controller,
    required this.field,
    required this.title,
    required this.helper,
  });

  final NativeFormController controller;
  final ForumAccountField field;
  final String title;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final option = field.options.first.value;
    final on = controller.values(field.name).contains(option);
    void toggle(bool v) => controller.set(field.name, v ? [option] : const []);
    return MergeSemantics(
      child: AppRow(
        title: Text(title),
        subtitle: helper == null ? null : Text(helper!),
        onTap: () => toggle(!on),
        trailing: Switch(value: on, onChanged: toggle),
      ),
    );
  }
}

class _TextRow extends StatefulWidget {
  const _TextRow({
    required this.controller,
    required this.field,
    required this.title,
    required this.helper,
    required this.multiline,
    required this.keyboardType,
  });

  final NativeFormController controller;
  final ForumAccountField field;
  final String title;
  final String? helper;
  final bool multiline;
  final TextInputType? keyboardType;

  @override
  State<_TextRow> createState() => _TextRowState();
}

class _TextRowState extends State<_TextRow> {
  late final _text =
      TextEditingController(text: widget.controller.value(widget.field.name));

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final field = widget.field;
    final hint = widget.helper ?? nativeHintText(field);
    final max = field.maxLength;
    // A counter on a 3-character width box is only clutter.
    final counter = max != null && max >= 10;
    return Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The field below carries the title and hint to assistive tools.
          ExcludeSemantics(
              child: Text(widget.title, style: theme.textTheme.titleSmall)),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: ExcludeSemantics(
                child: Text(hint, style: theme.textTheme.bodySmall),
              ),
            ),
          const SizedBox(height: AppSpace.sm),
          Semantics(
            label: widget.title,
            hint: hint,
            child: TextField(
              controller: _text,
              minLines: widget.multiline ? 3 : 1,
              maxLines: widget.multiline ? 8 : 1,
              maxLength: max != null && max > 0 ? max : null,
              keyboardType: widget.keyboardType ??
                  (widget.multiline ? TextInputType.multiline : null),
              decoration: InputDecoration(
                errorText: widget.controller.error(field.name),
                counterText: counter || max == null ? null : '',
              ),
              onChanged: (v) => widget.controller.set(field.name, [v]),
            ),
          ),
        ],
      ),
    );
  }
}

/// A problem or an unconfirmed result, announced and kept above the form.
class NativeFormBanner extends StatelessWidget {
  const NativeFormBanner(this.message,
      {super.key, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 20, color: error),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Text(message,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: error)),
            ),
            if (onAction != null)
              TextButton(onPressed: onAction, child: Text(actionLabel ?? '')),
          ],
        ),
      ),
    );
  }
}

typedef NativeFormLoader = Future<ForumAccountForm> Function();
typedef NativeFormSaver = Future<void> Function(
  ForumAccountForm form,
  Map<String, List<String>> changes,
  ForumAccountUpload? upload,
);

/// Load, edit, save and confirm a native form: Save in the app bar only when
/// something changed, a guard before leaving unsaved edits, and a refetch after
/// saving to prove the forum now holds the new values.
class NativeFormPage extends StatefulWidget {
  const NativeFormPage({
    super.key,
    required this.title,
    required this.sessionEpoch,
    required this.load,
    required this.save,
    required this.builder,
    this.onSaved,
    this.activeField,
    this.fieldCheck,
  });

  final String title;

  /// See [NativeFormController.activeField].
  final bool Function(NativeFormController c, String name)? activeField;

  /// See [NativeFormController.fieldCheck].
  final String? Function(NativeFormController c, String name)? fieldCheck;

  /// Changes whenever the account or network changes; the form reloads.
  final Listenable sessionEpoch;
  final NativeFormLoader load;
  final NativeFormSaver save;
  final List<Widget> Function(
      BuildContext context, NativeFormController controller) builder;

  /// After a confirmed save.
  final VoidCallback? onSaved;

  @override
  State<NativeFormPage> createState() => _NativeFormPageState();
}

class _NativeFormPageState extends State<NativeFormPage> {
  NativeFormController? _active;
  Object? _loadError;
  var _loading = true;
  var _generation = 0;
  var _saving = false;

  /// The forum took the save but reading it back failed: the form is read-only
  /// and cannot save again until a refresh brings a fresh form.
  var _stale = false;
  Map<String, List<String>>? _submitted;
  String? _error;
  String? _warning;

  @override
  void initState() {
    super.initState();
    widget.sessionEpoch.addListener(_reload);
    _start();
  }

  @override
  void dispose() {
    widget.sessionEpoch.removeListener(_reload);
    _active?.removeListener(_changed);
    _active?.retire();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _adopt(NativeFormController? next) {
    _active?.removeListener(_changed);
    // Overlays opened from the old form close and their results are dropped.
    _active?.retire();
    _active = next?..addListener(_changed);
  }

  /// Drops whatever is shown, so a form read for another account never stays
  /// on screen while the next one loads, and reads the form afresh.
  void _start() {
    final generation = ++_generation;
    _adopt(null);
    _loadError = null;
    _loading = true;
    widget.load().then((form) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _adopt(NativeFormController(form,
            activeField: widget.activeField, fieldCheck: widget.fieldCheck));
        _loading = false;
      });
    }, onError: (Object error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    });
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _error = _warning = null;
      _saving = false;
      _stale = false;
      _submitted = null;
      _start();
    });
  }

  Future<void> _save() async {
    final c = _active;
    if (c == null || _saving || _stale || c.busy || !c.dirty) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!c.valid) {
      messenger.showSnackBar(const SnackBar(content: Text('请先修正标出的项目')));
      return;
    }
    final expected = c.changes;
    final generation = _generation;
    setState(() {
      _saving = true;
      _error = _warning = null;
    });
    try {
      await widget.save(c.form, expected, c.upload);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      if (error is ForumAccountValidationException) {
        c.setServerErrors(error.fieldErrors);
      }
      // The forum may or may not have taken the post: no second write until a
      // refresh has read the result.
      final unknown = error is ForumRequestException &&
          (error.kind == ForumRequestKind.server ||
              error.kind == ForumRequestKind.network);
      setState(() {
        _saving = false;
        if (unknown) {
          _stale = true;
          _submitted = expected;
          _warning = '提交结果未确认，请刷新核对。';
        } else {
          _error = nativeFormErrorText(error);
        }
      });
      return;
    }
    if (!mounted || generation != _generation) return;
    final NativeFormController fresh;
    try {
      fresh = NativeFormController(await widget.load(),
          activeField: widget.activeField, fieldCheck: widget.fieldCheck);
    } catch (_) {
      // The edits stay on screen; only the proof is missing.
      if (!mounted || generation != _generation) return;
      setState(() {
        _saving = false;
        _stale = true;
        _submitted = expected;
        _warning = '已提交，但未能刷新核对。';
      });
      return;
    }
    // A reload for another account or network during the save wins.
    if (!mounted || generation != _generation) return;
    final confirmed = expected.entries.every((e) => nativeValuesEqual(
        fresh.form.field(e.key)?.values ?? const [], e.value));
    if (confirmed) {
      messenger.showSnackBar(const SnackBar(content: Text('已保存')));
      widget.onSaved?.call();
    }
    fresh.adopt(c, draftsOnly: confirmed);
    setState(() {
      _adopt(fresh);
      _saving = false;
      _warning = confirmed ? null : '提交后未能确认修改生效，请刷新核对';
    });
  }

  /// Reads the form again after a save whose readback failed: no write, no
  /// replay of the old submit. Edits the forum already holds drop out.
  Future<void> _refreshAfterSubmit() async {
    final old = _active;
    final submitted = _submitted;
    if (old == null || submitted == null || _saving) return;
    final messenger = ScaffoldMessenger.of(context);
    final generation = _generation;
    setState(() => _saving = true);
    final NativeFormController fresh;
    try {
      fresh = NativeFormController(await widget.load(),
          activeField: widget.activeField, fieldCheck: widget.fieldCheck);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _saving = false);
      return;
    }
    if (!mounted || generation != _generation) return;
    final confirmed = submitted.entries.every((e) => nativeValuesEqual(
        fresh.form.field(e.key)?.values ?? const [], e.value));
    if (confirmed) {
      messenger.showSnackBar(const SnackBar(content: Text('已保存')));
      widget.onSaved?.call();
    }
    fresh.adopt(old, draftsOnly: confirmed);
    setState(() {
      _adopt(fresh);
      _saving = false;
      _stale = false;
      _submitted = null;
      _warning = confirmed ? null : '提交后未能确认修改生效，请刷新核对';
    });
  }

  Future<bool> _confirmDiscard() async {
    final c = _active;
    if (c == null) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => NativeFormOverlay(
        controller: c,
        child: AlertDialog(
          title: const Text('放弃修改？'),
          content: const Text('离开后，未保存的修改会丢失。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('继续编辑'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('放弃'),
            ),
          ],
        ),
      ),
    );
    // A result that arrives after the form was replaced is dropped.
    return leave == true && !c.retired;
  }

  @override
  Widget build(BuildContext context) {
    final c = _active;
    final canSave = c != null && c.dirty && !c.busy && !_saving && !_stale;
    return PopScope(
      canPop: !_saving && !(c?.hasDrafts ?? false),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        if (await _confirmDiscard() && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            TextButton(
              onPressed: canSave ? _save : null,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
            const SizedBox(width: AppSpace.sm),
          ],
          bottom: _saving || (c?.busy ?? false)
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(2),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              : null,
        ),
        body: SafeArea(
          top: false,
          // The form fades in over its skeleton; a form read again, for this
          // or another account, drops the one shown at once.
          child: AppSwitcher(
            id: _loadError != null
                ? 'error'
                : _loading || _active == null
                    ? 'loading'
                    : 'form',
            scope: _generation,
            // Built now: a leaving child keeps what it showed.
            child: (() {
              if (_loadError != null) {
                return AsyncErrorView(
                  title: '加载失败',
                  message: nativeFormErrorText(_loadError),
                  onRetry: _reload,
                );
              }
              final form = _active;
              if (_loading || form == null) {
                return const ThreadListSkeleton(itemCount: 4);
              }
              final locked = _saving || form.busy || _stale;
              return LayoutBuilder(
                builder: (context, constraints) {
                  final gutter =
                      appGutter(constraints.maxWidth, AppWidths.form);
                  return KeyedSubtree(
                    // A reloaded form starts its text fields afresh.
                    key: ObjectKey(form),
                    child: ListView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(
                          gutter, AppSpace.sm, gutter, AppSpace.xxl),
                      children: [
                        if (_error != null || _warning != null) ...[
                          NativeFormBanner(
                            _error ?? _warning!,
                            actionLabel: '刷新',
                            onAction: _stale ? _refreshAfterSubmit : null,
                          ),
                          const SizedBox(height: AppSpace.lg),
                        ],
                        // Nothing changes, by pointer or keyboard, under a save,
                        // a file still being read, or a result not yet read back.
                        ExcludeFocus(
                          excluding: locked,
                          child: IgnorePointer(
                            ignoring: locked,
                            child: Opacity(
                              opacity: _stale ? 0.6 : 1,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: widget.builder(context, form),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            })(),
          ),
        ),
      ),
    );
  }
}

/// The forum's own message when it gave one.
String nativeFormErrorText(Object? error) =>
    error is ForumRequestException ? error.message : forumErrorText(error);
