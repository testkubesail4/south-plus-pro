import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final explicit in [false, true]) {
    test(
        'page2 (explicit URL: $explicit) keeps OP metadata without body or images',
        () async {
      final client = _NativeClient();
      final detail = await ForumRepository(client: client).fetchThreadDetail(
          ForumThread(
              title: 'Loading',
              url: explicit
                  ? 'read.php?tid-7001-fpage-0-toread--page-2.html'
                  : 'read.php?tid-7001.html',
              replies: 1,
              section: ''),
          page: explicit ? 1 : 2);
      expect(detail.thread.authorUid, '8001');
      expect(detail.bodyPostedAt, '2026-01-01 12:34');
      expect(detail.personalSignature, 'Synthetic signature');
      expect(detail.body, isEmpty);
      expect(detail.bodySegments, isEmpty);
      expect(detail.bodyImages, isEmpty);
      expect(detail.replies.single.authorUid, '8002');
      expect(client.paths.where((p) => p == 'read.php?tid-7001.html'),
          hasLength(1));
    });
  }

  test('OP metadata failure leaves requested page readable', () async {
    final detail =
        await ForumRepository(client: _NativeClient()..openingFailure = true)
            .fetchThreadDetail(
                const ForumThread(
                    title: 'Loading',
                    url: 'read.php?tid-7001.html',
                    replies: 1,
                    section: ''),
                page: 2);
    expect(detail.bodyPostedAt, isNull);
    expect(detail.personalSignature, isNull);
    expect(detail.thread.authorUid, isNull);
    expect(detail.replies, hasLength(1));
  });

  test('request board enriches once from matching classic page not user title',
      () async {
    final client = _NativeClient();
    final page = await ForumRepository(client: client).fetchBoardThreadPage(
        const ForumCategory(name: 'Requests', slug: 'fid-48'),
        page: 2,
        order: ForumThreadOrder.hits,
        filter: const ForumBoardFilter(
            label: 'Type',
            kind: ForumBoardFilterKind.topicType,
            url: 'thread.php?fid-48-type-3.html'));
    expect(client.paths, [
      'thread_new.php?fid-48-type-3-orderway-hits-asc-DESC-page-2.html',
      'thread.php?fid-48-type-3-orderway-hits-asc-DESC-page-2.html'
    ]);
    expect(page.threads[0].bounty?.amount, 30);
    expect(page.threads[0].bounty?.source, ForumBountySource.native);
    expect(page.threads[1].bounty?.status, ForumBountyStatus.unknown);
    expect(page.threads[1].bounty?.amount, isNull);
    expect(page.threads[2].bounty, isNull);
    expect(page.threads[0].title, 'Title promises 999SP');
  });

  test('optional classic failure and other boards never invent bounty',
      () async {
    for (final fid in ['48', '49']) {
      final client = _NativeClient()..classicFailure = true;
      final page = await ForumRepository(client: client)
          .fetchBoardThreadPage(ForumCategory(name: 'Board', slug: 'fid-$fid'));
      expect(page.threads.every((t) => t.bounty == null), isTrue);
      expect(client.paths.length, fid == '48' ? 2 : 1);
    }
  });
}

String _post(String id, String uid) =>
    '''<table class="js-post"><tr><th class="r_two"><a href="u.php?action-show-uid-$uid.html">Anonymous</a></th>
<th class="r_one" id="td_$id"><div class="tiptop"><span class="fl"><a class="s3">${id == 'tpc' ? 'GF' : 'B31F'}</a></span><span class="gray">2026-01-01 12:34</span><div class="bianji">（Synthetic signature）</div></div>
<div class="tpc_content"><div id="read_$id">Synthetic body<img src="https://example.invalid/picture.png"></div></div></th></tr></table>''';

class _NativeClient extends ForumClient {
  final paths = <String>[];
  bool openingFailure = false;
  bool classicFailure = false;
  @override
  Future<String> getOnce(String path) => get(path);
  @override
  Future<String> get(String path) async {
    paths.add(path);
    if (path.startsWith('thread_new.php'))
      return '''<ul class="stream">${[
        7001,
        7002,
        7003
      ].map((id) => '<li class="dcsns-li"><div class="section-title"><a href="read.php?tid-$id.html">Title promises 999SP</a></div></li>').join()}</ul>''';
    if (path.startsWith('thread.php')) {
      if (classicFailure) throw StateError('optional source unavailable');
      return '''<table id="ajaxtable"><tr class="tr3"><td><h3><span class="s1"> — 悬赏金额：30 — </span><a href="read.php?tid-7001.html">Different title</a></h3></td></tr>
      <tr class="tr3"><td><img src="images/thread/reward.gif"><h3><a href="read.php?tid-7002.html">Bounty marker</a></h3></td></tr>
      <tr class="tr3"><td><h3><a href="read.php?tid-7003.html">10000 SP title is user content</a></h3></td></tr></table>''';
    }
    if (path.contains('page-2'))
      return '<a href="read.php?tid-7001.html">Thread</a><div class="pages">Pages: 2/2</div>${_post('7002', '8002')}';
    if (openingFailure) throw StateError('opening unavailable');
    return '<a href="read.php?tid-7001.html">Thread</a><div class="pages">Pages: 1/2</div>${_post('tpc', '8001')}';
  }
}
