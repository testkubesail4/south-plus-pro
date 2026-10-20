import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../services/forum_request_exception.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../common/content_width.dart';
import '../editor/windcode_preview.dart';
import '../editor/windcode_toolbar.dart';

/// Edits one floor through the forum's own edit form, prefilled with the
/// post's original BBCode.
///
/// Pops `true` once the forum confirmed the save, `false` when a save was
/// sent but not confirmed (the floor should be reloaded to check), and null
/// when nothing was sent.
class ThreadEditScreen extends StatefulWidget {
  const ThreadEditScreen({
    super.key,
    required this.repository,
    required this.link,
    required this.openingPost,
  });

  final ForumRepository repository;

  /// The floor's own edit link, as the forum rendered it.
  final ThreadActionLink link;
  final bool openingPost;

  @override
  State<ThreadEditScreen> createState() => _ThreadEditScreenState();
}

// The repository's own wording says what to do next (e.g. reopen the edit).
String _errorText(Object error) =>
    error is ForumRequestException && error.message.isNotEmpty
        ? error.message
        : forumErrorText(error);

class _ThreadEditScreenState extends State<ThreadEditScreen> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  ThreadEditDraft? _draft;
  Object? _loadError;
  bool _saving = false;
  // A save went out without a confirmation: it may have taken effect.
  bool _unconfirmed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title.addListener(_changedText);
    _content.addListener(_changedText);
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  void _changedText() => setState(() {});

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final draft = await widget.repository.fetchEditDraft(widget.link);
      if (!mounted) return;
      _title.text = draft.title;
      _content.text = draft.content;
      setState(() => _draft = draft);
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  bool get _changed =>
      _draft != null &&
      (_title.text != _draft!.title || _content.text != _draft!.content);

  Future<void> _save() async {
    if (_saving) return;
    if (_content.text.trim().isEmpty) {
      setState(() => _error = '正文不能为空');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // A draft is good for one send. After an unconfirmed one, this explicit
      // save reads the form again and sends the text on screen.
      final draft = _unconfirmed
          ? await widget.repository.fetchEditDraft(widget.link)
          : _draft!;
      final result = await widget.repository.submitEdit(
        draft: draft,
        title: _title.text,
        content: _content.text,
      );
      if (!mounted) return;
      if (result.success) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _unconfirmed = true;
        _error = result.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _unconfirmed = true;
        _error = _errorText(error);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _leave() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃修改？'),
        content: const Text('未保存的修改会丢失。'),
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
    );
    if (discard == true && mounted) {
      Navigator.of(context).pop(_unconfirmed ? false : null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _draft != null;
    final loadError = _loadError;
    return PopScope(
      canPop: !_saving && !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.openingPost ? '编辑帖子' : '编辑回复'),
          actions: [
            if (ready) ...[
              IconButton(
                tooltip: '预览',
                onPressed: _saving
                    ? null
                    : () => showWindCodePreview(
                          context,
                          title: _title.text,
                          source: _content.text,
                          baseUri: widget.repository.networkConfig.baseUri,
                          closeOn: widget.repository.sessionEpoch,
                        ),
                icon: const Icon(Icons.visibility_outlined),
              ),
              Padding(
                padding: const EdgeInsets.only(right: AppSpace.sm),
                child: FilledButton(
                  key: const ValueKey('edit-save-button'),
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '保存中' : '保存修改'),
                ),
              ),
            ],
          ],
        ),
        body: ready
            ? _form(context)
            : loadError != null
                ? AsyncErrorView(
                    title: '无法打开编辑',
                    message: _errorText(loadError),
                    onRetry: _load,
                  )
                : const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  // One scroll view: with the keyboard up and large text, the outcome of a
  // save and its 查看帖子 stay reachable above the fields.
  Widget _form(BuildContext context) {
    final error = _error;
    return LayoutBuilder(
      builder: (context, box) {
        final gutter = appGutter(box.maxWidth, AppWidths.form);
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding:
              EdgeInsets.fromLTRB(gutter, AppSpace.md, gutter, AppSpace.md),
          children: [
            if (error != null) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  _unconfirmed
                      ? '保存未确认：$error。修改可能已经生效，请先查看帖子确认，再决定是否重新保存。'
                      : error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              if (_unconfirmed)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(false),
                    child: const Text('查看帖子'),
                  ),
                ),
              const SizedBox(height: AppSpace.sm),
            ],
            TextField(
              controller: _title,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: _content,
              enabled: !_saving,
              minLines: 8,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                labelText: '正文',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            WindCodeToolbar(
              controller: _content,
              enabled: !_saving,
              baseUri: widget.repository.networkConfig.baseUri,
            ),
          ],
        );
      },
    );
  }
}
