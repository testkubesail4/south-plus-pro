import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('thread header exposes its nearest board and a clean share destination',
      () async {
    final repository = ForumRepository(client: _HeaderClient('''
        <div id="breadcrumbs">
          <span class="crumbs-item"><img id="td_cate"></span>
          <a class="crumbs-item gray3" href="index.php"><i> </i>首页</a>
          <a class="crumbs-item gray3" href="thread.php?fid-901.html"><i> </i>Synthetic parent</a>
          <a class="crumbs-item gray3" href="thread.php?fid-902.html"><i> </i>Synthetic board</a>
          <span class="crumbs-item current"><i> </i><strong>
            <a href="read.php?tid-701.html">Synthetic thread</a></strong>
            <a href="rss.php?tid-701"><img></a></span>
        </div>
        <div id="breadcrumbs" style="margin-top:0px;">
          <a class="crumbs-item gray3" href="index.php"><i> </i>首页</a>
          <a class="crumbs-item gray3" href="thread.php?fid-902-page-0.html"><i> </i>Synthetic board</a>
          <div class="fr"><a class="abtn" id="readlog">Synthetic history</a></div>
        </div>
      '''));
    final detail = await repository.fetchThreadDetail(const ForumThread(
      title: 'Loading title',
      url: 'https://blue-plus.net/read.php?tid-701-uid-901-page-2.html#42',
      replies: 0,
      section: 'Latest feed',
    ));
    expect(detail.board?.name, 'Synthetic board');
    expect(detail.board?.slug, 'f902');
    expect(detail.board?.url, 'https://south-plus.net/thread.php?fid-902.html');
    expect(detail.thread.section, 'Synthetic board');
    expect(detail.thread.title, 'Synthetic thread');
    expect(repository.threadShareUrl(detail.thread),
        'https://south-plus.net/read.php?tid-701.html');
    expect(detail.thread.url, contains('uid-901'),
        reason: 'sharing must not change the current author filter');
  });

  test('an unnamed nearest board never falls back to its named parent',
      () async {
    for (final hasTitle in [true, false]) {
      for (final content in ['', '<a href="#"><i></i></a>Synthetic board']) {
        final repository = ForumRepository(client: _HeaderClient('''
          ${hasTitle ? '<title>Synthetic thread| Synthetic board - 南+ South Plus</title>' : ''}
          <div id="breadcrumbs">
            <a href="thread.php?fid-901.html">Synthetic parent</a>
            <a href="thread.php?fid-902.html">$content</a>
          </div>
        '''));
        final detail = await repository.fetchThreadDetail(const ForumThread(
          title: 'Synthetic thread',
          url: 'https://south-plus.net/read.php?tid-701.html',
          replies: 0,
          section: '',
        ));
        expect(detail.board?.slug, hasTitle ? 'f902' : null);
        expect(detail.board?.name, hasTitle ? 'Synthetic board' : null);
      }
    }
  });

  test('missing or untrusted board navigation stays unavailable', () async {
    for (final navigation in [
      '',
      '<div id="breadcrumbs"><a href="https://outside.invalid/thread.php?fid-902.html">Synthetic board</a></div>',
      '<div id="breadcrumbs"><a href="thread.php?fid-902-fid-903.html">Ambiguous board</a></div>',
    ]) {
      final repository = ForumRepository(client: _HeaderClient(navigation));
      final detail = await repository.fetchThreadDetail(const ForumThread(
        title: 'Synthetic thread',
        url: 'https://south-plus.net/read.php?tid-701.html',
        replies: 0,
        section: 'Latest feed',
      ));
      expect(detail.board, isNull);
      expect(repository.threadShareUrl(detail.thread),
          'https://south-plus.net/read.php?tid-701.html');
    }
    final repository = ForumRepository();
    expect(
      repository.threadShareUrl(const ForumThread(
        title: 'Synthetic',
        url: 'https://outside.invalid/read.php?tid-701.html',
        replies: 0,
        section: '',
      )),
      isNull,
    );
  });
}

class _HeaderClient extends ForumClient {
  _HeaderClient(this.navigation);
  final String navigation;

  @override
  Future<String> get(String path) async => '''
    <html><body>$navigation
      <span id="subject_tpc">Synthetic thread</span>
      <a href="read.php?tid-701.html">Synthetic thread</a>
      <table class="js-post"><tr>
        <th class="r_two"><strong>Synthetic author</strong></th>
        <th class="r_one"><div class="tiptop"><a class="s3">楼主</a></div>
          <div class="tpc_content"><div class="f14" id="read_tpc">
            Synthetic body <a href="thread.php?fid-999.html">Unrelated board</a>
          </div></div></th>
      </tr></table>
    </body></html>''';
}
