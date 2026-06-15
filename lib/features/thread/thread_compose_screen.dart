import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
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
  String? _error;

  String get _draftTitleKey => 'draft.thread.${widget.category.slug}.title';
  String get _draftContentKey => 'draft.thread.${widget.category.slug}.content';

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _title.text = prefs.getString(_draftTitleKey) ?? '';
    _content.text = prefs.getString(_draftContentKey) ?? '';
    setState(() => _draftLoaded = true);
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftTitleKey, _title.text);
    await prefs.setString(_draftContentKey, _content.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('草稿已保存')),
    );
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftTitleKey);
    await prefs.remove(_draftContentKey);
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await widget.repository.submitThread(
      category: widget.category,
      title: _title.text,
      content: _content.text,
    );

    if (!mounted) return;
    setState(() => _submitting = false);
    if (!result.success) {
      setState(() => _error = result.message);
      return;
    }

    await _clearDraft();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
    Navigator.of(context).pop(true);
  }

  void _preview() {
    final title = _title.text.trim().isEmpty ? '未命名主题' : _title.text.trim();
    final content = _content.text.trim().isEmpty ? '暂无正文' : _content.text;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(content, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('发布到 ${widget.category.name}')),
      body: SafeArea(
        top: false,
        child: !_draftLoaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                children: [
                  TextField(
                    controller: _title,
                    enabled: !_submitting,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '标题',
                      prefixIcon: Icon(Icons.title_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _content,
                    enabled: !_submitting,
                    minLines: 10,
                    maxLines: 16,
                    decoration: const InputDecoration(
                      labelText: '正文',
                      alignLabelWithHint: true,
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
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(Icons.send_outlined),
                    label: Text(_submitting ? '提交中...' : '提交'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _submitting ? null : _preview,
                          icon: Icon(Icons.visibility_outlined),
                          label: const Text('预览'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _submitting ? null : _saveDraft,
                          icon: Icon(Icons.save_outlined),
                          label: const Text('存草稿'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const _ComposeNote(),
                ],
              ),
      ),
    );
  }
}

class _ComposeNote extends StatelessWidget {
  const _ComposeNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        '出售内容请使用 WindCode：[sell=0]出售内容[/sell]。整帖出售、隐藏帖和附件后续单独补。',
        style: TextStyle(color: AppColors.textMuted, height: 1.45),
      ),
    );
  }
}
