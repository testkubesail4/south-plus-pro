import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../services/forum_request_exception.dart';
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
    if (_submitting) return;
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
      );
      if (!mounted) return;
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
    } on ForumRequestException catch (error) {
      if (mounted) setState(() => _error = forumRequestErrorText(error.kind));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _preview() => showWindCodePreview(
        context,
        title: _title.text,
        source: _content.text,
        baseUri: widget.repository.networkConfig.baseUri,
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
              onPressed: _submitting || !_draftLoaded ? null : _submit,
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
                                if (error != null)
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
