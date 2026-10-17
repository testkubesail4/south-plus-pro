import 'dart:async' show scheduleMicrotask;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../theme/app_theme.dart';

/// Shows [child] while the session is the one it was opened in. Once the
/// session moves on it blanks at once and removes its own route (never one
/// above it), so another account's category names never stay on screen.
class SessionBound extends StatefulWidget {
  const SessionBound({
    super.key,
    required this.session,
    required this.generation,
    required this.child,
  });

  /// Moves when the session changes; [generation] is its value when the route
  /// was asked for.
  final ValueListenable<int> session;
  final int generation;
  final Widget child;

  @override
  State<SessionBound> createState() => _SessionBoundState();
}

class _SessionBoundState extends State<SessionBound> {
  bool get _stale => widget.session.value != widget.generation;

  @override
  void initState() {
    super.initState();
    if (_stale) {
      // Changed before this first frame: close once it is mounted.
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
    } else {
      widget.session.addListener(_check);
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_check);
    super.dispose();
  }

  // Raised while the page behind may be mid-build.
  void _check() => scheduleMicrotask(() {
        if (!mounted || !_stale) return;
        setState(() {});
        _close();
      });

  void _close() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) =>
      _stale ? const SizedBox.shrink() : widget.child;
}

/// What the 管理 sheet asked for.
sealed class ManageAction {
  const ManageAction();
}

class CreateCategory extends ManageAction {
  const CreateCategory();
}

class DeleteCategory extends ManageAction {
  const DeleteCategory(this.category);
  final FavoriteCategory category;
}

/// 收藏分类: the categories as they are now, a way to add one and a way to
/// delete each but the default. Closing it changes nothing.
Future<ManageAction?> showManageCategoriesSheet(
  BuildContext context, {
  required ValueListenable<int> session,
  required FavoriteCollections data,
}) {
  // Frozen now: a change before the first frame must still read as stale.
  final generation = session.value;
  return showModalBottomSheet<ManageAction>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: AppWidths.sheet),
    builder: (sheetContext) => SessionBound(
      session: session,
      generation: generation,
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetTitle('收藏分类'),
              for (final category in data.categories)
                ListTile(
                  key: ValueKey('favorite-folder-row:${category.id}'),
                  title: Text(category.label),
                  subtitle: category.count == null
                      ? null
                      : Text('${category.count} 个主题'),
                  trailing: category.isDefault || !category.canDelete
                      ? null
                      : IconButton(
                          key:
                              ValueKey('favorite-folder-delete:${category.id}'),
                          tooltip: '删除分类',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => Navigator.of(sheetContext)
                              .pop(DeleteCategory(category)),
                        ),
                ),
              if (data.canCreate)
                ListTile(
                  key: const ValueKey('favorite-folder-new'),
                  leading: const Icon(Icons.add),
                  title: const Text('新建分类'),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(const CreateCategory()),
                ),
              const SizedBox(height: AppSpace.sm),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The name of a new category; null when cancelled.
Future<String?> showNewCategoryDialog(
  BuildContext context, {
  required ValueListenable<int> session,
  int? maxLength,
}) {
  final generation = session.value;
  return showDialog<String>(
    context: context,
    builder: (_) => SessionBound(
      session: session,
      generation: generation,
      child: _NewCategoryDialog(maxLength: maxLength),
    ),
  );
}

class _NewCategoryDialog extends StatefulWidget {
  const _NewCategoryDialog({this.maxLength});

  final int? maxLength;

  @override
  State<_NewCategoryDialog> createState() => _NewCategoryDialogState();
}

class _NewCategoryDialogState extends State<_NewCategoryDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _value => _name.text.trim();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建分类'),
      content: TextField(
        key: const ValueKey('favorite-category-name'),
        controller: _name,
        autofocus: true,
        maxLength: widget.maxLength,
        decoration: const InputDecoration(labelText: '分类名称'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          if (_value.isNotEmpty) Navigator.of(context).pop(_value);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('favorite-category-create'),
          onPressed:
              _value.isEmpty ? null : () => Navigator.of(context).pop(_value),
          child: const Text('创建'),
        ),
      ],
    );
  }
}

/// Whether to delete [category]; false when kept or dismissed.
Future<bool> showDeleteCategoryDialog(
  BuildContext context, {
  required ValueListenable<int> session,
  required FavoriteCategory category,
}) async {
  final generation = session.value;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => SessionBound(
      session: session,
      generation: generation,
      child: AlertDialog(
        title: Text('删除分类「${category.label}」？'),
        content: const Text('其中的主题会移到默认分类。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('保留'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    ),
  );
  return confirmed == true;
}

/// Whether to stop favouriting [titles]; false when kept or dismissed.
Future<bool> showRemoveFavoritesDialog(
  BuildContext context, {
  required ValueListenable<int> session,
  required List<String> titles,
}) async {
  final generation = session.value;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => SessionBound(
      session: session,
      generation: generation,
      child: AlertDialog(
        title: const Text('取消收藏'),
        content: Text(titles.length == 1
            ? '「${titles.single}」将从收藏中移除。'
            : '${titles.length} 个主题将从收藏中移除：\n'
                '${titles.take(3).map((t) => '「$t」').join('\n')}'
                '${titles.length > 3 ? '\n…' : ''}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('保留'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('取消收藏'),
          ),
        ],
      ),
    ),
  );
  return confirmed == true;
}

/// The category [count] favourites go to; null when dismissed.
Future<FavoriteCategory?> showMoveSheet(
  BuildContext context, {
  required ValueListenable<int> session,
  required List<FavoriteCategory> categories,
  required int count,
}) {
  final generation = session.value;
  return showModalBottomSheet<FavoriteCategory>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: AppWidths.sheet),
    builder: (sheetContext) => SessionBound(
      session: session,
      generation: generation,
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SheetTitle('移动 $count 个主题到…'),
              for (final category in categories)
                ListTile(
                  key: ValueKey('favorite-move-to:${category.id}'),
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(category.label),
                  onTap: () => Navigator.of(sheetContext).pop(category),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.sm),
                child: TextButton(
                  key: const ValueKey('favorite-move-cancel'),
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('取消'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.sm),
      child: Semantics(
        header: true,
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}
