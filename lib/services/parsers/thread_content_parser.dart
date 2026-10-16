import 'package:html/dom.dart' as dom;

import '../../models/forum_models.dart';
import '../forum_url_resolver.dart';
import 'windcode_parser.dart';

class ThreadContentParser {
  ThreadContentParser({ForumUrlResolver? urls})
      : urls = urls ?? ForumUrlResolver();

  final ForumUrlResolver urls;

  List<ThreadContentSegment> parseWindCode(String source) {
    final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final content = dom.Element.tag('div')
      ..nodes.addAll(WindCodeParser(preview: true).parse(normalized) ??
          [dom.Text(normalized)]);
    return _extractInlineSegments(content, const _InlineTextStyleData(),
        parseRaw: false);
  }

  List<ThreadContentSegment> extractInlineSegments(dom.Element content) =>
      _extractInlineSegments(content, const _InlineTextStyleData());

  List<ThreadContentSegment> _extractInlineSegments(
      dom.Element content, _InlineTextStyleData inherited,
      {bool parseRaw = true}) {
    final segments = <ThreadContentSegment>[];
    final buffer = StringBuffer();
    // Preserve authored breaks while folding HTML source indentation.
    final explicitBreaks = <int>[];
    var activeStyle = _styleForElement(content, inherited);

    void flushText() {
      if (buffer.isEmpty) return;
      final explicitBreak = explicitBreaks.isNotEmpty;
      var breakIndex = 0;
      var text = buffer.toString().replaceAllMapped(
        RegExp(r'[ \t]*\n(?:[ \t]*\n)*'),
        (match) {
          var count = 0;
          while (breakIndex < explicitBreaks.length &&
              explicitBreaks[breakIndex] < match.end) {
            if (explicitBreaks[breakIndex] >= match.start) count++;
            breakIndex++;
          }
          return '\n' * (count == 0 ? 1 : count);
        },
      );
      buffer.clear();
      explicitBreaks.clear();
      if (text.trim().isEmpty) {
        if (!explicitBreak) return;
        text = text.replaceAll(RegExp(r'[ \t]'), '');
      }
      final segment = ThreadContentSegment.text(
        text,
        colorValue: activeStyle.colorValue,
        backgroundColorValue: activeStyle.backgroundColorValue,
        isBold: activeStyle.isBold,
        isItalic: activeStyle.isItalic,
        isUnderline: activeStyle.isUnderline,
        isStrike: activeStyle.isStrike,
        fontScale: activeStyle.fontScale,
        href: activeStyle.href,
        fontFamily: activeStyle.fontFamily,
      );
      segments.addAll(_linkify(segment));
    }

    void walk(dom.Node node, bool expandRaw) {
      if (node is dom.Text) {
        final raw = expandRaw ? WindCodeParser().parse(node.text) : null;
        if (raw != null) {
          for (final child in raw) {
            walk(child, false);
          }
        } else {
          buffer.write(node.text.replaceAll(RegExp(r'[ \t\r\f]+'), ' '));
        }
        return;
      }
      if (node is! dom.Element) return;
      if ({'script', 'style', 'form', 'input', 'button', 'noscript'}
          .contains(node.localName)) return;
      if ((node.localName == 'h6' || _isServerCodeLabel(node)) &&
          _isCodeElement(node.nextElementSibling)) return;
      if (_isCodeElement(node)) {
        flushText();
        final lines = node.classes.contains('blockquote2')
            ? node.querySelectorAll('ol > li')
            : <dom.Element>[];
        segments.add(ThreadContentSegment.code(
            lines.isEmpty ? _codeText(node) : lines.map(_codeText).join('\n')));
        return;
      }
      if ({'iframe', 'object', 'embed', 'video', 'audio'}
          .contains(node.localName)) {
        flushText();
        final source = node.attributes['src'] ??
            node.attributes['data'] ??
            node.querySelector('source')?.attributes['src'];
        final resolved = source == null ? null : urls.absoluteUrl(source);
        final safe =
            resolved != null && ForumUrlResolver.isSafeExternalUrl(resolved);
        segments.add(ThreadContentSegment.media(
          url: safe ? resolved : null,
          text: node.attributes['title'] ?? '${node.localName} 媒体（应用内不支持播放）',
        ));
        return;
      }
      if (node.localName == 'ul' || node.localName == 'ol') {
        flushText();
        segments.add(ThreadContentSegment.list([
          for (final item
              in node.children.where((child) => child.localName == 'li'))
            ThreadContentSegment.block(
                _extractInlineSegments(item, activeStyle, parseRaw: expandRaw)),
        ],
            isOrdered: node.localName == 'ol',
            listStyle: node.attributes['type'] ?? '1'));
        return;
      }
      if (node.localName == 'table') {
        final code = _serverCodeTableContent(node);
        if (code != null) {
          walk(code, expandRaw);
          return;
        }
        flushText();
        final rows = <List<ThreadContentTableCell>>[];
        for (final row in node.querySelectorAll('tr')) {
          var parent = row.parent;
          while (parent != null && parent.localName != 'table') {
            parent = parent.parent;
          }
          if (parent != node) continue;
          rows.add([
            for (final cell in row.children
                .where((child) => {'td', 'th'}.contains(child.localName)))
              ThreadContentTableCell(
                  _extractInlineSegments(cell, activeStyle,
                      parseRaw: expandRaw),
                  isHeader: cell.localName == 'th'),
          ]);
        }
        segments.add(ThreadContentSegment.table(rows));
        return;
      }
      final alignment = node.attributes['align'] ??
          RegExp(r'text-align\s*:\s*(left|right|center|justify)',
                  caseSensitive: false)
              .firstMatch(node.attributes['style'] ?? '')
              ?.group(1) ??
          (node.localName == 'center' ? 'center' : null);
      if (alignment != null &&
          {'left', 'right', 'center', 'justify'}.contains(alignment)) {
        flushText();
        final clone = node.clone(true)
          ..attributes.remove('align')
          ..attributes.remove('style');
        segments.add(ThreadContentSegment.block(
            _extractInlineSegments(clone, _styleForElement(node, activeStyle),
                parseRaw: expandRaw),
            alignment: switch (alignment) {
              'center' => ThreadContentAlignment.center,
              'right' => ThreadContentAlignment.end,
              'justify' => ThreadContentAlignment.justify,
              _ => ThreadContentAlignment.start,
            }));
        return;
      }
      if (_isSaleBoxElement(node)) {
        flushText();
        final saleBox = _saleBoxFromElement(node);
        if (saleBox != null) {
          segments.add(ThreadContentSegment.saleBox(saleBox));
          return;
        }
      }
      if (_isSaleWarningElement(node)) {
        flushText();
        return;
      }
      if (node.localName == 'blockquote' ||
          node.classes.contains('blockquote3') ||
          node.classes.contains('blockquote') ||
          node.classes.contains('quote')) {
        flushText();
        final quoteSegments = _extractInlineSegments(
            _quoteContentElement(node), activeStyle,
            parseRaw: expandRaw);
        if (quoteSegments.isNotEmpty) {
          segments.add(ThreadContentSegment.quote(quoteSegments));
        }
        return;
      }
      if (node.localName == 'br') {
        explicitBreaks.add(buffer.length);
        buffer.write('\n');
        return;
      }
      if (node.localName == 'img') {
        final src = node.attributes['src'] ?? '';
        if (src.isEmpty) return;
        final imageUrl = urls.absoluteUrl(src);
        if (!ForumUrlResolver.isSafeExternalUrl(imageUrl) ||
            !{'http', 'https'}.contains(Uri.tryParse(imageUrl)?.scheme)) {
          buffer.write(node.attributes['alt'] ?? '[图片链接无效]');
          return;
        }
        flushText();
        final alt = _cleanText(
          node.attributes['alt'] ?? node.attributes['title'] ?? '',
        );
        segments.add(
          ThreadContentSegment.image(
            url: imageUrl,
            alt: alt.isEmpty ? null : alt,
            isEmoji: _isInlineEmojiImage(src),
            href: activeStyle.href,
          ),
        );
        return;
      }

      final isBlock = {
        'p',
        'div',
        'li',
        'tr',
        'h1',
        'h2',
        'h3',
        'h4',
        'h5',
        'h6'
      }.contains(node.localName);
      if (isBlock) buffer.write('\n');
      final previousStyle = activeStyle;
      final nextStyle = _styleForElement(node, activeStyle);
      final styleChanged = !_sameInlineStyle(activeStyle, nextStyle);
      if (styleChanged) flushText();
      activeStyle = nextStyle;
      for (final child in node.nodes) {
        walk(child, expandRaw);
      }
      if (styleChanged) flushText();
      activeStyle = previousStyle;
      if (isBlock) buffer.write('\n');
    }

    for (final node in content.nodes) {
      walk(node, parseRaw);
    }
    flushText();

    bool isInline(ThreadContentSegment segment) =>
        segment.type == ThreadContentSegmentType.text || segment.isEmoji;
    final normalized = <ThreadContentSegment>[];
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      if (segment.type == ThreadContentSegmentType.text &&
          (segment.text?.trim().isEmpty ?? true) &&
          (index == 0 ||
              index == segments.length - 1 ||
              ((segment.text ?? '').split('\n').length <= 2 &&
                  (!isInline(segments[index - 1]) ||
                      !isInline(segments[index + 1]))))) continue;
      normalized.add(segment);
    }
    return _trimBoundaryWhitespace(normalized);
  }

  Iterable<ThreadContentSegment> _linkify(ThreadContentSegment segment) sync* {
    final text = segment.text ?? '';
    if (segment.href != null) {
      yield segment;
      return;
    }
    var offset = 0;
    for (final match in RegExp(r'''(?:https?://|www\.)[^\s<>"'，。；！？]+''',
            caseSensitive: false)
        .allMatches(text)) {
      var value = match
          .group(0)!
          .split(RegExp(r'\[/[a-z][^\]]*\]', caseSensitive: false))
          .first;
      value = value.replaceFirst(RegExp(r'[.,;!?:]+$'), '');
      while (value.endsWith(')') &&
          ')'.allMatches(value).length > '('.allMatches(value).length) {
        value = value.substring(0, value.length - 1);
      }
      while (value.endsWith(']') &&
          ']'.allMatches(value).length > '['.allMatches(value).length) {
        value = value.substring(0, value.length - 1);
      }
      final href = urls.absoluteUrl(
          value.toLowerCase().startsWith('www.') ? 'https://$value' : value);
      if (!ForumUrlResolver.isSafeExternalUrl(href)) continue;
      if (match.start > offset) {
        yield _textSegmentWithText(
            segment, text.substring(offset, match.start));
      }
      final link = _textSegmentWithText(segment, value);
      yield ThreadContentSegment.text(value,
          colorValue: link.colorValue,
          backgroundColorValue: link.backgroundColorValue,
          isBold: link.isBold,
          isItalic: link.isItalic,
          isUnderline: link.isUnderline,
          isStrike: link.isStrike,
          fontScale: link.fontScale,
          href: href,
          fontFamily: link.fontFamily);
      offset = match.start + value.length;
    }
    if (offset < text.length)
      yield _textSegmentWithText(segment, text.substring(offset));
  }

  String? extractQuote(dom.Element content) {
    for (final element
        in content.querySelectorAll('blockquote, .blockquote, .blockquote3')) {
      if (_isCodeElement(element)) continue;
      final quote = _cleanText(element.text);
      if (quote.isNotEmpty) return quote;
    }
    return null;
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
      fontFamily: segment.fontFamily,
    );
  }

  bool _isServerCodeLabel(dom.Element node) =>
      node.localName == 'span' &&
      node.classes.containsAll({'f10', 's8'}) &&
      node.children.length == 1 &&
      node.children.single.localName == 'a' &&
      node.children.single.children.isEmpty &&
      _cleanText(node.text) == '复制代码';

  dom.Element? _serverCodeTableContent(dom.Element table) {
    bool hasText(dom.Element node) => node.nodes
        .whereType<dom.Text>()
        .any((text) => text.text.trim().isNotEmpty);
    var cell = table;
    for (final tag in ['tbody', 'tr', 'td']) {
      if (hasText(cell) ||
          cell.children.length != 1 ||
          cell.children.single.localName != tag) return null;
      cell = cell.children.single;
    }
    if (hasText(cell) || cell.children.length != 3) return null;
    final clear = cell.children[0];
    final label = cell.children[1];
    final code = cell.children[2];
    if (clear.localName != 'div' ||
        !clear.classes.contains('c') ||
        clear.children.isNotEmpty ||
        clear.text.trim().isNotEmpty ||
        !_isServerCodeLabel(label) ||
        code.localName != 'div' ||
        !code.classes.contains('blockquote2') ||
        hasText(code) ||
        code.children.length != 1 ||
        code.children.single.localName != 'ol') return null;
    final lines = code.children.single;
    if (hasText(lines) || lines.children.any((line) => line.localName != 'li'))
      return null;
    return code;
  }

  bool _isCodeElement(dom.Element? node) =>
      node != null &&
      (node.localName == 'pre' ||
          node.localName == 'code' ||
          node.classes.contains('blockquote2') ||
          (node.localName == 'blockquote' &&
              (RegExp(r'^code(?:\d|_|$)', caseSensitive: false)
                      .hasMatch(node.id) ||
                  RegExp(r'Copy code|复制代码', caseSensitive: false)
                      .hasMatch(node.previousElementSibling?.text ?? ''))));

  String _codeText(dom.Node node) {
    if (node is dom.Text) return node.text;
    if (node is! dom.Element) return '';
    if (node.localName == 'br') return '\n';
    if ({'script', 'style'}.contains(node.localName)) return '';
    return node.nodes.map(_codeText).join().replaceAll('\r\n', '\n');
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
    // Without a buy action, the same markup holds unlocked post content.
    return previous != null &&
        _isSaleBoxElement(previous) &&
        _saleBoxFromElement(previous) != null;
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
      final resolved = urls.absoluteUrl(href);
      if (href.isNotEmpty &&
          urls.forumLinkTarget(resolved) is! ForumBlockedLinkTarget) {
        style = style.copyWith(href: resolved);
      }
    }

    final family = element.attributes['face'];
    if (family != null && family.trim().isNotEmpty)
      style = style.copyWith(fontFamily: family);
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
        RegExp(r'(?:^|;)\s*color\s*:\s*([^;]+)', caseSensitive: false)
            .firstMatch(style);
    final raw = styleMatch?.group(1) ?? element.attributes['color'];
    if (raw == null) return null;
    return _parseCssColor(raw.trim());
  }

  int? _parseCssColor(String raw) {
    final lower = raw.toLowerCase();
    if (forumWindCodeColors.containsKey(lower))
      return forumWindCodeColors[lower];
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
        left.fontFamily == right.fontFamily &&
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
    this.fontFamily,
  });

  final int? colorValue;
  final int? backgroundColorValue;
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final bool isStrike;
  final double fontScale;
  final String? href;
  final String? fontFamily;

  _InlineTextStyleData copyWith({
    int? colorValue,
    bool? isBold,
    bool? isItalic,
    bool? isUnderline,
    bool? isStrike,
    double? fontScale,
    String? href,
    int? backgroundColorValue,
    String? fontFamily,
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
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}
