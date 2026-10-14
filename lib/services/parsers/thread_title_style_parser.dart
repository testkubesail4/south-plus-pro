import 'package:html/dom.dart' as dom;

import '../../models/forum_models.dart';

ForumTitleStyle? parseThreadTitleStyle(dom.Element link) {
  final bold = link.querySelector('b, strong') != null;
  final italic = link.querySelector('i, em') != null;
  final underline = link.querySelector('u') != null;
  final raw = link.querySelector('font[color]')?.attributes['color']?.trim();
  final match =
      RegExp(r'^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').firstMatch(raw ?? '');
  int? color;
  if (match != null) {
    var hex = match.group(1)!;
    if (hex.length == 3) {
      hex = hex.split('').map((char) => '$char$char').join();
    }
    color = int.parse('ff$hex', radix: 16);
  }
  if (!bold && !italic && !underline && color == null) return null;
  return ForumTitleStyle(
    bold: bold,
    italic: italic,
    underline: underline,
    colorValue: color,
  );
}
