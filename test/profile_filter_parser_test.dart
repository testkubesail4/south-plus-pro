import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/models/user_content_query.dart';
import 'package:south_plus_rewrite/services/forum_url_resolver.dart';
import 'package:south_plus_rewrite/services/parsers/user_profile_parser.dart';

void main() {
  final parser = UserProfileParser(
      urls: ForumUrlResolver(baseUri: Uri.parse('https://south-plus.net/')));

  test('profile rows retain board and individual reply identities and paging',
      () {
    final page = parser.parseContentPage(html.parse('''
      <table class="u-table"><tr><td>
      <a href="job.php?action=topost&amp;tid=12&amp;pid=101">reply one..</a>
      <a href="thread.php?fid-48.html">board</a></td></tr><tr><td>
      <a href="job.php?action-topost-tid-12-pid-102.html">reply two</a>
      <a href="https://example.invalid/thread.php?fid-9.html">foreign</a>
      </td></tr></table><div class="pages">
      <a href="u.php?action-post-uid-7-page-60.html">last</a>
      <a href="u.php?action-post-uid-8-page-900.html">other user</a>
      <a href="https://example.invalid/u.php?action-post-uid-7-page-800.html">foreign</a>
      <a href="u.php?action-topic-uid-7-page-700.html">other tab</a></div>
      '''), uid: '7', tab: UserProfileTab.posts, page: 1);
    expect(page.totalPages, 60);
    expect(page.items.map((item) => item.postId), ['101', '102']);
    expect(page.items.map((item) => item.threadId), ['12', '12']);
    expect(page.items.first.boardId, '48');
    expect(page.items.first.titleTruncated, isTrue);
    expect(page.items.last.titleTruncated, isFalse);
    expect(page.items.every((item) => item.sourcePage == 1), isTrue);
    expect(page.items.first.boardUrl,
        'https://south-plus.net/thread.php?fid-48.html');
    expect(page.items.last.boardId, isNull);
  });

  test(
      'favorite content uses the main table, keeps truncation and real source pages',
      () {
    final page = parser.parseContentPage(html.parse('''
      <table class="u-table"><tr><td><a href="read.php?tid-999.html">sidebar</a></td></tr></table>
      <div id="u-contentmain"><table class="u-table"><tr><td>
      <a href="read.php?tid-12.html">cut..</a><a href="u.php?uid-88.html">author</a>
      </td></tr><tr><td><a href="https://external.invalid/read.php?tid-99.html">foreign</a></td></tr></table>
      <div class="pages">Pages: 2/3<a href="u.php?action-favor-uid-7-page-3.html">»</a></div></div>
      '''), uid: '7', tab: UserProfileTab.favorites, page: 2);
    expect(page.paginationKnown, isTrue);
    expect(page.totalPages, 3);
    expect(page.items.single.threadId, '12');
    expect(page.items.single.sourcePage, 2);
    expect(page.items.single.titleTruncated, isTrue);
  });

  test(
      'unconfirmed or contradictory pagination is not published as a complete tab',
      () {
    final uncertain = html.parse('''<div id="u-contentmain">
      <table class="u-table"><tr><td><a href="read.php?tid-12.html">title</a></td></tr></table>
      <div class="pages">unreadable</div></div>''');
    final bad = parser.parseContentPage(uncertain,
        uid: '7', tab: UserProfileTab.topics, page: 1);
    expect(bad.items, hasLength(1));
    expect(bad.paginationKnown, isFalse);
    final single = html.parse('<table class="u-table"></table>');
    final details = parser.appendDetails(
        overview:
            const UserProfile(uid: '7', name: 'user', url: 'u.php?uid-7.html'),
        homeDocument: html.parse(''),
        topicsDocument: uncertain,
        postsDocument: single,
        favoritesDocument: single);
    expect(
        details.contentPagination.containsKey(UserProfileTab.topics), isFalse);
    expect(details.contentPagination[UserProfileTab.posts]?.totalPages, 1);
    final wrongPage = parser.parseContentPage(
        html.parse('''<div id="u-contentmain">
      <table class="u-table"><tr><td><a href="read.php?tid-12.html">title</a></td></tr></table>
      <div class="pages">Pages: 1/3</div></div>'''),
        uid: '7',
        tab: UserProfileTab.topics,
        page: 2);
    expect(wrongPage.paginationKnown, isFalse);
    expect(wrongPage.items.single.sourcePage, 1);
  });

  test(
      'pager scope rejects explicit UID tab and type contradictions without requiring missing type markers',
      () {
    UserContentPage pageFor(List<String> links,
            {UserContentArticleType type = UserContentArticleType.sale}) =>
        parser.parseContentPage(
            html.parse('<div id="u-contentmain">'
                '<table class="u-table"><tr><td><a href="read.php?tid-12.html">title</a></td></tr></table>'
                '<div class="pages">Pages: 1/1${links.map((href) => '<a href="$href">last</a>').join()}</div></div>'),
            uid: '88',
            tab: UserProfileTab.topics,
            page: 1,
            articleType: type);
    const sale = 'u.php?action-topic-uid-88-type-sale-page-1.html';
    const missing = 'u.php?action-topic-uid-88-page-1.html';
    const poll = 'u.php?action-topic-uid-88-type-poll-page-1.html';
    for (final href in [
      poll,
      'u.php?action=topic&amp;uid=88&amp;type=poll&amp;page=1',
      'u.php?action-topic-uid-99-type-sale-page-1.html',
      'u.php?action-post-uid-88-type-sale-page-1.html',
      'https://external.invalid/u.php?action-topic-uid-88-type-sale-page-1.html'
    ]) {
      expect(pageFor([href]).paginationKnown, isFalse, reason: href);
    }
    expect(pageFor([missing]).paginationKnown, isTrue,
        reason:
            'missing type markers remain compatible, not invented evidence');
    expect(pageFor([sale, poll]).paginationKnown, isTrue);
    expect(pageFor([missing, poll]).paginationKnown, isFalse,
        reason: 'an untyped link cannot repair the only explicit type claim');
    expect(pageFor([sale], type: UserContentArticleType.all).paginationKnown,
        isFalse);
  });

  test('taxonomy admits only native classifications of the selected board', () {
    final filters = parser.parseContentClassifications(html.parse('''
      <div class="hthread"><div class="threadlist">
      <a href="thread.php?fid-48.html">all</a>
      <a href="thread.php?fid-48-search-digest.html">digest</a>
      <a href="thread.php?fid-48-type-1.html">二次元R18相关</a>
      <a href="thread.php?fid-48-type-2.html">三次元R18相关</a>
      <a href="thread.php?fid-9-type-3.html">wrong board</a>
      <a href="https://example.invalid/thread.php?fid-48-type-4.html">foreign</a>
      </div></div>
      '''), '48');
    expect(filters.map((item) => item.id), ['1', '2']);
    expect(filters.first.label, '二次元R18相关');
  });

  test('digest absence is known on native board rows, not on thread headers',
      () {
    final metadata = parser.parseContentBoardMetadata(html.parse('''
      <table id="ajaxtable">
      <tr class="tr3"><td><h3><a href="read.php?tid-12.html">digest</a></h3>
      <img src="images/colorImagination/file/digest_1.gif" title="精华帖标志"></td></tr>
      <tr class="tr3"><td><h3><a href="read.php?tid-13.html">ordinary</a></h3></td></tr>
      <tr class="tr3"><td><h3><a href="read.php?tid-14.html">global sticky</a></h3>
      <img src="images/colorImagination/file/headtopic_3.gif"></td></tr>
      </table>'''), boardId: '48', classifications: const []);
    expect(metadata['12']!.digest, isTrue);
    expect(metadata['13']!.digest, isFalse);
    expect(metadata.containsKey('14'), isFalse);
    expect(
        parser.parseContentThreadMetadata(
            html.parse('<h1 id="subject_tpc">digest</h1>'),
            classifications: const []).digest,
        isNull);
  });

  test('poll proof is native vote form, author UID is scoped to admitted OP',
      () {
    final document = html.parse('''
      <a href="u.php?action-show-uid-999.html">global user</a>
      <h1 id="subject_tpc">title</h1>
      <form action="job.php?action=vote"><input name="voteid[]" value="1">
      <input name="tid" value="12"></form>
      <h6 class="quote jumbotron">售价1 SP币</h6>
      <table class="js-post"><tr><th class="r_two">
      <a href="u.php?action-show-uid-88.html"><strong>OP</strong></a>
      </th><th class="r_one"><div id="read_tpc">body</div></th></tr></table>
      ''');
    final metadata = parser.parseContentThreadMetadata(document,
        classifications: const [], threadId: '12');
    expect(metadata.authorUid, '88');
    expect(metadata.poll, isTrue);
    expect(metadata.sale, isNull);
    expect(
        parser
            .parseContentThreadMetadata(document,
                classifications: const [], threadId: '13')
            .poll,
        isNull);
    document.querySelector('#read_tpc')!.attributes.remove('id');
    expect(
        parser.parseContentThreadMetadata(document,
            classifications: const []).authorUid,
        isNull);
  });

  test('classification uses authoritative header and known taxonomy only', () {
    const taxonomy = [
      UserContentClassification(id: '1', label: '二次元R18相关'),
    ];
    final document = html.parse('''
      <div id="breadcrumbs"><a href="thread.php?fid-48.html">board</a></div>
      <h1 id="subject_tpc">[二次元R18相关]求助黄油</h1>
      <div class="tpc_content">body text and [other] names are irrelevant</div>
      ''');
    final known = parser.parseContentThreadMetadata(document,
        classifications: taxonomy, profileTitle: '求助黄油');
    expect(known.boardId, '48');
    expect(known.boardName, 'board');
    expect(known.title, '[二次元R18相关]求助黄油');
    expect(known.classificationId, '1');
    expect(known.classificationKnown, isTrue);
    final unknown = parser.parseContentThreadMetadata(document,
        classifications: const [], profileTitle: '求助黄油');
    expect(unknown.classificationId, isNull);
    expect(unknown.classificationKnown, isFalse);
    expect(unknown.digest, isNull);
    for (final original in ['[二次元R18相关]求助黄油', '求助…', '求助...', 'different']) {
      final spoofed = parser.parseContentThreadMetadata(document,
          classifications: taxonomy, profileTitle: original);
      expect(spoofed.classificationKnown, isFalse);
    }
    expect(
        parser
            .parseContentThreadMetadata(html.parse('<h1>[二次元R18相关]fake</h1>'),
                classifications: taxonomy)
            .classificationKnown,
        isFalse);
  });
}
