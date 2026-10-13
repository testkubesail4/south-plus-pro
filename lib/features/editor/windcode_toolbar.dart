import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'south_plus_emoji_picker.dart';

class WindCodeToolbar extends StatelessWidget {
  const WindCodeToolbar({
    super.key,
    required this.controller,
    this.enabled = true,
    this.baseUri,
    this.allowSale = true,
  });

  final TextEditingController controller;
  final bool enabled;
  final Uri? baseUri;

  /// Sale insertion is off where no purchase flow is verified (PMs).
  final bool allowSale;

  // The site editor's own size, colour and font menus.
  static const sizes = [1, 2, 3, 4, 5, 6];
  static const colors = <String, int>{
    'skyblue': 0xFF87CEEB,
    'royalblue': 0xFF4169E1,
    'blue': 0xFF0000FF,
    'darkblue': 0xFF00008B,
    'orange': 0xFFFFA500,
    'orangered': 0xFFFF4500,
    'crimson': 0xFFDC143C,
    'red': 0xFFFF0000,
    'firebrick': 0xFFB22222,
    'darkred': 0xFF8B0000,
    'green': 0xFF008000,
    'limegreen': 0xFF32CD32,
    'seagreen': 0xFF2E8B57,
    'teal': 0xFF008080,
    'deeppink': 0xFFFF1493,
    'tomato': 0xFFFF6347,
    'coral': 0xFFFF7F50,
    'purple': 0xFF800080,
    'indigo': 0xFF4B0082,
    'burlywood': 0xFFDEB887,
    'sandybrown': 0xFFF4A460,
    'sienna': 0xFFA0522D,
    'chocolate': 0xFFD2691E,
    'silver': 0xFFC0C0C0,
  };
  static const fonts = [
    '宋体',
    '楷体_GB2312',
    '新宋体',
    '黑体',
    '隶书',
    'Andale Mono',
    'Arial',
    'Arial Black',
    'Book Antiqua',
    'Century Gothic',
    'Comic Sans MS',
    'Courier New',
    'Georgia',
    'Impact',
    'Tahoma',
    'Times New Roman',
    'Trebuchet MS',
    'Script MT Bold',
    'Stencil',
    'Verdana',
    'Lucida Console',
  ];

  @override
  Widget build(BuildContext context) {
    final actions = [
      _WindCodeAction(
        label: '表情',
        icon: Icons.mood_outlined,
        onTap: () => _showEmojiSheet(context),
      ),
      _WindCodeAction(
        label: '粗体',
        icon: Icons.format_bold,
        onTap: () => _wrapSelection('[b]', '[/b]', '文字'),
      ),
      _WindCodeAction(
        label: '斜体',
        icon: Icons.format_italic,
        onTap: () => _wrapSelection('[i]', '[/i]', '文字'),
      ),
      _WindCodeAction(
        label: '下划线',
        icon: Icons.format_underlined,
        onTap: () => _wrapSelection('[u]', '[/u]', '文字'),
      ),
      _WindCodeAction(
        label: '字号',
        icon: Icons.format_size,
        onTap: () => _pickAndWrap(
          context,
          title: '字号',
          options: {for (final size in sizes) '$size': '$size'},
          tag: 'size',
        ),
      ),
      _WindCodeAction(
        label: '颜色',
        icon: Icons.format_color_text,
        onTap: () => _pickAndWrap(
          context,
          title: '颜色',
          options: {for (final name in colors.keys) name: name},
          tag: 'color',
          swatch: (name) => Color(colors[name]!),
        ),
      ),
      _WindCodeAction(
        label: '字体',
        icon: Icons.font_download_outlined,
        onTap: () => _pickAndWrap(
          context,
          title: '字体',
          options: {for (final font in fonts) font: font},
          tag: 'font',
        ),
      ),
      _WindCodeAction(
        label: '对齐',
        icon: Icons.format_align_center,
        onTap: () => _pickAndWrap(
          context,
          title: '对齐',
          options: const {
            'left': '居左',
            'center': '居中',
            'right': '居右',
          },
          tag: 'align',
        ),
      ),
      _WindCodeAction(
        label: '列表',
        icon: Icons.format_list_bulleted,
        onTap: () => _showListSheet(context),
      ),
      if (allowSale)
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

  Future<String?> _pickOption(
    BuildContext context, {
    required String title,
    required Map<String, String> options,
    Color Function(String value)? swatch,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final MapEntry(:key, :value) in options.entries)
                      ListTile(
                        leading: swatch == null
                            ? null
                            : CircleAvatar(
                                radius: 10,
                                backgroundColor: swatch(key),
                              ),
                        title: Text(value),
                        onTap: () => Navigator.of(context).pop(key),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndWrap(
    BuildContext context, {
    required String title,
    required Map<String, String> options,
    required String tag,
    Color Function(String value)? swatch,
  }) async {
    final selection = controller.value.selection;
    final value = await _pickOption(
      context,
      title: title,
      options: options,
      swatch: swatch,
    );
    if (value == null) return;
    _wrapRange(
      prefix: '[$tag=$value]',
      suffix: '[/$tag]',
      placeholder: '文字',
      selection: selection,
    );
  }

  Future<void> _showListSheet(BuildContext context) async {
    final selection = controller.value.selection;
    final type = await _pickOption(
      context,
      title: '列表',
      options: const {
        '': '无序列表',
        '1': '数字列表',
        'a': '字母列表',
      },
    );
    if (type == null) return;
    final text = controller.text;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    // Each selected line becomes one item, as the site editor prompts per item.
    final lines = text
        .substring(start, end)
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final items =
        (lines.isEmpty ? ['项目'] : lines).map((line) => '[li]$line[/li]').join();
    final open = type.isEmpty ? '[list]' : '[list=$type]';
    final value = '$open$items[/list]';
    controller.value = TextEditingValue(
      text: text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + value.length),
    );
  }

  Future<void> _showEmojiSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SouthPlusEmojiPicker(
          baseUri: baseUri,
          onSelected: (emoji) {
            Navigator.of(context).pop();
            _insertText(emoji.code);
          },
        );
      },
    );
  }

  void _insertText(String value) {
    final text = controller.text;
    final selection = controller.selection;
    final rawStart = selection.start < 0 ? text.length : selection.start;
    final rawEnd = selection.end < 0 ? text.length : selection.end;
    final start = rawStart < rawEnd ? rawStart : rawEnd;
    final end = rawStart < rawEnd ? rawEnd : rawStart;
    controller.value = TextEditingValue(
      text: text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + value.length),
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
                        icon: Icon(Icons.sell_outlined, size: 18),
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
