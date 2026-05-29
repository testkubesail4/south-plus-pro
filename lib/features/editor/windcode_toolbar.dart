import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class WindCodeToolbar extends StatelessWidget {
  const WindCodeToolbar({
    super.key,
    required this.controller,
    this.enabled = true,
  });

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _WindCodeAction(
        label: '出售',
        icon: Icons.sell_outlined,
        onTap: () => _showSaleSheet(context),
      ),
      _WindCodeAction(
        label: '引用',
        icon: Icons.format_quote,
        onTap: () => _wrapSelection('[quote]', '[/quote]', '引用内容'),
      ),
      _WindCodeAction(
        label: '链接',
        icon: Icons.link,
        onTap: () => _wrapSelection('[url]', '[/url]', 'https://'),
      ),
      _WindCodeAction(
        label: '图片',
        icon: Icons.image_outlined,
        onTap: () => _wrapSelection('[img]', '[/img]', '图片地址'),
      ),
      _WindCodeAction(
        label: '代码',
        icon: Icons.code,
        onTap: () => _wrapSelection('[code]', '[/code]', '代码'),
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: actions
              .map(
                (action) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: Icon(action.icon, size: 16),
                    label: Text(action.label),
                    onPressed: enabled ? action.onTap : null,
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  void _wrapSelection(String prefix, String suffix, String placeholder) {
    _wrapRange(
      prefix: prefix,
      suffix: suffix,
      placeholder: placeholder,
      selection: controller.value.selection,
    );
  }

  Future<void> _showSaleSheet(BuildContext context) async {
    final capturedSelection = controller.value.selection;
    final priceController = TextEditingController(text: '0');
    final price = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '出售选中内容',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  capturedSelection.isCollapsed
                      ? '未选中文字，将插入可编辑的出售内容占位。'
                      : '已选中的文字会被包裹为出售内容。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '售价',
                    suffixText: 'SP币',
                    helperText: '填 0 可作为免费出售测试。',
                  ),
                  onSubmitted: (_) => _submitSalePrice(
                    context,
                    priceController.text,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _submitSalePrice(
                          context,
                          priceController.text,
                        ),
                        icon: const Icon(Icons.sell_outlined, size: 18),
                        label: const Text('插入出售'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    priceController.dispose();
    if (price == null) return;

    _wrapRange(
      prefix: '[sell=$price]',
      suffix: '[/sell]',
      placeholder: '出售内容',
      selection: capturedSelection,
    );
  }

  void _submitSalePrice(BuildContext context, String value) {
    final price = int.tryParse(value.trim());
    if (price == null || price < 0) return;
    Navigator.of(context).pop(price);
  }

  void _wrapRange({
    required String prefix,
    required String suffix,
    required String placeholder,
    required TextSelection selection,
  }) {
    final value = controller.value;
    final text = value.text;
    final rawStart = selection.start < 0 ? text.length : selection.start;
    final rawEnd = selection.end < 0 ? text.length : selection.end;
    final start = rawStart < rawEnd ? rawStart : rawEnd;
    final end = rawStart < rawEnd ? rawEnd : rawStart;
    final selected = start == end ? placeholder : text.substring(start, end);
    final replacement = '$prefix$selected$suffix';
    controller.value = TextEditingValue(
      text: text.replaceRange(start, end, replacement),
      selection: TextSelection(
        baseOffset: start + prefix.length,
        extentOffset: start + prefix.length + selected.length,
      ),
    );
  }
}

class _WindCodeAction {
  const _WindCodeAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}
