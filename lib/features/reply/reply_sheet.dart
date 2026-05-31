import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../editor/windcode_toolbar.dart';

class ReplyComposer extends StatefulWidget {
  const ReplyComposer({
    super.key,
    required this.thread,
    required this.repository,
    required this.onSubmitted,
  });

  final ForumThread thread;
  final ForumRepository repository;
  final ValueChanged<String> onSubmitted;

  @override
  State<ReplyComposer> createState() => ReplyComposerState();
}

class ReplyComposerState extends State<ReplyComposer> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  final _contentFocus = FocusNode();
  bool _submitting = false;
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
    if (_content.text.trim().isEmpty) {
      setState(() => _error = '回复内容不能为空');
      focusContent();
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await widget.repository.submitReply(
      thread: widget.thread,
      title: _title.text,
      content: _content.text,
    );

    if (!mounted) return;
    setState(() => _submitting = false);
    if (!result.success) {
      setState(() => _error = result.message);
      return;
    }

    _content.clear();
    widget.onSubmitted(result.message);
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

  void focusContent() {
    _contentFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '快速回复',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'WindCode',
                  style: TextStyle(
                    color: AppColors.brandDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _title,
            enabled: !_submitting,
            decoration: const InputDecoration(
              labelText: '标题',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _content,
            focusNode: _contentFocus,
            minLines: 5,
            maxLines: 8,
            enabled: !_submitting,
            decoration: const InputDecoration(
              labelText: '内容',
              hintText: '输入回复内容',
            ),
          ),
          const SizedBox(height: 10),
          WindCodeToolbar(
            controller: _content,
            enabled: !_submitting,
            baseUri: widget.repository.networkConfig.baseUri,
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('reply-submit-button'),
                  onPressed: _canSubmit ? _submit : null,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_outlined, size: 18),
                  label: Text(_submitting ? '提交中...' : '提交回复'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
