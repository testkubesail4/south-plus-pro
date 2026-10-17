import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../services/forum_request_exception.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../editor/windcode_preview.dart';
import '../editor/windcode_toolbar.dart';

class ReplyComposer extends StatefulWidget {
  const ReplyComposer({
    super.key,
    required this.thread,
    required this.repository,
    required this.onSubmitted,
    this.onCollapse,
  });

  final ForumThread thread;
  final ForumRepository repository;
  final ValueChanged<String> onSubmitted;

  /// Folds the docked composer away; its draft stays.
  final VoidCallback? onCollapse;

  @override
  State<ReplyComposer> createState() => ReplyComposerState();
}

class ReplyComposerState extends State<ReplyComposer> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  final _contentFocus = FocusNode();
  bool _submitting = false;
  bool _editingTitle = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title.text = 'Re:${widget.thread.title}';
    _content.addListener(_handleContentChanged);
  }

  @override
  void didUpdateWidget(covariant ReplyComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thread.url != widget.thread.url && _title.text.isEmpty) {
      _title.text = 'Re:${widget.thread.title}';
    }
  }

  @override
  void dispose() {
    _content.removeListener(_handleContentChanged);
    _title.dispose();
    _content.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  bool get _canSubmit => !_submitting && _content.text.trim().isNotEmpty;

  void _handleContentChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_content.text.trim().isEmpty) {
      setState(() => _error = '回复内容不能为空');
      focusContent();
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final result = await widget.repository.submitReply(
        thread: widget.thread,
        title: _title.text,
        content: _content.text,
      );
      if (!mounted) return;
      if (!result.success) {
        setState(() => _error = result.message);
        return;
      }
      _content.clear();
      // A floor's subject answered that floor only; the next reply is generic.
      _title.text = 'Re:${widget.thread.title}';
      _editingTitle = false;
      widget.onSubmitted(result.message);
    } on ForumRequestException catch (error) {
      if (mounted) setState(() => _error = forumRequestErrorText(error.kind));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void insertContent(String value) {
    final selection = _content.selection;
    final text = _content.text;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    _content.value = TextEditingValue(
      text: text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    focusContent();
  }

  /// Answers one floor: the site's 回复 only sets the subject line.
  void replyTo(String title) {
    _title.text = title;
    focusContent();
  }

  void focusContent() {
    _contentFocus.requestFocus();
  }

  static final _well = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide.none,
  );

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context)
        .textTheme
        .bodySmall!
        .copyWith(color: AppColors.textMuted);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                // The subject line stays folded until the reader edits it.
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _submitting
                      ? null
                      : () => setState(() => _editingTitle = !_editingTitle),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      children: [
                        Icon(
                          Icons.reply_outlined,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _title,
                            builder: (context, value, _) => Text(
                              value.text.trim().isEmpty ? '无标题' : value.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: muted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _editingTitle ? Icons.expand_less : Icons.edit_outlined,
                          size: 16,
                          color: AppColors.textFaint,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: '预览',
                onPressed: _submitting
                    ? null
                    : () => showWindCodePreview(
                  context,
                  title: _title.text,
                  source: _content.text,
                  baseUri: widget.repository.networkConfig.baseUri,
                ),
                color: AppColors.textMuted,
                icon: const Icon(Icons.visibility_outlined),
              ),
              if (widget.onCollapse != null)
                IconButton(
                  tooltip: '收起回复框',
                  onPressed: widget.onCollapse,
                  color: AppColors.textMuted,
                  icon: const Icon(Icons.expand_more),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_editingTitle) ...[
                  TextField(
                    controller: _title,
                    enabled: !_submitting,
                    decoration: const InputDecoration(labelText: '标题'),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: _content,
                  focusNode: _contentFocus,
                  minLines: 3,
                  maxLines: 6,
                  enabled: !_submitting,
                  // A soft well rather than an outlined form field.
                  decoration: InputDecoration(
                    hintText: '输入回复内容',
                    fillColor: AppColors.inkSoft,
                    border: _well,
                    enabledBorder: _well,
                    disabledBorder: _well,
                    focusedBorder: _well,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: WindCodeToolbar(
                        controller: _content,
                        enabled: !_submitting,
                        baseUri: widget.repository.networkConfig.baseUri,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      key: const ValueKey('reply-submit-button'),
                      onPressed: _canSubmit ? _submit : null,
                      icon: _submitting
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              // The button's own foreground, like its label.
                              child: Builder(
                                builder: (context) =>
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: IconTheme.of(context).color,
                                ),
                              ),
                            )
                          : const Icon(Icons.send_outlined, size: 18),
                      label: Text(_submitting ? '发送中' : '发送'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
