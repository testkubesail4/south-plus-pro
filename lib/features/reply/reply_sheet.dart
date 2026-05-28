import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';

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
  State<ReplyComposer> createState() => _ReplyComposerState();
}

class _ReplyComposerState extends State<ReplyComposer> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title.text = 'Re:${widget.thread.title}';
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
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
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
          const Text(
            '回复',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
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
            minLines: 5,
            maxLines: 8,
            enabled: !_submitting,
            decoration: const InputDecoration(
              labelText: '内容',
              hintText: '输入回复内容',
            ),
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
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: Text(_submitting ? '提交中...' : '提交'),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _submitting ? null : () {},
                child: const Text('表 情'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
