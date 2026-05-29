import 'package:html/dom.dart' as dom;

import '../../models/forum_models.dart';
import '../forum_url_resolver.dart';
import 'thread_content_parser.dart';

class ThreadDetailParser {
  const ThreadDetailParser({
    this.urls = const ForumUrlResolver(),
    this.contentParser = const ThreadContentParser(),
  });

  final ForumUrlResolver urls;
  final ThreadContentParser contentParser;

  List<ThreadReply> simpleThreadCards(dom.Document document) {
    final replies = <ThreadReply>[];
    for (final card in document.querySelectorAll('.card .card-body')) {
      final header = card.querySelector('h6');
      final cardText = card.querySelector('.card-text');
      final saleBoxesFirst = cardText != null && _startsWithSaleBox(cardText);
      final saleBoxes = cardText == null
          ? const <ThreadSaleBox>[]
          : _extractSaleBoxes(cardText);
      final quote =
          cardText == null ? null : contentParser.extractQuote(cardText);
      final images = const <ThreadImage>[];
      final links =
          cardText == null ? const <ThreadLink>[] : _extractLinks(cardText);
      final segments = cardText == null
          ? const <ThreadContentSegment>[]
          : contentParser.extractInlineSegments(cardText);
      final content = _cleanText(cardText?.text ?? '');
      if (header == null ||
          (content.isEmpty &&
              segments.isEmpty &&
              saleBoxes.isEmpty &&
              images.isEmpty &&
              links.isEmpty)) {
        continue;
      }

      final author = _cleanText(header.querySelector('strong')?.text ?? '匿名');
      final headerText = _cleanText(header.text);
      final floor =
          _cleanText(header.querySelector('.float-right')?.text ?? '');
      final dateMatch =
          RegExp(r'\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}').firstMatch(headerText);
      final postedAt = [
        if (dateMatch != null) dateMatch.group(0)!,
        if (floor.isNotEmpty) floor,
      ].join(' ');
      replies.add(
        ThreadReply(
          author: author,
          content: content,
          postedAt: postedAt.isEmpty ? null : postedAt,
          floor: floor.isEmpty ? null : floor,
          quote: quote,
          segments: segments,
          images: images,
          links: links,
          saleBoxes: saleBoxes,
          saleBoxesFirst: saleBoxesFirst,
        ),
      );
    }
    return replies;
  }

  List<ThreadReply> legacyReplies(dom.Document document) {
    return document
        .querySelectorAll('.reply')
        .map((reply) {
          final author = _cleanText(reply.querySelector('b')?.text ?? '匿名');
          final content =
              _cleanText(reply.querySelector('.content')?.text ?? reply.text);
          return ThreadReply(author: author, content: content);
        })
        .where((reply) => reply.content.isNotEmpty)
        .toList();
  }

  String bodyText(dom.Document document) {
    final candidates = [
      document.querySelector('.body'),
      document.querySelector('.content'),
      document.querySelector('main'),
    ];
    for (final candidate in candidates) {
      final text = _cleanText(candidate?.text ?? '');
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  List<ThreadLink> _extractLinks(dom.Element content) {
    final links = <ThreadLink>[];
    final seen = <String>{};
    for (final link in content.querySelectorAll('a[href]')) {
      final href = link.attributes['href'] ?? '';
      if (href.isEmpty ||
          href == '#' ||
          href.startsWith('javascript:') ||
          href.startsWith('mailto:')) {
        continue;
      }
      final url = urls.absoluteUrl(href);
      if (!seen.add(url)) continue;
      final label = _cleanText(link.text);
      links.add(ThreadLink(label: label.isEmpty ? url : label, url: url));
      if (links.length >= 20) break;
    }
    return links;
  }

  bool _startsWithSaleBox(dom.Element content) {
    for (final node in content.nodes) {
      if (node is dom.Text && _cleanText(node.text).isEmpty) continue;
      if (node is dom.Element) {
        if (node.localName == 'h6' &&
            node.classes.contains('quote') &&
            node.classes.contains('jumbotron')) {
          return true;
        }
        if (_cleanText(node.text).isEmpty) continue;
      }
      return false;
    }
    return false;
  }

  List<ThreadSaleBox> _extractSaleBoxes(dom.Element content) {
    final saleBoxes = <ThreadSaleBox>[];
    for (final saleElement in content.querySelectorAll('h6.quote.jumbotron')) {
      final input = saleElement.querySelector('input[type="button"]');
      final onclick = input?.attributes['onclick'] ?? '';
      final buyPath = _buyPathFromOnclick(onclick);
      if (buyPath == null) continue;

      final summary = _cleanText(
        saleElement.querySelector('.s3')?.text ?? saleElement.text,
      );
      final warningElement = _saleWarningElement(saleElement);
      final warning = _cleanText(warningElement?.text ?? '');
      final priceMatch = RegExp(r'售价\s*(\d+)\s*SP币').firstMatch(summary);
      final buyersMatch = RegExp(r'已有\s*(\d+)\s*人购买').firstMatch(summary);

      saleBoxes.add(
        ThreadSaleBox(
          summary: summary.isEmpty ? '此帖需要购买后查看' : summary,
          buyPath: buyPath,
          warning: warning.isEmpty ? null : warning,
          price: priceMatch == null ? null : int.tryParse(priceMatch.group(1)!),
          buyers:
              buyersMatch == null ? null : int.tryParse(buyersMatch.group(1)!),
        ),
      );

      saleElement.remove();
      warningElement?.remove();
    }
    return saleBoxes;
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

  String _cleanText(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
