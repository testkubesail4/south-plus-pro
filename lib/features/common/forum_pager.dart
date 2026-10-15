import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Compact pager: previous · "第 N / M 页" (opens the page picker) · next.
/// A null [onSelected] disables every control, e.g. while a page loads.
class ForumPager extends StatelessWidget {
  const ForumPager({
    super.key,
    required this.current,
    required this.total,
    required this.onSelected,
  });

  final int current;
  final int total;
  final ValueChanged<int>? onSelected;

  @override
  Widget build(BuildContext context) {
    final select = onSelected;
    Widget divider() => VerticalDivider(
      width: 1,
      thickness: 1,
      indent: 10,
      endIndent: 10,
      color: AppColors.border,
    );
    Widget arrow(String tooltip, IconData icon, int page, bool enabled) =>
        IconButton(
          tooltip: tooltip,
          onPressed: enabled && select != null ? () => select(page) : null,
          icon: Icon(icon),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 44),
        );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, minHeight: 44),
        child: Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              children: [
                arrow('上一页', Icons.chevron_left, current - 1, current > 1),
                divider(),
                Expanded(
                  child: Tooltip(
                    message: '选择页码',
                    child: InkWell(
                      onTap: select == null
                          ? null
                          : () async {
                              final page = await showForumPagePicker(
                                context,
                                current: current,
                                total: total,
                              );
                              if (page != null && page != current) {
                                select(page);
                              }
                            },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                '第 $current / $total 页',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: select == null
                                      ? AppColors.textFaint
                                      : AppColors.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.expand_more,
                              size: 18,
                              color: AppColors.textFaint,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                divider(),
                arrow('下一页', Icons.chevron_right, current + 1, current < total),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet listing every page plus a number field; resolves to the
/// chosen page, or null when dismissed.
Future<int?> showForumPagePicker(
  BuildContext context, {
  required int current,
  required int total,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _PagePickerSheet(current: current, total: total),
  );
}

class _PagePickerSheet extends StatefulWidget {
  const _PagePickerSheet({required this.current, required this.total});

  final int current;
  final int total;

  @override
  State<_PagePickerSheet> createState() => _PagePickerSheetState();
}

class _PagePickerSheetState extends State<_PagePickerSheet> {
  static const _tile = 56.0;
  final _input = TextEditingController();
  ScrollController? _grid;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _grid?.dispose();
    super.dispose();
  }

  void _submit() {
    final page = int.tryParse(_input.text.trim());
    if (page == null) {
      setState(() => _error = '请输入有效页码');
      return;
    }
    Navigator.of(context).pop(page.clamp(1, widget.total));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + media.viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '选择页码',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '共 ${widget.total} 页',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = (constraints.maxWidth / _tile).floor().clamp(
                  1,
                  12,
                );
                final row = (widget.current - 1) ~/ columns;
                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: _tile * 4.5),
                  child: GridView.builder(
                    shrinkWrap: true,
                    // Opens with the current page's row in view.
                    controller: _grid ??= ScrollController(
                      initialScrollOffset: row > 1 ? (row - 1) * _tile : 0,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: _tile,
                    ),
                    itemCount: widget.total,
                    itemBuilder: (context, index) => _PageTile(
                      page: index + 1,
                      selected: index + 1 == widget.current,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: '页码',
                    hintText: '1 - ${widget.total}',
                    errorText: _error,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(72, 48),
                  ),
                  child: const Text('跳转'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({required this.page, required this.selected});

  final int page;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: selected ? AppColors.brand : AppColors.inkSoft,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).pop(page),
          child: Center(
            child: Text(
              '$page',
              style: TextStyle(
                color: selected ? Colors.white : AppColors.text,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
