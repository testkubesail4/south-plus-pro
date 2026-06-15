import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../models/forum_models.dart';
import '../forum_url_resolver.dart';

class ThreadImagePreviewParser {
  ThreadImagePreviewParser({ForumUrlResolver? urls})
      : urls = urls ?? ForumUrlResolver();

  static const maxImages = 24;
  static const maxHostPages = 6;
  static const maxDetailPages = 5;

  final ForumUrlResolver urls;

  ThreadImagePreview parse(dom.Document document, String threadUrl) {
    return parsePages([(document: document, url: threadUrl)]);
  }

  ThreadImagePreview parsePages(
    List<({dom.Document document, String url})> pages,
  ) {
    final candidates = <String>{};
    final hostPages = <String>{};
    final firstPage = pages.isEmpty ? null : pages.first;
    final firstDocument = firstPage?.document;
    final firstUrl = firstPage?.url ?? urls.baseUri.toString();
    final author =
        firstDocument == null ? null : _detectThreadAuthor(firstDocument);
    var scannedPosts = 0;
    var hasBuyBlock = false;

    for (final page in pages) {
      final posts = _collectAuthorPosts(page.document, author);
      for (final post in posts) {
        scannedPosts += 1;
        _collectImagesFromRoot(candidates, post.content, page.url);
        if (_hasBuyBlock(post.content)) hasBuyBlock = true;
        if (candidates.length >= maxImages) break;
      }
      if (candidates.length >= maxImages) break;
    }

    if (scannedPosts == 0 && firstDocument != null) {
      final firstContent = _firstPostContent(firstDocument);
      if (firstContent != null) {
        scannedPosts = 1;
        _collectImagesFromRoot(candidates, firstContent, firstUrl);
        hasBuyBlock = _hasBuyBlock(firstContent);
      }
    }

    if (scannedPosts == 0) {
      return const ThreadImagePreview(
        images: [],
        note: '未找到楼主发言',
      );
    }

    final normalized = _normalizeImageList(candidates);
    for (final url in normalized) {
      if (_isHostPageUrl(url)) {
        hostPages.add(url);
      }
    }

    final images = normalized
        .where((url) => !_isHostPageUrl(url))
        .take(maxImages)
        .map((url) => ThreadImage(url: url))
        .toList();
    final media = images
        .map((image) => ThreadPreviewMedia.image(url: image.url))
        .toList();

    return ThreadImagePreview(
      images: images,
      media: media,
      hostPages: hostPages.take(maxHostPages).toList(),
      hasBuyBlock: hasBuyBlock,
      note:
          media.isNotEmpty || hostPages.isNotEmpty ? null : '楼主发言未发现可预览图片',
    );
  }

  List<ThreadPreviewMedia> parseHostPageMedia(
    dom.Document document,
    String hostPageUrl,
  ) {
    final direct = _metaContent(document, "meta[property='og:image']") ??
        _metaContent(document, "meta[name='og:image']") ??
        _metaContent(document, "meta[name='twitter:image']") ??
        _metaContent(document, "meta[property='twitter:image']") ??
        _findFirstImageUrlInText(document.outerHtml, hostPageUrl);
    final absolute = _toAbsoluteUrl(direct, hostPageUrl);
    if (absolute == null ||
        !_isImageCandidate(absolute) ||
        _isBlockedImage(absolute)) {
      return const [];
    }
    return [
      ThreadPreviewMedia.image(
        url: _normalizeImageUrl(absolute),
        source: hostPageUrl,
      ),
    ];
  }

  List<ThreadImage> parseHostPage(dom.Document document, String hostPageUrl) {
    return parseHostPageMedia(document, hostPageUrl)
        .where((media) => media.type == ThreadPreviewMediaType.image)
        .map((media) => ThreadImage(url: media.url))
        .toList();
  }

  dom.Element? _firstPostContent(dom.Document document) {
    return document.querySelector('#read_tpc') ??
        document.querySelector('[id^="read_"]') ??
        document.querySelector('.tpc_content .f14') ??
        document.querySelector('.tpc_content');
  }

  _PostAuthor? _detectThreadAuthor(dom.Document document) {
    final firstContent = _firstPostContent(document);
    if (firstContent == null) return null;
    final firstPost = _findPostContainer(firstContent);
    return firstPost == null ? null : _extractPostAuthor(firstPost);
  }

  List<_PreviewPost> _collectAuthorPosts(
    dom.Document document,
    _PostAuthor? author,
  ) {
    final posts = <_PreviewPost>[];
    final seen = <dom.Element>{};
    final contents = document.querySelectorAll(
      '#read_tpc, [id^="read_"], .tpc_content .f14, .tpc_content',
    );

    for (final content in contents) {
      if (author == null && content.id != 'read_tpc') continue;

      final post = _findPostContainer(content);
      if (post == null || !seen.add(post)) continue;

      if (author == null || _sameAuthor(_extractPostAuthor(post), author)) {
        posts.add(_PreviewPost(content: content));
      }
    }
    return posts;
  }

  dom.Element? _findPostContainer(dom.Element content) {
    dom.Element? node = content;
    while (node != null) {
      if (node.localName == 'tr') return node;
      node = node.parent;
    }

    node = content;
    while (node != null) {
      if (node.localName == 'table') return node;
      node = node.parent;
    }

    return content.parent;
  }

  _PostAuthor? _extractPostAuthor(dom.Element post) {
    final profileLink = post.querySelector(
      'a[href^="u.php"], a[href*="/u.php"], a[href*="action-show-uid"], '
      'a[href*="uid-"], a[href*="uid="]',
    );
    final href = profileLink?.attributes['href'] ?? '';
    final uidMatch = RegExp(r'uid[-=](\d+)', caseSensitive: false)
            .firstMatch(href) ??
        RegExp(r'/u\.php\?(\d+)', caseSensitive: false).firstMatch(href);
    final uid = uidMatch?.group(1) ?? '';
    final name = _cleanText(profileLink?.text ?? '');

    if (uid.isEmpty && name.isEmpty) return null;
    return _PostAuthor(uid: uid, name: name);
  }

  bool _sameAuthor(_PostAuthor? left, _PostAuthor right) {
    if (left == null) return false;
    if (left.uid.isNotEmpty && right.uid.isNotEmpty) {
      return left.uid == right.uid;
    }
    if (left.name.isNotEmpty && right.name.isNotEmpty) {
      return left.name == right.name;
    }
    return false;
  }

  void _collectImagesFromRoot(
    Set<String> output,
    dom.Element root,
    String threadUrl,
  ) {
    for (final image in root.querySelectorAll('img')) {
      _addUrl(output, _imageLikeAttr(image), threadUrl);
      _addUrlsFromText(output, image.attributes['onclick'] ?? '', threadUrl);
      _addUrlsFromText(output, image.outerHtml, threadUrl);
    }

    for (final node in root.querySelectorAll('[style]')) {
      _addUrlsFromText(output, node.attributes['style'] ?? '', threadUrl);
    }

    for (final anchor in root.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'] ?? '';
      if (href.isEmpty || href.startsWith('javascript:')) continue;

      final absolute = _toAbsoluteUrl(href, threadUrl);
      if (absolute != null && _isImageCandidate(absolute)) {
        output.add(absolute);
      }

      _addUrlsFromText(output, anchor.text, threadUrl);
      _addUrlsFromText(output, anchor.attributes['title'] ?? '', threadUrl);
    }

    _addUrlsFromText(output, root.text, threadUrl);
  }

  List<String> _normalizeImageList(Set<String> urls) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in urls) {
      final normalized = _normalizeImageUrl(raw);
      if (normalized.isEmpty ||
          !_isImageCandidate(normalized) ||
          _isBlockedImage(normalized) ||
          !seen.add(normalized)) {
        continue;
      }
      result.add(normalized);
      if (result.length >= maxImages) break;
    }
    return result;
  }

  String _imageLikeAttr(dom.Element image) {
    for (final name in [
      'src',
      'data-src',
      'data-original',
      'data-url',
      'data-file',
      'ess-data',
      'zoomfile',
      'file',
    ]) {
      final value = image.attributes[name];
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  void _addUrl(Set<String> output, String raw, String baseUrl) {
    final absolute = _toAbsoluteUrl(raw, baseUrl);
    if (absolute != null) output.add(absolute);
  }

  void _addUrlsFromText(Set<String> output, String text, String baseUrl) {
    final urlPattern = RegExp(
      "(?:https?:)?//[^\\s<>\"'()]+|(?:attachment|upload)/[^\\s<>\"'()]+",
      caseSensitive: false,
    );
    for (final match in urlPattern.allMatches(text)) {
      final raw = _htmlDecode(match.group(0) ?? '')
          .replaceFirst(RegExp(r'[\),，。\.\]]+$'), '');
      final absolute = _toAbsoluteUrl(raw, baseUrl);
      if (absolute != null && _isImageCandidate(absolute)) {
        output.add(absolute);
      }
    }
  }

  String? _toAbsoluteUrl(String? raw, String baseUrl) {
    final cleaned = _htmlDecode(raw ?? '').trim();
    if (cleaned.isEmpty ||
        cleaned.startsWith(RegExp(r'data:', caseSensitive: false))) {
      return null;
    }
    if (cleaned.startsWith('//')) {
      final base = Uri.tryParse(baseUrl);
      return '${base?.scheme ?? urls.baseUri.scheme}:$cleaned';
    }
    final uri = Uri.tryParse(cleaned);
    if (uri != null && uri.hasScheme) return urls.absoluteUrl(cleaned);
    final base = Uri.tryParse(baseUrl) ?? urls.baseUri;
    return base.resolve(cleaned).toString();
  }

  String _normalizeImageUrl(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return '';
    return parsed.removeFragment().toString();
  }

  String? _metaContent(dom.Document document, String selector) {
    final value = document.querySelector(selector)?.attributes['content'];
    return value == null || value.isEmpty ? null : value;
  }

  String? _findFirstImageUrlInText(String text, String baseUrl) {
    final candidates = <String>{};
    _addUrlsFromText(candidates, text, baseUrl);
    for (final candidate in _normalizeImageList(candidates)) {
      if (!_isHostPageUrl(candidate)) return candidate;
    }
    return null;
  }

  String _htmlDecode(String value) {
    return html_parser.parseFragment(value).text ?? '';
  }

  String _cleanText(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _isImageCandidate(String url) {
    return _imageExtensionPattern.hasMatch(url) ||
        _attachmentPattern.hasMatch(url) ||
        _imageHostPattern.hasMatch(url);
  }

  bool _isHostPageUrl(String url) {
    return _hostPagePattern.hasMatch(url) &&
        !_imageExtensionPattern.hasMatch(url);
  }

  bool _isBlockedImage(String url) {
    return _emojiPattern.hasMatch(url) ||
        _emojiFilePattern.hasMatch(url) ||
        _avatarPattern.hasMatch(url);
  }

  bool _hasBuyBlock(dom.Element root) {
    if (_buyPattern.hasMatch(root.text)) return true;
    for (final node in root.querySelectorAll('input, button, a')) {
      final text = [
        node.attributes['value'],
        node.attributes['onclick'],
        node.attributes['href'],
        node.text,
      ].whereType<String>().join(' ');
      if (_buyPattern.hasMatch(text)) return true;
    }
    return false;
  }
}

final _imageHostPattern = RegExp(
  r'(catbox\.moe|gofile\.io|imgbox\.com|imgur\.com|i\.imgur\.com|postimg|postimages|pixhost|ibb\.co|imgbb|imagebam|imagevenue|freeimage|imgpile|lensdump|iili\.io|jpg\d?\.|pixeldrain|telegra\.ph|discord(?:app)?\.com/attachments|pbs\.twimg\.com|sinaimg|weibo|imoutolove|blue-plus|level-plus)',
  caseSensitive: false,
);
final _hostPagePattern = RegExp(
  r'(gofile\.io/d/|ibb\.co|imgbox\.com|imagebam\.com|imagevenue\.com|postimg\.cc|pixhost\.to|imgur\.com/(?!a/)|lensdump\.com/i/)',
  caseSensitive: false,
);
final _imageExtensionPattern = RegExp(
  r'\.(?:jpg|jpeg|png|webp|gif|bmp)(?:[?#].*)?$',
  caseSensitive: false,
);
final _attachmentPattern = RegExp(
  r'/(?:attachment|upload)/',
  caseSensitive: false,
);
final _emojiPattern = RegExp(
  r'/(?:smile|smallface|kaoani|post/smile|faces?|emot|emotion)/',
  caseSensitive: false,
);
final _emojiFilePattern = RegExp(
  r'/(?:face\d+|fly_\d+)\.(?:gif|jpg|jpeg|png|webp)$',
  caseSensitive: false,
);
final _avatarPattern = RegExp(r'/(?:avatar|face)/', caseSensitive: false);
final _buyPattern = RegExp(
  r'(buytopic|此帖售价|愿意购买|我买|我付钱|免费购买|隐藏内容|出售内容)',
  caseSensitive: false,
);

class _PreviewPost {
  const _PreviewPost({required this.content});

  final dom.Element content;
}

class _PostAuthor {
  const _PostAuthor({required this.uid, required this.name});

  final String uid;
  final String name;
}
