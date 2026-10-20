import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_url_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'OP filter fallback uses verified identities and rejects foreign server links',
      () {
    final repository = ForumRepository();
    const thread = ForumThread(
        title: 'Fixture thread',
        url: 'https://blue-plus.net/read.php?tid-701.html',
        replies: 0,
        section: '',
        authorUrl: 'https://www.imoutolove.me/u.php?action-show-uid-901.html');
    expect(repository.originalPosterPostsUrl(thread),
        'https://south-plus.net/read.php?tid-701-uid-901.html');
    expect(
        repository.originalPosterPostsUrl(thread.copyWith(
            authorPostsUrl:
                'https://blue-plus.net/read.php?tid-701-uid-901-page-3.html')),
        'https://south-plus.net/read.php?tid-701-uid-901.html');
    expect(
        repository.originalPosterPostsUrl(thread.copyWith(
            authorPostsUrl:
                'https://blue-plus.net/read.php?tid-701-uid-902.html')),
        'https://south-plus.net/read.php?tid-701-uid-901.html');
    expect(
        repository.originalPosterPostsUrl(const ForumThread(
            title: 'Fixture',
            url: 'https://south-plus.net/read.php?tid-701.html',
            replies: 0,
            section: '',
            authorUrl: 'https://example.invalid/u.php?uid-901.html',
            authorPostsUrl:
                'https://example.invalid/read.php?tid-701-uid-901.html')),
        isNull);
    expect(
        repository.originalPosterPostsUrl(const ForumThread(
            title: 'Fixture',
            url: 'https://south-plus.net/read.php?tid-701.html',
            replies: 0,
            section: '',
            author: 'Fixture identity without URL')),
        isNull);
  });

  test('native sibling footers supply distinct OP and reply actions', () async {
    final client = _ThreadClient()
      ..response = '''<html><body>Pages: 1/1
      <span id="subject_tpc">Synthetic thread</span>
      <a href="read.php?tid-701.html">Synthetic thread</a>
      <table class="js-post"><tr>
        <th class="r_two"><a href="u.php?uid-901.html"><strong>Synthetic OP</strong></a></th>
        <th class="r_one"><div class="tiptop"><span class="fl"><a class="s3">楼主</a></span></div>
          <div class="tpc_content"><div class="f14" id="read_tpc">Synthetic opening body</div></div>
        </th></tr><tr><td><ul class="readbot">
          <li class="huifu"><a onclick="postreply('回 楼主(Synthetic OP) 的帖子');">回复</a></li>
          <li class="yinyong"><a href="post.php?action-quote-fid-2-tid-701-pid-tpc-article-0.html">引用</a></li>
        </ul></td></tr></table>
      <table class="js-post"><tr>
        <th class="r_two"><a href="u.php?uid-902.html"><strong>Synthetic reply</strong></a></th>
        <th class="r_one"><div class="tiptop"><span class="fl"><a class="s3">B1F</a></span></div>
          <div class="tpc_content"><div class="f14" id="read_42">Synthetic reply body</div></div>
        </th></tr><tr><td><ul class="readbot">
          <li class="huifu"><a onclick="postreply('回 1楼(Synthetic reply) 的帖子');">回复</a></li>
          <li class="yinyong"><a href="post.php?action-quote-fid-2-tid-701-pid-42-article-1.html">引用</a></li>
        </ul></td></tr></table>
      </body></html>''';
    final detail = await ForumRepository(client: client).fetchThreadDetail(
        const ForumThread(
            title: 'Synthetic',
            url: 'https://south-plus.net/read.php?tid-701.html',
            replies: 1,
            section: 'Synthetic'));
    expect(detail.bodyReplyTitle, '回 楼主(Synthetic OP) 的帖子');
    expect(detail.bodyQuoteUrl,
        'https://south-plus.net/post.php?action-quote-fid-2-tid-701-pid-tpc-article-0.html');
    expect(detail.bodyReplyUrl, isNull,
        reason: 'native reply uses its subject, not the quote URL');
    expect(detail.replies.single.replyTitle, '回 1楼(Synthetic reply) 的帖子');
    expect(detail.replies.single.quoteUrl,
        'https://south-plus.net/post.php?action-quote-fid-2-tid-701-pid-42-article-1.html');
    expect(detail.replies.single.replyUrl, isNull);
  });

  test(
      'filtered first rows never replace known OP identity or impersonate an opening post',
      () async {
    final client = _ThreadClient()
      ..response = _postPage('901', 'Fixture OP', '楼主', 'Fixture opening');
    final repository = ForumRepository(client: client);
    final original = await repository.fetchThreadDetail(const ForumThread(
        title: 'Fixture thread',
        url: 'https://south-plus.net/read.php?tid-701.html',
        replies: 0,
        section: ''));
    expect(original.thread.author, 'Fixture OP');
    expect(original.body, 'Fixture opening');
    expect(original.thread.authorUid, '901');
    expect(original.bodyReplyTitle, '回 楼主(Fixture OP) 的帖子');
    expect(
      original.bodyQuoteUrl,
      'https://south-plus.net/post.php?action-quote-fid-2-tid-701-pid-tpc-article-0.html',
    );
    client.response =
        _postPage('902', 'Fixture other author', 'B11F', 'Fixture other reply');
    final other = await repository.fetchThreadDetail(original.thread
        .copyWith(url: 'https://south-plus.net/read.php?tid-701-uid-902.html'));
    expect(other.thread.author, 'Fixture OP');
    expect(other.body, isEmpty);
    expect(other.replies.single.author, 'Fixture other author');
    expect(other.replies.single.floor, 'B11F');
    expect(repository.isOriginalPosterFilter(other.thread), false);
    expect(repository.originalPosterPostsUrl(other.thread),
        'https://south-plus.net/read.php?tid-701-uid-901.html');
    expect(repository.unfilteredThreadUrl(other.thread),
        'https://south-plus.net/read.php?tid-701.html');
    client.response =
        _postPage('901', 'Fixture OP', 'B12F', 'Fixture OP followup');
    final onlyOp = await repository.fetchThreadDetail(original.thread
        .copyWith(url: 'https://south-plus.net/read.php?tid-701-uid-901.html'));
    expect(repository.isOriginalPosterFilter(onlyOp.thread), true);
    expect(onlyOp.body, isEmpty,
        reason: 'first matched OP reply is not the opening floor');
    expect(onlyOp.replies.single.content, 'Fixture OP followup');
    client.response =
        _postPage('902', 'Fixture other author', 'B11F', 'Fixture other reply');
    final unknownOp = await repository.fetchThreadDetail(const ForumThread(
        title: 'Fixture thread',
        url: 'https://south-plus.net/read.php?tid-701-uid-902.html',
        replies: 0,
        section: ''));
    expect(unknownOp.thread.author, isNull);
    expect(repository.originalPosterPostsUrl(unknownOp.thread), isNull);
    expect(unknownOp.body, isEmpty);
    expect(unknownOp.replies.single.author, 'Fixture other author');
  });

  test(
      'native last-page fetch preserves anchor data and author filter on page and refresh',
      () async {
    final client = _ThreadClient();
    final repository = ForumRepository(client: client);
    final first = await repository.fetchThreadDetail(const ForumThread(
        title: 'Fixture thread',
        url: 'https://blue-plus.net/read.php?tid-701-uid-901-page-e.html#pid42',
        replies: 0,
        section: 'Fixture board'));
    expect(client.paths.first, 'read.php?tid-701-uid-901-page-e.html');
    expect(client.paths.last, 'read.php?tid-701.html');
    expect(first.pagination.currentPage, 2);
    expect(first.replies.single.anchors,
        containsAll(['pid42', 'read_42', 'fl-11']));
    expect(first.thread.url,
        'https://south-plus.net/read.php?tid-701-uid-901.html');
    await repository.fetchThreadDetail(first.thread, page: 2);
    await repository.fetchThreadDetail(first.thread, page: 2);
    expect(client.paths.where((path) => path.contains('uid-901')).skip(1), [
      'read.php?tid-701-uid-901-fpage-0-toread--page-2.html',
      'read.php?tid-701-uid-901-fpage-0-toread--page-2.html',
    ]);
    expect(client.paths.where((path) => !path.contains('uid-901')),
        everyElement('read.php?tid-701.html'));
  });
  final urls = ForumUrlResolver(baseUri: Uri.https('south-plus.net', '/'));
  test(
      'link targets normalize mirrors and preserve tab, location and safe external actions',
      () {
    final topic = urls.forumLinkTarget(
            'http://www.imoutolove.me/read.php?tid=701&page=3#42')
        as ForumThreadLinkTarget;
    expect(topic.url, 'https://south-plus.net/read.php?tid=701&page=3#42');
    final user =
        urls.forumLinkTarget('//blue-plus.net/u.php?action-topic-uid-901.html')
            as ForumUserLinkTarget;
    expect(user.tab, UserProfileTab.topics);
    expect(
        user.userUrl, 'https://south-plus.net/u.php?action-topic-uid-901.html');
    final friends = urls.forumLinkTarget('u.php?action-friend-uid-901.html')
        as ForumAppPageLinkTarget;
    expect(friends.page, ForumAppPage.friends);
    expect(friends.ownerUid, '901');
    final board = urls.forumLinkTarget('./thread_new.php?fid-42.html')
        as ForumBoardLinkTarget;
    expect(board.category.slug, 'f42');
    final mail = urls.forumLinkTarget('mailto:reader@example.invalid')
        as ForumExternalLinkTarget;
    expect(mail.url, 'mailto:reader@example.invalid');
    expect(
        urls.forumLinkTarget(
            'https://south-plus.net.example.invalid/read.php?tid-701.html'),
        isA<ForumExternalLinkTarget>());
    expect(urls.forumLinkTarget('//example.invalid/file'),
        isA<ForumExternalLinkTarget>());
    expect(urls.forumLinkTarget('magnet:?xt=urn:btih:fixture'),
        isA<ForumExternalLinkTarget>());
    expect(urls.forumLinkTarget('ed2k://|file|fixture|1|abc|/'),
        isA<ForumExternalLinkTarget>());
    for (final value in [
      'JaVaScRiPt:alert(1)',
      'file:///fixture',
      'data:image/png,fixture',
      'https://user:password@south-plus.net/read.php?tid-701.html',
      'mailto:reader@example.invalid?body=fixture',
      'mailto:reader@example.invalid%0aBcc:other@example.invalid',
      'message.php?action-del-towhere-receivebox-delids-701-verify-fixture.html',
      'login.php?action=quit',
      'login.php?action-%71uit.html',
      'message.php?%61ction-%64el-mid-701.html',
      'read.php?tid-701-tid-702.html',
      'read.php?tid=701&tid=702',
      'job.php?action=buytopic&tid=701',
    ]) {
      expect(urls.forumLinkTarget(value), isA<ForumBlockedLinkTarget>(),
          reason: value);
    }
  });
  test(
      'forum host aliases preserve DNS boundary and ignore case and trailing dot',
      () {
    expect(
        urls.forumLinkTarget(
            'https://BBS.BLUE-PLUS.NET./read.php?tid-701.html'),
        isA<ForumThreadLinkTarget>());
    for (final host in [
      'evil-south-plus.net',
      'south-plus.net.evil.invalid',
      'south-plus.net:444'
    ]) {
      expect(urls.forumLinkTarget('https://$host/read.php?tid-701.html'),
          isA<ForumExternalLinkTarget>());
    }
  });
  test('external query and fragment bytes survive resolver and absolute URL',
      () {
    const value = 'https://example.invalid/file?token=a%2Db#fixture%2Danchor';
    expect(urls.absoluteUrl(value), value);
    expect((urls.forumLinkTarget(value) as ForumExternalLinkTarget).url, value);
  });
  test(
      'SEO encoded hyphens remain data through mirror normalization and safe classification',
      () {
    const source =
        'https://blue-plus.net/search.php?keyword-foo%2Daction%2Dquit.html';
    final target = urls.forumLinkTarget(source);
    expect(target, isA<ForumPageLinkTarget>());
    expect((target as ForumPageLinkTarget).url,
        'https://south-plus.net/search.php?keyword-foo%2Daction%2Dquit.html');
    expect(urls.relativePath(urls.absoluteUrl(source)),
        'search.php?keyword-foo%2Daction%2Dquit.html');
    const thread =
        'https://blue-plus.net/read.php?tid-701-page-2.html#fixture%2Danchor';
    expect((urls.forumLinkTarget(thread) as ForumThreadLinkTarget).url,
        'https://south-plus.net/read.php?tid-701-page-2.html#fixture%2Danchor');
    expect(urls.relativePath(thread),
        'read.php?tid-701-page-2.html#fixture%2Danchor');
    expect(
        urls.threadDetailPath(
            'https://blue-plus.net/simple/index.php?t701_2.html#fixture%2Danchor'),
        'read.php?tid=701&fpage=0&toread=&page=2#fixture%2Danchor');
  });

  test(
      'resolver recognizes simple-page locations and never accepts foreign tid',
      () {
    expect(
        urls.threadDetailPath(
            'https://blue-plus.net/simple/index.php?t701_2.html#fixture'),
        'read.php?tid=701&fpage=0&toread=&page=2#fixture');
    expect(urls.tidFromUrl('https://example.invalid/read.php?tid-701.html'),
        isNull);
    expect(
        urls.tidFromUrl(
            'https://south-plus.net.example.invalid/read.php?tid-701.html'),
        isNull);
    expect(urls.tidFromUrl('javascript:read.php?tid-701.html'), isNull);
    expect(
        urls.tidFromUrl(
            'https://user:password@south-plus.net/read.php?tid-701.html'),
        isNull);
    expect(
        urls.threadDetailPath(
            'https://blue-plus.net/read.php?tid-701-page-3.html#fixture'),
        'read.php?tid-701-page-3.html#fixture');
  });
}

String _postPage(String uid, String name, String floor, String body) =>
    '''<html><body>Pages: 1/1
  <span id="subject_tpc">Fixture thread</span><a href="read.php?tid-701.html">Fixture thread</a>
  <table class="js-post"><tr><th class="r_two"><a href="u.php?action-show-uid-$uid.html"><strong>$name</strong></a></th>
    <th class="r_one" id="td_42"><div class="tiptop"><span class="fl"><a class="s3">$floor</a></span>
      <a href="read.php?tid-701-uid-$uid.html">只看该作者</a>
      <a onclick="postreply('回 $floor($name) 的帖子');">回复</a>
      <a href="post.php?action-quote-fid-2-tid-701-pid-tpc-article-0.html">引用</a></div>
      <div class="tpc_content"><div class="f14" id="read_42">$body</div></div>
    </th></tr></table></body></html>''';

class _ThreadClient extends ForumClient {
  String? response;
  final paths = <String>[];
  @override
  Future<String> get(String path) async {
    paths.add(path);
    return response ??
        '''<html><body><div class="pages">Pages: 2/2</div>
      <a href="read.php?tid-701.html">Fixture canonical</a>
      <a name="pid42"></a><table class="js-post"><tr>
        <th class="r_two"><a href="u.php?uid-901.html"><strong>Fixture author</strong></a></th>
        <th class="r_one"><div class="tiptop"><span class="fl"><a class="s3">B11F</a></span></div>
          <div class="tpc_content"><div class="f14" id="read_42">Fixture reply</div></div>
        </th></tr></table></body></html>''';
  }
}
