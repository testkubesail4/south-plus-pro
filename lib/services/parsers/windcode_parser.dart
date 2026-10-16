import 'package:html/dom.dart' as dom;

import '../../models/forum_emojis.dart';
import '../../models/forum_models.dart';
import '../forum_url_resolver.dart';

// WindCode becomes inert DOM nodes; HTML inside raw text is never reparsed.
class WindCodeParser {
  WindCodeParser({this.preview = false});

  final bool preview;

  static final _token =
      RegExp(r'\[(/?)([a-z]+|\*)(?:[=:]([^\]\r\n]*))?\]', caseSensitive: false);
  static const _paired = {
    'b',
    'i',
    'u',
    'size',
    'font',
    'color',
    'quote',
    'sell',
    'code',
    'url',
    'email',
    'img',
    'align',
    'list',
    'li',
    'rm',
    'wmv',
    'flash',
    'iframe',
    'fly',
    'move',
    'shadow',
    'glow'
  };

  List<dom.Node>? parse(String text, {int depth = 0}) {
    // shortcut: nesting beyond 32 stays literal, increase only after renderer stress testing.
    if (depth >= 32) return null;
    final result = <dom.Node>[];
    var offset = 0;
    var changed = false;
    for (final match in _token.allMatches(text)) {
      if (match.start < offset || match[1] == '/') continue;
      final tag = match[2]!.toLowerCase();
      final argument = match[3];
      dom.Element? element;
      var end = match.end;
      if (tag == 's' &&
          RegExp(r'^\[s:', caseSensitive: false).hasMatch(match[0]!)) {
        final emoji = southPlusEmojiById[argument];
        if (emoji != null) {
          element = dom.Element.tag('img')
            ..attributes['src'] = emoji.path
            ..attributes['alt'] = '[s:$argument]';
        }
      } else if (_paired.contains(tag)) {
        if (tag == 'sell' && !preview) continue;
        final close = _closing(text, match, tag);
        if (close == null) continue;
        end = close.end;
        final body = text.substring(match.end, close.start);
        if (!_validArgument(tag, argument, body)) continue;
        element = _element(tag, argument, body, depth);
      }
      if (element == null) continue;
      if (match.start > offset)
        result.addAll(_textNodes(text.substring(offset, match.start)));
      result.add(element);
      offset = end;
      changed = true;
    }
    if (!changed && !preview) return null;
    if (offset < text.length) result.addAll(_textNodes(text.substring(offset)));
    return result;
  }

  List<dom.Node> _textNodes(String text) {
    if (!preview) return [dom.Text(text)];
    return [
      for (final (index, line) in text.split('\n').indexed) ...[
        if (index > 0) dom.Element.tag('br'),
        dom.Text(line),
      ],
    ];
  }

  RegExpMatch? _closing(String text, RegExpMatch opening, String tag) {
    var nesting = 1;
    var opaqueEnd = opening.end;
    for (final token in _token.allMatches(text, opening.end)) {
      if (token.start < opaqueEnd || (token[1] == '/' && token[3] != null))
        continue;
      final tokenTag = token[2]!.toLowerCase();
      if (tag == 'code') {
        if (tokenTag == 'code' && token[1] == '/') return token;
        continue;
      }
      if (tokenTag == 'code' && token[1]!.isEmpty && token[3] == null) {
        final close = _closing(text, token, 'code');
        if (close != null) opaqueEnd = close.end;
        continue;
      }
      if (tokenTag != tag) continue;
      nesting += token[1] == '/' ? -1 : 1;
      if (nesting == 0) return token;
    }
    return null;
  }

  Iterable<RegExpMatch> _listMarkers(String body) sync* {
    var offset = 0;
    for (final token in _token.allMatches(body)) {
      if (token.start < offset || token[1] == '/') continue;
      final tag = token[2]!.toLowerCase();
      if ({'code', 'list', 'li'}.contains(tag)) {
        final close = _closing(body, token, tag);
        if (close != null &&
            _validArgument(
                tag, token[3], body.substring(token.end, close.start))) {
          offset = close.end;
        }
      } else if (tag == '*' && token[3] == null) {
        yield token;
      }
    }
  }

  bool _validColor(String value) =>
      forumWindCodeColors.containsKey(value.toLowerCase()) ||
      RegExp(r'^#?(?:[0-9a-f]{3}|[0-9a-f]{6})$', caseSensitive: false)
          .hasMatch(value);

  bool _validUrl(String value) =>
      value.trim().isNotEmpty &&
      !RegExp(r'[\s<>"\\]').hasMatch(value) &&
      ForumUrlResolver.isSafeExternalUrl(ForumUrlResolver().absoluteUrl(value));

  bool _validArgument(String tag, String? argument, String body) {
    final value = argument?.trim();
    switch (tag) {
      case 'sell':
        return preview &&
            value != null &&
            RegExp(r'^\d+$').hasMatch(value) &&
            int.tryParse(value) != null;
      case 'size':
        return value != null && RegExp(r'^[1-6]$').hasMatch(value);
      case 'font':
        return value != null && value.isNotEmpty;
      case 'color':
        return value != null && _validColor(value);
      case 'align':
        return {'left', 'center', 'right'}.contains(value?.toLowerCase());
      case 'list':
        return value == null || {'', '1', 'a', 'A'}.contains(value);
      case 'url':
        return _validUrl(value ?? body.trim());
      case 'email':
        return ForumUrlResolver.isSafeExternalUrl(
            'mailto:${value ?? body.trim()}');
      case 'img':
        return value == null && _validUrl(body.trim());
      case 'iframe':
        return value == null && _validUrl(body.trim());
      case 'rm':
      case 'wmv':
      case 'flash':
        return _validUrl(body.trim()) &&
            (value == null ||
                value.isEmpty ||
                RegExp(r'^\d+\s*,\s*\d+(?:\s*,\s*[01])?$').hasMatch(value));
      case 'shadow':
      case 'glow':
        final parts = value?.split(',').map((part) => part.trim()).toList();
        return parts != null &&
            parts.length == 3 &&
            int.tryParse(parts[0]) != null &&
            _validColor(parts[1]) &&
            int.tryParse(parts[2]) != null;
      default:
        return value == null;
    }
  }

  dom.Element _element(String tag, String? argument, String body, int depth) {
    argument = argument?.trim();
    if (tag == 'code') return dom.Element.tag('pre')..append(dom.Text(body));
    if (tag == 'img') {
      return dom.Element.tag('img')..attributes['src'] = body.trim();
    }
    if ({'rm', 'wmv', 'flash', 'iframe'}.contains(tag)) {
      return dom.Element.tag('embed')
        ..attributes['src'] = body.trim()
        ..attributes['title'] = '$tag 媒体（应用内不支持播放）';
    }
    final element = dom.Element.tag(switch (tag) {
      'quote' || 'sell' => 'blockquote',
      'size' || 'font' || 'color' => 'font',
      'url' || 'email' => 'a',
      'align' => 'div',
      'list' => argument == null || argument.isEmpty ? 'ul' : 'ol',
      'li' => 'li',
      'fly' || 'move' || 'shadow' || 'glow' => 'span',
      _ => tag,
    });
    if (tag == 'size') element.attributes['size'] = argument ?? '';
    if (tag == 'font') element.attributes['face'] = argument ?? '';
    if (tag == 'color') element.attributes['color'] = argument ?? '';
    if (tag == 'align') element.attributes['align'] = argument ?? '';
    if (tag == 'url') element.attributes['href'] = argument ?? body.trim();
    if (tag == 'email')
      element.attributes['href'] = 'mailto:${argument ?? body.trim()}';
    if (tag == 'list' && argument != null)
      element.attributes['type'] = argument;
    if (tag == 'sell') {
      element
        ..append(dom.Element.tag('b')
          ..append(dom.Text('出售内容 · 售价 ${int.parse(argument!)} SP币')))
        ..append(dom.Element.tag('br'));
    }
    final markers =
        tag == 'list' ? _listMarkers(body).toList() : <RegExpMatch>[];
    if (markers.isNotEmpty) {
      final items = [body.substring(0, markers.first.start)];
      for (var index = 0; index < markers.length; index++) {
        items.add(body.substring(
            markers[index].end,
            index + 1 < markers.length
                ? markers[index + 1].start
                : body.length));
      }
      if (items.first.trim().isNotEmpty) {
        element.nodes.addAll(
            parse(items.first, depth: depth + 1) ?? _textNodes(items.first));
      }
      for (final item in items.skip(1)) {
        element.append(dom.Element.tag('li')
          ..nodes.addAll(parse(item, depth: depth + 1) ?? _textNodes(item)));
      }
    } else {
      element.nodes.addAll(parse(body, depth: depth + 1) ?? _textNodes(body));
    }
    return element;
  }
}
