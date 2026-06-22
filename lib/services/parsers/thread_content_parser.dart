import 'package:html/dom.dart' as dom;

import '../../models/forum_models.dart';
import '../forum_url_resolver.dart';

class ThreadContentParser {
  ThreadContentParser({ForumUrlResolver? urls})
      : urls = urls ?? ForumUrlResolver();

  final ForumUrlResolver urls;

  List<ThreadContentSegment> extractInlineSegments(dom.Element content) {
    final segments = <ThreadContentSegment>[];
    final buffer = StringBuffer();
    var activeStyle = const _InlineTextStyleData();

    void flushText() {
      if (buffer.isEmpty) return;
      final text = buffer
          .toString()
          .replaceAll(RegExp(r'[ \t]+\n'), '\n')
          .replaceAll(RegExp(r'\n{2,}'), '\n');
      buffer.clear();
      if (text.trim().isEmpty) {
        if (segments.isNotEmpty && !text.contains('\n')) return;
      }
      segments.add(
        ThreadContentSegment.text(
          text,
          colorValue: activeStyle.colorValue,
          backgroundColorValue: activeStyle.backgroundColorValue,
          isBold: activeStyle.isBold,
          isItalic: activeStyle.isItalic,
          isUnderline: activeStyle.isUnderline,
          isStrike: activeStyle.isStrike,
          fontScale: activeStyle.fontScale,
          href: activeStyle.href,
        ),
      );
    }

    void walk(dom.Node node) {
      if (node is dom.Text) {
        buffer.write(node.text.replaceAll(RegExp(r'[ \t\r\f]+'), ' '));
        return;
      }
      if (node is! dom.Element) return;
      if (_isSaleBoxElement(node)) {
        flushText();
        final saleBox = _saleBoxFromElement(node);
        if (saleBox != null) {
          segments.add(ThreadContentSegment.saleBox(saleBox));
        }
        return;
      }
      if (_isSaleWarningElement(node)) {
        flushText();
        return;
      }
      if (node.localName == 'blockquote' ||
          node.classes.contains('blockquote') ||
          node.classes.contains('quote')) {
        flushText();
        final quoteSegments = extractInlineSegments(_quoteContentElement(node));
        if (quoteSegments.isNotEmpty) {
          segments.add(ThreadContentSegment.quote(quoteSegments));
        }
        return;
      }
      if (node.localName == 'br') {
        buffer.write('\n');
        return;
      }
      if (node.localName == 'img') {
        final src = node.attributes['src'] ?? '';
        if (src.isEmpty) return;
        flushText();
        final alt = _cleanText(
          node.attributes['alt'] ?? node.attributes['title'] ?? '',
        );
        segments.add(
          ThreadContentSegment.image(
            url: urls.absoluteUrl(src),
            alt: alt.isEmpty ? null : alt,
            isEmoji: _isInlineEmojiImage(src),
          ),
        );
        return;
      }

      final previousStyle = activeStyle;
      final nextStyle = _styleForElement(node, activeStyle);
      final styleChanged = !_sameInlineStyle(activeStyle, nextStyle);
      if (styleChanged) flushText();
      activeStyle = nextStyle;
      for (final child in node.nodes) {
        walk(child);
      }
      if (styleChanged) flushText();
      activeStyle = previousStyle;
    }

    for (final node in content.nodes) {
      walk(node);
    }
    flushText();

    final normalizedSegments = segments
        .where((segment) =>
            segment.type == ThreadContentSegmentType.image ||
            segment.type == ThreadContentSegmentType.quote ||
            segment.type == ThreadContentSegmentType.saleBox ||
            (segment.text?.trim().isNotEmpty ?? false))
        .toList();
    return _trimBoundaryWhitespace(normalizedSegments);
  }

  String? extractQuote(dom.Element content) {
    final quoteElement = content.querySelector('blockquote') ??
        content.querySelector('.blockquote');
    if (quoteElement == null) return null;
    final quote = _cleanText(quoteElement.text);
    return quote.isEmpty ? null : quote;
  }

  List<ThreadContentSegment> _trimBoundaryWhitespace(
    List<ThreadContentSegment> segments,
  ) {
    if (segments.isEmpty) return segments;

    final normalized = List<ThreadContentSegment>.of(segments);
    for (var index = 0; index < normalized.length; index++) {
      final segment = normalized[index];
      if (segment.type != ThreadContentSegmentType.text) break;

      final text = segment.text ?? '';
      final trimmed = text.replaceFirst(RegExp('^[\\s\\u00a0]+'), '');
      if (trimmed.trim().isEmpty) {
        normalized.removeAt(index);
        index--;
        continue;
      }
      normalized[index] = _textSegmentWithText(segment, trimmed);
      break;
    }

    for (var index = normalized.length - 1; index >= 0; index--) {
      final segment = normalized[index];
      if (segment.type != ThreadContentSegmentType.text) break;

      final text = segment.text ?? '';
      final trimmed = text.replaceFirst(RegExp('[\\s\\u00a0]+\$'), '');
      if (trimmed.trim().isEmpty) {
        normalized.removeAt(index);
        continue;
      }
      normalized[index] = _textSegmentWithText(segment, trimmed);
      break;
    }

    return normalized;
  }

  ThreadContentSegment _textSegmentWithText(
    ThreadContentSegment segment,
    String text,
  ) {
    return ThreadContentSegment.text(
      text,
      colorValue: segment.colorValue,
      backgroundColorValue: segment.backgroundColorValue,
      isBold: segment.isBold,
      isItalic: segment.isItalic,
      isUnderline: segment.isUnderline,
      isStrike: segment.isStrike,
      fontScale: segment.fontScale,
      href: segment.href,
    );
  }

  dom.Element _quoteContentElement(dom.Element quote) {
    final cloned = quote.clone(true);
    cloned.querySelector('h6.quote2')?.remove();
    cloned.querySelector('h6.quote')?.remove();
    return cloned;
  }

  bool _isSaleBoxElement(dom.Element element) {
    return element.localName == 'h6' &&
        element.classes.contains('quote') &&
        element.classes.contains('jumbotron');
  }

  ThreadSaleBox? _saleBoxFromElement(dom.Element saleElement) {
    final input = saleElement.querySelector('input[type="button"]');
    final onclick = input?.attributes['onclick'] ?? '';
    final buyPath = _buyPathFromOnclick(onclick);
    if (buyPath == null) return null;

    final summary = _cleanText(
      saleElement.querySelector('.s3')?.text ?? saleElement.text,
    );
    final warningElement = _saleWarningElement(saleElement);
    final warning = _cleanText(warningElement?.text ?? '');
    final priceMatch = RegExp(r'售价\s*(\d+)\s*SP币').firstMatch(summary);
    final buyersMatch = RegExp(r'已有\s*(\d+)\s*人购买').firstMatch(summary);
    return ThreadSaleBox(
      summary: summary.isEmpty ? '此帖需要购买后查看' : summary,
      buyPath: buyPath,
      warning: warning.isEmpty ? null : warning,
      price: priceMatch == null ? null : int.tryParse(priceMatch.group(1)!),
      buyers: buyersMatch == null ? null : int.tryParse(buyersMatch.group(1)!),
    );
  }

  String? _buyPathFromOnclick(String onclick) {
    final match = RegExp("location\\.href\\s*=\\s*['\\\"]([^'\\\"]+)['\\\"]")
        .firstMatch(onclick);
    return match?.group(1);
  }

  dom.Element? _saleWarningElement(dom.Element saleElement) {
    final parent = saleElement.parent;
    if (parent == null) return null;
    final siblings = parent.children;
    final index = siblings.indexOf(saleElement);
    if (index == -1 || index + 1 >= siblings.length) return null;
    final sibling = siblings[index + 1];
    if (sibling.localName != 'blockquote') return null;
    return sibling.classes.contains('blockquote') ? sibling : null;
  }

  bool _isSaleWarningElement(dom.Element element) {
    if (element.localName != 'blockquote' ||
        !element.classes.contains('blockquote')) {
      return false;
    }
    final previous = element.previousElementSibling;
    return previous != null && _isSaleBoxElement(previous);
  }

  String _cleanText(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  _InlineTextStyleData _styleForElement(
    dom.Element element,
    _InlineTextStyleData parent,
  ) {
    var style = parent;
    final tag = element.localName;
    if (tag == 'b' || tag == 'strong') style = style.copyWith(isBold: true);
    if (tag == 'i' || tag == 'em') style = style.copyWith(isItalic: true);
    if (tag == 'u') style = style.copyWith(isUnderline: true);
    if (tag == 'strike' || tag == 's' || tag == 'del') {
      style = style.copyWith(isStrike: true);
    }
    if (tag == 'a') {
      final href = element.attributes['href'] ?? '';
      if (href.isNotEmpty && !href.startsWith('javascript:')) {
        style = style.copyWith(href: urls.absoluteUrl(href));
      }
    }

    final color = _elementColor(element);
    if (color != null) style = style.copyWith(colorValue: color);
    final background = _elementBackgroundColor(element);
    if (background != null) {
      style = style.copyWith(backgroundColorValue: background);
    }
    final scale = _elementFontScale(element);
    if (scale != null) style = style.copyWith(fontScale: scale);
    return style;
  }

  int? _elementBackgroundColor(dom.Element element) {
    final style = element.attributes['style'] ?? '';
    final match = RegExp(
      r'background(?:-color)?\s*:\s*([^;]+)',
      caseSensitive: false,
    ).firstMatch(style);
    final raw = match?.group(1);
    if (raw == null) return null;
    return _parseCssColor(raw.trim());
  }

  int? _elementColor(dom.Element element) {
    final style = element.attributes['style'] ?? '';
    final styleMatch =
        RegExp(r'color\s*:\s*([^;]+)', caseSensitive: false).firstMatch(style);
    final raw = styleMatch?.group(1) ?? element.attributes['color'];
    if (raw == null) return null;
    return _parseCssColor(raw.trim());
  }

  int? _parseCssColor(String raw) {
    final lower = raw.toLowerCase();
    const named = {
      'black': 0xff000000,
      'red': 0xffff0000,
      'blue': 0xff0000ff,
      'green': 0xff008000,
      'white': 0xffffffff,
      'gray': 0xff808080,
      'grey': 0xff808080,
      'purple': 0xff800080,
    };
    if (named.containsKey(lower)) return named[lower];
    final hexMatch = RegExp(r'^#?([0-9a-f]{3}|[0-9a-f]{6})$').firstMatch(lower);
    if (hexMatch == null) return null;
    var hex = hexMatch.group(1)!;
    if (hex.length == 3) {
      hex = hex.split('').map((char) => '$char$char').join();
    }
    return int.tryParse('ff$hex', radix: 16);
  }

  double? _elementFontScale(dom.Element element) {
    if (element.localName == 'small') return 0.86;
    final size = element.attributes['size'];
    return switch (size) {
      '1' => 0.78,
      '2' => 0.9,
      '3' => 1,
      '4' => 1.16,
      '5' => 1.32,
      '6' => 1.5,
      '7' => 1.72,
      _ => null,
    };
  }

  bool _isInlineEmojiImage(String src) {
    return src.contains('images/post/smile/') ||
        src.contains('/images/post/smile/');
  }

  bool _sameInlineStyle(
    _InlineTextStyleData left,
    _InlineTextStyleData right,
  ) {
    return left.colorValue == right.colorValue &&
        left.backgroundColorValue == right.backgroundColorValue &&
        left.isBold == right.isBold &&
        left.isItalic == right.isItalic &&
        left.isUnderline == right.isUnderline &&
        left.isStrike == right.isStrike &&
        left.fontScale == right.fontScale &&
        left.href == right.href;
  }
}

class _InlineTextStyleData {
  const _InlineTextStyleData({
    this.colorValue,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.isStrike = false,
    this.fontScale = 1,
    this.href,
    this.backgroundColorValue,
  });

  final int? colorValue;
  final int? backgroundColorValue;
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final bool isStrike;
  final double fontScale;
  final String? href;

  _InlineTextStyleData copyWith({
    int? colorValue,
    bool? isBold,
    bool? isItalic,
    bool? isUnderline,
    bool? isStrike,
    double? fontScale,
    String? href,
    int? backgroundColorValue,
  }) {
    return _InlineTextStyleData(
      colorValue: colorValue ?? this.colorValue,
      backgroundColorValue: backgroundColorValue ?? this.backgroundColorValue,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      isUnderline: isUnderline ?? this.isUnderline,
      isStrike: isStrike ?? this.isStrike,
      fontScale: fontScale ?? this.fontScale,
      href: href ?? this.href,
    );
  }
}
