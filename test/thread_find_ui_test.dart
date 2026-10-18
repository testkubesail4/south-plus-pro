import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_blocking_settings.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/full_scan.dart';
import 'package:south_plus_rewrite/services/thread_search.dart';

// Synthetic fixtures only: fictional host, tid, pids and authors.
const _url = 'https://south-plus.net/read.php?tid-7.html';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('帖内查找 finds loaded floors, scans on request and opens a hit',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _Repo();
    await tester.pumpWidget(MaterialApp(
      home: ThreadDetailScreen(
        repository: repository,
        thread: const ForumThread(
            title: 'find', url: _url, replies: 0, section: ''),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('帖内查找'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'needle');
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1 页'), findsOneWidget);
    expect(find.text('搜索范围：已加载内容'), findsOneWidget);

    await tester.tap(find.text('搜索全部页面'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始搜索'));
    await tester.pumpAndSettle();
    final scan = repository.scans.single;
    expect(scan.keyword, 'needle');
    expect(find.text('已搜索全部页面'), findsOneWidget);

    await tester.tap(find.textContaining('第 3 页'));
    await tester.pumpAndSettle();
    expect(repository.pages, [1, 3]);
    expect(
      find.textContaining('far needle', findRichText: true).hitTestable(),
      findsWidgets,
    );

    // The scan outlives the sheet; a new keyword drops it.
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('帖内查找'));
    await tester.pumpAndSettle();
    expect(find.text('已搜索全部页面'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'needles');
    await tester.pumpAndSettle();
    expect(scan.disposed, isTrue);
    expect(find.text('搜索范围：已加载内容'), findsOneWidget);
  });
}

class _Scan extends FullScan<ThreadSearchHit> {
  _Scan(this.keyword);

  final String keyword;
  bool disposed = false;
  ScanProgress _progress = const ScanProgress(totalPages: 3);
  List<ThreadSearchHit> _hits = const [];

  @override
  ScanProgress get progress => _progress;
  @override
  List<ThreadSearchHit> get hits => _hits;
  @override
  List<ThreadSearchHit> get unresolved => const [];

  @override
  void start() {
    _hits = const [
      ThreadSearchHit(
          page: 3,
          anchor: '301',
          floorLabel: '61 楼',
          author: 'far',
          snippet: 'far needle'),
    ];
    _progress = const ScanProgress(
        state: ScanState.done, scannedPages: 3, totalPages: 3, found: 1);
    notifyListeners();
  }

  @override
  void stop() {}
  @override
  void resume() {}

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _Repo extends ForumRepository {
  final pages = <int>[];
  final scans = <_Scan>[];

  @override
  FullScan<ThreadSearchHit> scanThread(
    ForumThread current,
    String keyword, {
    required List<ThreadDetail> loaded,
    required BlockingRules rules,
  }) {
    final scan = _Scan(keyword);
    scans.add(scan);
    return scan;
  }

  @override
  Future<ThreadDetail> fetchThreadDetail(ForumThread thread,
      {int page = 1}) async {
    pages.add(page);
    final text = page == 1 ? 'near needle' : 'far needle';
    return ThreadDetail(
      thread: const ForumThread(
          title: 'find', url: _url, replies: 60, section: 'synthetic'),
      body: '',
      pagination: ThreadPagination(currentPage: page, totalPages: 3),
      replies: [
        ThreadReply(
          author: page == 1 ? 'near' : 'far',
          content: text,
          floor: '${page * 20}F',
          segments: [ThreadContentSegment.text(text)],
          anchors: ['${page}01'],
        ),
      ],
    );
  }
}
