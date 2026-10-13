import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/forum_pm_models.dart';
import '../../services/forum_repository.dart';
import '../../services/forum_request_exception.dart';
import '../common/async_state_view.dart';
import '../editor/windcode_toolbar.dart';

/// Writes, replies, forwards or edits a message through a server compose form.
/// [path] is the server entry (reply/forward/edit/profile link); null opens a
/// blank message. Returns the accepted server result and refresh destination.
class PmComposeScreen extends StatefulWidget {
  const PmComposeScreen({super.key, required this.repository, this.path});

  final ForumRepository repository;
  final String? path;

  @override
  State<PmComposeScreen> createState() => _PmComposeScreenState();
}

class _PmComposeScreenState extends State<PmComposeScreen> {
  late Future<ForumPmCompose> _future = _fetch();
  final _recipient = TextEditingController();
  final _title = TextEditingController();
  final _body = TextEditingController();
  ForumPmCompose? _compose;
  bool _saveToSendbox = false;
  bool _submitting = false;
  String? _error;

  Future<ForumPmCompose> _fetch() async {
    final compose = await widget.repository.fetchPmCompose(path: widget.path);
    _compose = compose;
    _recipient.text = compose.recipientUid;
    _title.text = compose.title;
    _body.text = compose.body;
    _saveToSendbox = compose.saveToSendbox;
    return compose;
  }

  @override
  void dispose() {
    _recipient.dispose();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final compose = _compose;
    if (_submitting || compose == null) return;
    final recipient = _recipient.text.trim();
    final title = _title.text.trim();
    final body = _body.text;
    // Server prefills (e.g. edit forms) may hold a name; only numeric UIDs post.
    final missing = !RegExp(r'^\d+$').hasMatch(recipient)
        ? '请输入数字收件人 UID'
        : title.isEmpty
            ? '标题不能为空'
            : body.trim().isEmpty
                ? '内容不能为空'
                : null;
    if (missing != null) {
      setState(() => _error = missing);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.repository.submitPm(
        compose: compose,
        recipientUid: recipient,
        title: title,
        body: body,
        saveToSendbox: _saveToSendbox,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
      Navigator.of(context).pop(result);
    } on ForumRequestException catch (error) {
      if (mounted) setState(() => _error = forumErrorText(error));
    } on ForumRepositoryException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('短消息')),
      body: SafeArea(
        top: false,
        child: FutureBuilder<ForumPmCompose>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return AsyncErrorView(
                title: '消息表单加载失败',
                message: forumErrorText(snapshot.error),
                onRetry: () => setState(() {
                  _future = _fetch();
                }),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final compose = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              children: [
                TextField(
                  controller: _recipient,
                  enabled: !_submitting,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '收件人 UID',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
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
                  controller: _body,
                  enabled: !_submitting,
                  minLines: 8,
                  maxLines: 14,
                  decoration: const InputDecoration(
                    labelText: '内容',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 10),
                WindCodeToolbar(
                  controller: _body,
                  enabled: !_submitting,
                  baseUri: widget.repository.networkConfig.baseUri,
                  allowSale: false,
                ),
                CheckboxListTile(
                  value: _saveToSendbox,
                  onChanged: _submitting
                      ? null
                      : (value) =>
                          setState(() => _saveToSendbox = value ?? false),
                  title: const Text('保存到发件箱'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const ValueKey('pm-submit-button'),
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
                  label: Text(_submitting
                      ? '提交中...'
                      : compose.isEdit
                          ? '提交修改'
                          : '发送'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
