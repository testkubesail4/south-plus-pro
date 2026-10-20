import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../services/forum_request_exception.dart';
import '../../services/local_state_preferences.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../editor/windcode_preview.dart';
import '../editor/windcode_toolbar.dart';

class ThreadComposeScreen extends StatefulWidget {
  const ThreadComposeScreen({
    super.key,
    required this.category,
    required this.repository,
  });

  final ForumCategory category;
  final ForumRepository repository;

  @override
  State<ThreadComposeScreen> createState() => _ThreadComposeScreenState();
}

class _ThreadComposeScreenState extends State<ThreadComposeScreen> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  bool _submitting = false;
  bool _draftLoaded = false;
  bool _replyNotice = true;
  String? _error;
  // Sent without a clear answer from the forum: this screen never sends again.
  bool _unconfirmed = false;
  bool _draftNotKept = false;
  bool _posted = false;
  // The board's native form: its categories and bounty rules.
  ThreadComposeDraft? _form;
  Object? _formError;
  String? _category;
  final _bestBounty = TextEditingController();
  final _helpfulBounty = TextEditingController();

  String get _draftTitleKey => 'draft.thread.${widget.category.slug}.title';
  String get _draftContentKey => 'draft.thread.${widget.category.slug}.content';

  @override
  void initState() {
    super.initState();
    _loadDraft();
    _loadForm();
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _bestBounty.dispose();
    _helpfulBounty.dispose();
    super.dispose();
  }

  Future<void> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _title.text = prefs.getString(_draftTitleKey) ?? '';
    _content.text = prefs.getString(_draftContentKey) ?? '';
    setState(() => _draftLoaded = true);
  }

  /// Reads the board's form. A form is spent by one submit, so a definite
  /// failure reads a fresh one, keeping what the user already chose.
  Future<void> _loadForm({bool keepInput = false}) async {
    setState(() => _formError = null);
    try {
      final form =
          await widget.repository.fetchThreadComposeDraft(widget.category);
      if (!mounted) return;
      setState(() {
        _form = form;
        if (keepInput &&
            (_category == null ||
                form.categories.any((c) => c.value == _category))) {
          return;
        }
        // The native placeholder ('') and unknown values read as 不分类.
        _category = form.categories.any((c) => c.value == form.selectedCategory)
            ? form.selectedCategory
            : null;
        // The minimum, shown in full: nothing is charged by a hidden default.
        _bestBounty.text =
            '${form.minBestAmount ?? form.defaultBestAmount ?? ''}';
        _helpfulBounty.text =
            '${form.minHelpfulAmount ?? form.defaultHelpfulAmount ?? ''}';
      });
    } catch (error) {
      if (mounted) setState(() => _formError = error);
    }
  }

  Future<void> _storeDraft() async {
    final title = _title.text;
    final content = _content.text;
    await LocalStatePreferences.write((prefs) async {
      if (!await prefs.setString(_draftTitleKey, title)) return false;
      return prefs.setString(_draftContentKey, content);
    });
  }

  Future<void> _saveDraft() async {
    var saved = false;
    try {
      await _storeDraft();
      saved = true;
    } catch (_) {
      // Keep the editor open so the user can copy the text or retry saving.
    }
    if (!mounted) return;
    if (_unconfirmed) setState(() => _draftNotKept = !saved);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved ? '草稿已保存' : '草稿未能保存到本机，请先复制正文后重试'),
      ),
    );
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftTitleKey);
    await prefs.remove(_draftContentKey);
  }

  BountyInput? get _bounty {
    final form = _form;
    if (form == null || !form.bountySupported) return null;
    return BountyInput(
      best: int.tryParse(_bestBounty.text.trim()),
      helpful: int.tryParse(_helpfulBounty.text.trim()),
      minBest: form.minBestAmount ?? form.defaultBestAmount,
      minHelpful: form.minHelpfulAmount ?? form.defaultHelpfulAmount,
      currency: form.bountyCurrency ?? 'SP币',
    );
  }

  Future<void> _submit() async {
    if (_submitting || _unconfirmed || _posted) return;
    final bounty = _bounty;
    if (bounty != null) {
      if (bounty.error case final error?) {
        setState(() => _error = error);
        return;
      }
      if (!await _confirmBounty(bounty) || !mounted) return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final result = await widget.repository.submitThread(
        category: widget.category,
        title: _title.text,
        content: _content.text,
        enableReplyNotice: _replyNotice,
        draft: _form,
        categoryValue: _category,
        bestAnswerAmount: bounty?.best,
        helpfulAmount: bounty?.helpful,
        confirmBounty: bounty != null,
      );
      if (!mounted) return;
      if (result.unconfirmed) {
        // It may have posted (and charged): lock first, then keep the text.
        setState(() => _unconfirmed = true);
        try {
          await _storeDraft();
        } catch (_) {
          if (mounted) setState(() => _draftNotKept = true);
        }
        return;
      }
      if (!result.success) {
        setState(() => _error = result.message);
        unawaited(_loadForm(keepInput: true));
        return;
      }

      // Posted: nothing below may turn this back into a retryable send.
      _posted = true;
      try {
        await _clearDraft();
      } catch (_) {
        // A stale local draft is harmless; the post itself is up.
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('主题已发布')),
      );
      Navigator.of(context).pop(true);
    } on ForumRequestException catch (error) {
      if (mounted) setState(() => _error = forumRequestErrorText(error.kind));
    } catch (error) {
      if (mounted) setState(() => _error = forumErrorText(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<bool> _confirmBounty(BountyInput bounty) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发布悬赏帖？'),
        content: Text(bounty.terms.join('\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('compose-bounty-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('确认发布并扣除 ${bounty.charge} ${bounty.currency}'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  void _preview() => showWindCodePreview(
        context,
        title: _title.text,
        source: _content.text,
        baseUri: widget.repository.networkConfig.baseUri,
        closeOn: widget.repository.sessionEpoch,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error;
    // Borderless fields: the page itself is the editing surface.
    InputDecoration bare(String hint) => InputDecoration(
          hintText: hint,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        );
    Widget column(Widget child) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: child,
          ),
        );
    final fields = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          TextField(
            controller: _title,
            enabled: !_submitting,
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.text,
            // Long titles wrap instead of scrolling sideways.
            minLines: 1,
            maxLines: 3,
            style: theme.textTheme.titleMedium,
            decoration: bare('标题'),
          ),
          Divider(color: AppColors.border),
          if (_formError != null) ...[
            _FormLoadError(onRetry: _submitting ? null : _loadForm),
            Divider(color: AppColors.border),
          ] else if (_form case final form?
              when form.categories.isNotEmpty || form.bountySupported) ...[
            _ComposeOptions(
              form: form,
              category: _category,
              onCategory: _submitting
                  ? null
                  : (value) => setState(() => _category = value),
              best: _bestBounty,
              helpful: _helpfulBounty,
              bounty: _bounty,
              enabled: !_submitting,
              onChanged: () => setState(() {}),
            ),
            Divider(color: AppColors.border),
          ],
          Expanded(
            child: TextField(
              controller: _content,
              enabled: !_submitting,
              expands: true,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: theme.textTheme.bodyMedium,
              decoration: bare('正文'),
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('发新帖'),
            Text(
              widget.category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '预览',
            onPressed: _submitting || !_draftLoaded ? null : _preview,
            icon: const Icon(Icons.visibility_outlined),
          ),
          IconButton(
            tooltip: '存草稿',
            onPressed: _submitting || !_draftLoaded ? null : _saveDraft,
            icon: const Icon(Icons.save_outlined),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 12, 0),
            // While sending, a spinner joins the label, which stays.
            child: FilledButton.icon(
              key: const ValueKey('compose-submit'),
              onPressed: _submitting || _unconfirmed || _posted || !_draftLoaded
                  ? null
                  : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size(64, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              icon: _submitting
                  // Drawn in the button's own (disabled) content colour.
                  ? Builder(
                      builder: (context) => SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: IconTheme.of(context).color,
                        ),
                      ),
                    )
                  : null,
              label: const Text('发布'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: !_draftLoaded
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Fills the space above the toolbar, and scrolls instead of
                  // overflowing when a keyboard, a long title or an error
                  // leaves too little room.
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: constraints.maxHeight),
                          child: IntrinsicHeight(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_unconfirmed)
                                  MaterialBanner(
                                    key: const ValueKey('compose-unconfirmed'),
                                    content: Text(
                                      '发布结果未确认：请求已发出，但没有收到论坛的明确答复。'
                                      '请到版块查看是否已发布，不要重复发布。'
                                      '${_draftNotKept ? '草稿未能保存到本机，离开前请先复制正文。' : '草稿已保留。'}',
                                    ),
                                    leading: const Icon(Icons.help_outline),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(true),
                                        child: const Text('返回版块查看'),
                                      ),
                                    ],
                                  )
                                else if (error != null)
                                  MaterialBanner(
                                    content: Text(error),
                                    leading: Icon(
                                      Icons.error_outline,
                                      color: theme.colorScheme.error,
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            setState(() => _error = null),
                                        child: const Text('知道了'),
                                      ),
                                    ],
                                  ),
                                Expanded(child: column(fields)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Follows the keyboard up, so formatting stays at hand.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceTint,
                      border: Border(top: BorderSide(color: AppColors.border)),
                    ),
                    child: column(
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(
                          children: [
                            WindCodeToolbar(
                              controller: _content,
                              enabled: !_submitting,
                              baseUri: widget.repository.networkConfig.baseUri,
                            ),
                            SwitchListTile(
                              value: _replyNotice,
                              onChanged: _submitting
                                  ? null
                                  : (value) =>
                                      setState(() => _replyNotice = value),
                              dense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              title: const Text('新回复站内通知'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// The bounty a new thread offers, checked against the board's minimums,
/// with what posting it charges (the forum's own showreward rule).
class BountyInput {
  const BountyInput({
    required this.best,
    required this.helpful,
    required this.minBest,
    required this.minHelpful,
    required this.currency,
  });

  final int? best;
  final int? helpful;
  final int? minBest;
  final int? minHelpful;
  final String currency;

  String? get error {
    final best = this.best;
    final helpful = this.helpful;
    if (best == null || best <= 0) return '请填写最佳答案悬赏';
    if (minBest != null && best < minBest!) return '最佳答案悬赏至少 $minBest';
    if (helpful == null || helpful < 0) return '请填写热心助人悬赏';
    if (minHelpful != null && helpful < minHelpful!) {
      return '热心助人悬赏至少 $minHelpful';
    }
    return null;
  }

  /// Charged on posting: the best answer twice (half is a deposit), plus the
  /// helpful pool. Only meaningful when [error] is null.
  int get charge => best! * 2 + helpful!;

  List<String> get terms => [
        '发布时将预先扣除 $charge $currency：',
        '· 最佳答案 $best × 2 = ${best! * 2}，选出最佳答案后退回 $best',
        '· 热心助人 $helpful，奖励热心回复者，不退回',
        '逾期未选出最佳答案，押金可能无法退回。',
      ];
}

class _FormLoadError extends StatelessWidget {
  const _FormLoadError({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '分类和悬赏设置加载失败',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    );
  }
}

/// The board's category and, on bounty boards, the bounty with its charge.
class _ComposeOptions extends StatelessWidget {
  const _ComposeOptions({
    required this.form,
    required this.category,
    required this.onCategory,
    required this.best,
    required this.helpful,
    required this.bounty,
    required this.enabled,
    required this.onChanged,
  });

  final ThreadComposeDraft form;
  final String? category;
  final ValueChanged<String?>? onCategory;
  final TextEditingController best;
  final TextEditingController helpful;
  final BountyInput? bounty;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bounty = this.bounty;
    final error = bounty?.error;
    Widget amount(String label, TextEditingController c, int? min, Key key) =>
        Expanded(
          child: TextField(
            key: key,
            controller: c,
            enabled: enabled,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              labelText: label,
              suffixText: bounty?.currency,
              helperText: min == null ? null : '至少 $min',
              isDense: true,
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (form.categories.isNotEmpty)
            DropdownButtonFormField<String?>(
              key: const ValueKey('compose-category'),
              initialValue: category,
              onChanged: onCategory,
              decoration: const InputDecoration(
                labelText: '分类',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('不分类')),
                for (final c in form.categories)
                  DropdownMenuItem(value: c.value, child: Text(c.label)),
              ],
            ),
          if (bounty != null) ...[
            if (form.categories.isNotEmpty) const SizedBox(height: AppSpace.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                amount('最佳答案悬赏', best, bounty.minBest,
                    const ValueKey('compose-bounty-best')),
                const SizedBox(width: AppSpace.md),
                amount('热心助人悬赏', helpful, bounty.minHelpful,
                    const ValueKey('compose-bounty-helpful')),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                error ??
                    '发布时预先扣除 ${bounty.charge} ${bounty.currency}，'
                        '其中 ${bounty.best} 在选出最佳答案后退回',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: error == null ? null : theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
