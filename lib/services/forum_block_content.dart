import 'package:html/dom.dart' as dom;

String _simplifyText(String text) {
  final buffer = StringBuffer();
  int? previous;
  for (final rune in text.runes) {
    if (rune != previous) buffer.writeCharCode(rune);
    previous = rune;
  }
  return buffer
      .toString()
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'''[~⁉`‘’'～！!？?。，、,.<>]+'''), '!');
}

String matchableBlockContent(String content) => content.splitMapJoin(
      RegExp(r'<[^>]+>'),
      onMatch: (match) => match.group(0)!,
      onNonMatch: (chunk) =>
          chunk.startsWith('<') ? chunk : _simplifyText(chunk),
    );

// linPlus defaults: whole short reply, text preferred, all smileys equivalent.
String? blockContentKey(dom.Element root, {bool ignorable = false}) {
  if (ignorable) return '<IGNORABLE>';
  if (root.text.length > 512 || root.innerHtml.length > 2048) return null;
  final parts = <String>[];
  var externalImage = false;
  var complex = false;
  void visit(dom.Element node) {
    final tag = node.localName ?? '';
    if (node.classes.contains('jumbotron') ||
        (tag == 'blockquote' && node.classes.contains('blockquote3')) ||
        const {
          'script',
          'style',
          'button',
          'input',
          'select',
          'form',
          'video',
          'object',
          'frame',
          'iframe'
        }.contains(tag)) {
      complex = true;
      return;
    }
    if (tag == 'hr') return;
    if (tag == 'br') {
      parts.add(' ');
      return;
    }
    if (tag == 'img') {
      var src = node.attributes['data-rinsp-defer-src'] ?? '';
      if (src.isEmpty) src = node.attributes['src'] ?? '';
      if (src.startsWith('images/post/smile/')) {
        if (parts.isEmpty || parts.last != '<EMOJI>') parts.add('<EMOJI>');
      } else {
        parts.add('<EXT_IMG>');
        externalImage = true;
      }
      return;
    }
    final marked = !const {
      'font',
      'center',
      'i',
      'u',
      'b',
      'sup',
      'sub',
      'code',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'h7',
      'h8',
      'h9',
      'p',
      'span',
      'div',
      'blockquote'
    }.contains(tag);
    if (marked) parts.add('<${tag.toUpperCase()}>');
    for (final child in node.nodes) {
      if (child is dom.Text) {
        final text = _simplifyText(child.text.toLowerCase());
        if (text.isNotEmpty) parts.add(text);
      } else if (child is dom.Element) {
        visit(child);
        if (complex) return;
      }
    }
    if (marked) parts.add('<${tag.toUpperCase()}_END>');
  }

  visit(root);
  if (complex) return null;
  final text = parts
      .where((part) => !part.startsWith('<'))
      .join()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (text.isNotEmpty) {
    final withoutSymbols =
        text.replaceAll('!', ' ').replaceAll(RegExp(' +'), ' ').trim();
    return withoutSymbols.isEmpty ? text : withoutSymbols;
  }
  if (externalImage) return null;
  final tokens = parts.join().replaceAll(RegExp(r'\s+'), ' ').trim();
  return tokens.isEmpty ? '<EMPTY>' : tokens;
}
