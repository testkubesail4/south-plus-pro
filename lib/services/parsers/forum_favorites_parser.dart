import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../models/forum_models.dart';
import '../forum_request_exception.dart';

class ForumFavoritesPage {
  ForumFavoritesPage({
    required this.collections,
    required this.verify,
    required this.createVerify,
    required this.complete,
    required Set<String> jobs,
    required Set<String> destinations,
  })  : jobs = Set.unmodifiable(jobs),
        destinations = Set.unmodifiable(destinations);

  final FavoriteCollections collections;
  final String verify;
  final String? createVerify;
  final bool complete;
  final Set<String> jobs;
  final Set<String> destinations;
}

class ForumFavoritesParser {
  const ForumFavoritesParser();

  ForumFavoritesPage parse(String html, Uri base, {String? categoryId}) {
    final document = html_parser.parse(html);
    final root = document.querySelector('#u-contentmain');
    if (root == null) {
      final message = rejection(html) ?? '无法读取收藏列表，请刷新重试';
      final login = document.querySelector('input[name="pwpwd"]') != null ||
          forumTextNeedsLogin(message);
      throw ForumRequestException(
          login
              ? ForumRequestKind.loginRequired
              : forumTextIsForbidden(message)
                  ? ForumRequestKind.forbidden
                  : forumTextIsRateLimited(message)
                      ? ForumRequestKind.rateLimited
                      : ForumRequestKind.server,
          login ? '请先登录后查看收藏' : message);
    }
    final categories = <FavoriteCategory>[];
    final ids = <String>{};
    for (final cell in document.querySelectorAll('td[id^="uf_"]')) {
      final id = cell.id.substring(3);
      if (id == 'all' || id == 'forum') continue;
      if (!_id(id) || !ids.add(id)) _invalid();
      final links = cell.querySelectorAll('a[href]');
      final labels =
          links.where((link) => link.attributes['title'] != '删除目录').toList();
      if (labels.length != 1 ||
          !_local(labels.single.attributes['href']!, base)) _invalid();
      final label = labels.single.text.trim();
      if (label.isEmpty || _controls(label)) _invalid();
      final deletes =
          links.where((link) => link.attributes['title'] == '删除目录').toList();
      if (deletes.length > 1) _invalid();
      final canDelete = id != '0' &&
          deletes.length == 1 &&
          _local(deletes.single.attributes['href']!, base) &&
          RegExp('^action(?:=|-)favor-job-deltype-type-$id-uid-[1-9]\\d*-verify-[A-Za-z0-9_-]+\\.html\$')
              .hasMatch(
                  base.resolve(deletes.single.attributes['href']!).query) &&
          RegExp(r'^\s*return\s+Checkinfo\(\)\s*;?\s*$')
              .hasMatch(deletes.single.attributes['onclick'] ?? '');
      categories
          .add(FavoriteCategory(id: id, label: label, canDelete: canDelete));
    }
    if (!ids.contains('0') || (categoryId != null && !ids.contains(categoryId)))
      _invalid();

    dom.Element? manage;
    dom.Element? create;
    for (final form in document.querySelectorAll('form')) {
      if (!_form(form, base)) continue;
      if (form.querySelector('input[name="job"][value="addtype"]') != null) {
        if (create != null) _invalid();
        create = form;
      } else if (form.querySelector('input[name="job"][value="change"]') !=
              null &&
          form.querySelector('input[name="job"][value="clear"]') != null &&
          identical(
              form.querySelector('.u-table'), root.querySelector('.u-table'))) {
        if (manage != null) _invalid();
        manage = form;
      }
    }
    if (manage == null || manage.querySelector('.u-table') == null) _invalid();
    final verify = _verify(manage);
    final select = manage.querySelector('select[name="type"]');
    if (select == null) _invalid();
    final options = select.querySelectorAll('option');
    final offered = options.map((o) => o.attributes['value'] ?? '').toSet();
    if (offered.length != options.length ||
        !ids.every(offered.contains) ||
        offered.any((id) => !ids.contains(id))) _invalid();

    final jobs = manage
        .querySelectorAll('input[name="job"]')
        .where((control) =>
            control.attributes['type']?.toLowerCase() == 'radio' &&
            _enabled(control))
        .map((control) => control.attributes['value'] ?? '')
        .toSet();
    final destinations = _enabled(select)
        ? options
            .where(_enabled)
            .map((option) => option.attributes['value'] ?? '')
            .toSet()
        : <String>{};
    final items = <FavoriteCollectionEntry>[];
    final rowIds = <String>{};
    for (final row in manage.querySelectorAll('.u-table tr')) {
      final link = row.querySelector('th > a[href^="read.php?tid-"]');
      final selections = row.querySelectorAll('input[name="selid[]"]');
      if (link == null) {
        if (selections.isNotEmpty) _invalid();
        continue;
      }
      if (selections.length != 1 ||
          selections.single.attributes['type']?.toLowerCase() != 'checkbox' ||
          !_enabled(selections.single)) _invalid();
      final id = selections.single.attributes['value'] ?? '';
      if (!_id(id) || id == '0' || !rowIds.add(id)) _invalid();
      final href = link.attributes['href']!;
      if (!_local(href, base, path: '/read.php')) _invalid();
      final tid = RegExp(r'^tid-([1-9]\d*)(?:-[^/]*)?\.html$')
          .firstMatch(base.resolve(href).query)
          ?.group(1);
      if (tid == null) _invalid();
      final author = row.querySelector('td > a[href^="u.php?uid-"]');
      final categoryCell = author?.parent?.nextElementSibling;
      if (categoryCell == null || categoryCell.localName != 'td') _invalid();
      final category = categoryCell.text.trim();
      final matches = categories.where((c) => c.label == category).toList();
      final source = category.isEmpty
          ? '0'
          : matches.length == 1
              ? matches.single.id
              : categoryId != null &&
                      categories
                          .any((c) => c.id == categoryId && c.label == category)
                  ? categoryId
                  : null;
      if (categoryId != null && source != categoryId) _invalid();
      final title = _clean(link.text);
      if (title.isEmpty) _invalid();
      final authorHref = author?.attributes['href'];
      items.add(FavoriteCollectionEntry(
        id: id,
        categoryId: source,
        thread: UserListItem(
            title: title,
            titleTruncated: title.endsWith('..'),
            url: base.resolve(href).toString(),
            threadId: tid,
            author: _clean(author?.text ?? ''),
            authorUrl: authorHref != null && _local(authorHref, base)
                ? base.resolve(authorHref).toString()
                : null),
      ));
    }
    final pagination = document.querySelector('.pages');
    final pager = document.querySelector('.pages li.pagesone');
    final pages = pager == null
        ? null
        : RegExp(r'Pages:\s*(\d+)[^/]*\/\s*(\d+)')
            .firstMatch(_clean(pager.text));
    final currentPage = int.tryParse(pages?.group(1) ?? '') ?? 1;
    final maxPage =
        pagination == null ? 1 : int.tryParse(pages?.group(2) ?? '');
    if (currentPage < 1 ||
        (maxPage != null && (maxPage < 1 || currentPage > maxPage))) _invalid();
    final complete = currentPage == 1 && maxPage == 1;
    final counted = categories.map((category) {
      final known = complete &&
          (categoryId == category.id ||
              (categoryId == null &&
                  items.every((item) => item.categoryId != null)));
      return FavoriteCategory(
          id: category.id,
          label: category.label,
          count: known
              ? items.where((item) => item.categoryId == category.id).length
              : null,
          canDelete: category.canDelete);
    }).toList();
    final name = create?.querySelector('input[name="type"]');
    final createJob = create
        ?.querySelector('input[type="hidden"][name="job"][value="addtype"]');
    final canCreate = name != null &&
        createJob != null &&
        _enabled(createJob) &&
        _enabled(name) &&
        (name.attributes['type'] ?? 'text').toLowerCase() == 'text' &&
        !name.attributes.containsKey('readonly');
    final maxLength = int.tryParse(name?.attributes['maxlength'] ?? '');
    return ForumFavoritesPage(
      collections: FavoriteCollections(
          categories: counted,
          items: items,
          categoryId: categoryId,
          canCreate: canCreate,
          nameMaxLength: maxLength != null && maxLength >= 0 ? maxLength : null,
          page: currentPage,
          pageCount: maxPage),
      verify: verify,
      createVerify: create == null ? null : _verify(create),
      complete: complete,
      jobs: jobs,
      destinations: destinations,
    );
  }

  String? rejection(String html) {
    final literal = RegExp(
            r'^\s*(?:<\?xml[^>]*\?>\s*)?<ajax>\s*<!\[CDATA\[(.*?)\]\]>\s*</ajax>\s*$',
            dotAll: true)
        .firstMatch(html)
        ?.group(1);
    final center =
        html_parser.parse(html).querySelector('#main .t .f_one center');
    if (literal == null && center == null) return null;
    final text = _clean(literal ?? center!.text);
    if (text.length > 240 || _controls(text) || text.contains(RegExp(r'[<>]')))
      return null;
    if (RegExp(
            r'^(?:非法请求|认证码错误|验证码错误|没有权限|权限不足|请先登录|您还没有登录|请求过于频繁|论坛设置:刷新不要快于)')
        .hasMatch(text)) {
      return text;
    }
    return null;
  }

  bool _form(dom.Element form, Uri base) {
    if (form.attributes['method']?.toLowerCase() != 'post') return false;
    final action = form.attributes['action'];
    if (action == null || !_local(action, base)) return false;
    final uri = base.resolve(action);
    final query = uri.queryParametersAll;
    return query.length == 1 &&
        query['action']?.length == 1 &&
        query['action']?.single == 'favor';
  }

  String _verify(dom.Element form) {
    final fields = form.querySelectorAll('input[type="hidden"][name="verify"]');
    if (fields.length != 1 || !_enabled(fields.single)) _invalid();
    final token = fields.single.attributes['value'] ?? '';
    if (token.isEmpty || RegExp(r'[\x00-\x20\x7f]').hasMatch(token)) _invalid();
    return token;
  }

  bool _enabled(dom.Element element) {
    if (element.attributes.containsKey('disabled')) return false;
    for (var parent = element.parent; parent != null; parent = parent.parent) {
      if (!parent.attributes.containsKey('disabled')) continue;
      if (parent.localName == 'optgroup' || parent.localName == 'select')
        return false;
      if (parent.localName != 'fieldset') continue;
      final legend = parent.children
          .where((child) => child.localName == 'legend')
          .firstOrNull;
      var inLegend = false;
      for (var current = element.parent;
          current != null;
          current = current.parent) {
        if (identical(current, legend)) {
          inLegend = true;
          break;
        }
        if (identical(current, parent)) break;
      }
      if (!inLegend) return false;
    }
    return true;
  }

  bool _local(String value, Uri base, {String path = '/u.php'}) {
    if (_controls(value) || value.contains('\\')) return false;
    final parsed = Uri.tryParse(value);
    if (parsed == null) return false;
    final uri = base.resolveUri(parsed);
    return {'http', 'https'}.contains(uri.scheme) &&
        uri.origin == base.origin &&
        uri.userInfo.isEmpty &&
        !uri.hasFragment &&
        uri.path == path;
  }

  bool _id(String value) => RegExp(r'^(?:0|[1-9]\d*)$').hasMatch(value);
  bool _controls(String value) => RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);
  String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();
  Never _invalid() => throw const ForumRequestException(
      ForumRequestKind.server, '收藏列表格式已更改，请刷新后重试');
}
