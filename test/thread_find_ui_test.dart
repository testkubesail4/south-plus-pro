import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_find.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_blocking_settings.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/full_scan.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';
import 'package:south_plus_rewrite/services/thread_search.dart';

// Synthetic fixtures only: fictional host, tid, pids, uids and authors.
const _url = 'https://south-plus.net/read.php?tid-7.html';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_Repo> pumpThread(WidgetTester tester, {_Repo? repository}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repository ??= _Repo();
    await tester.pumpWidget(MaterialApp(
      home: ThreadDetailScreen(
        repository: repository,
        thread: const ForumThread(
            title: 'find', url: _url, replies: 0, section: ''),
      ),
    ));
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> openFind(WidgetTester tester, String keyword) async {
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('帖内查找'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), keyword);
    await tester.pumpAndSettle();
  }

  Future<void> confirmScan(WidgetTester tester) async {
    await tester.tap(find.text('搜索全部页面'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始搜索'));
    await tester.pumpAndSettle();
  }

  testWidgets('帖内查找 finds loaded floors, scans on request and opens a hit',
      (tester) async {
    final repository = await pumpThread(tester);
    await openFind(tester, 'needle');
    expect(find.textContaining('第 1 页'), findsOneWidget);
    expect(find.text('搜索范围：已加载内容'), findsOneWidget);

    await confirmScan(tester);
    final scan = repository.scans.single;
    expect(scan.keyword, 'needle');
    scan.finish();
    await tester.pumpAndSettle();
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

  testWidgets('a hit on a repeated post opens the floor where it shows',
      (tester) async {
    await LoadingPreferences.load();
    await LoadingPreferences.save(LoadingDomain.thread, LoadingMode.continuous);
    final repository =
        await pumpThread(tester, repository: _Repo()..repeatPost = true);
    await tester.tap(find.text('加载第 2 页'));
    await tester.pumpAndSettle();
    // Page 2 adds nothing new, so page 3 follows on, then it pauses.
    final read = List.of(repository.pages);
    expect(read.take(2), [1, 2]);

    await openFind(tester, 'needle');
    await tester.tap(find.textContaining('第 2 页').last);
    await tester.pumpAndSettle();
    expect(repository.pages, read, reason: 'no page is read again');
    expect(find.text('未找到指定楼层，已显示所在页'), findsNothing);
    expect(
      find.textContaining('near needle', findRichText: true).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('the two modes say their cost; 全部页面 asks before any request',
      (tester) async {
    final repository = await pumpThread(tester);
    await openFind(tester, '');
    expect(find.text('仅已加载（1 页）'), findsOneWidget);
    expect(find.text('全部页面（3 页）'), findsOneWidget);
    expect(find.text('只查已加载的页面，不发送请求'), findsOneWidget);

    // Choosing it without a keyword only says what will happen.
    await tester.tap(find.text('全部页面（3 页）'));
    await tester.pumpAndSettle();
    expect(repository.scans, isEmpty);
    expect(find.text('逐页请求剩余 2 页，可随时停止，已找到的结果会保留'), findsOneWidget);
    expect(find.text('输入关键词后按搜索，确认后逐页读取剩余 2 页'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'needle');
    await tester.pumpAndSettle();
    expect(repository.scans, isEmpty, reason: 'typing never scans');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(repository.scans, isEmpty, reason: 'not before the confirmation');
    await tester.tap(find.text('开始搜索'));
    await tester.pumpAndSettle();
    final scan = repository.scans.single;
    expect(find.text('正在搜索全部页面'), findsOneWidget);

    // Back to the loaded pages: the scan stops and its results go.
    await tester.tap(find.text('仅已加载（1 页）'));
    await tester.pumpAndSettle();
    expect(scan.disposed, isTrue);
    expect(find.text('搜索范围：已加载内容'), findsOneWidget);
  });

  testWidgets(
      'a running scan goes on without the sheet and stops with the page',
      (tester) async {
    final repository = await pumpThread(tester);
    await openFind(tester, 'needle');
    await confirmScan(tester);
    final first = repository.scans.single;
    expect(find.text('正在搜索全部页面'), findsOneWidget);

    // Closing the sheet keeps the scan; its end is announced.
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();
    expect(first.disposed, isFalse);
    expect(first.stopped, isFalse);
    first.finish();
    await tester.pump();
    expect(find.text('帖内查找完成：找到 1 条'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));

    await openFind(tester, 'far');
    await confirmScan(tester);
    final second = repository.scans.last;
    expect(second, isNot(first));
    await tester.pumpWidget(const SizedBox());
    expect(second.disposed, isTrue);
  });

  testWidgets('another page over the thread pauses its scan, keeping 继续',
      (tester) async {
    final repository = await pumpThread(tester);
    await openFind(tester, 'needle');
    await confirmScan(tester);
    final scan = repository.scans.single;
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.byType(ThreadDetailScreen))).push(
      MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('another page'))),
    );
    await tester.pumpAndSettle();
    expect(scan.stopped, isTrue);
    expect(scan.disposed, isFalse);

    Navigator.of(tester.element(find.text('another page'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('帖内查找'));
    await tester.pumpAndSettle();
    expect(find.text('已停止，结果不完整'), findsOneWidget);
    expect(find.text('继续'), findsOneWidget);
    expect(find.text('返回已加载'), findsOneWidget);
    expect(repository.scans, hasLength(1), reason: 'never restarted by itself');
  });

  testWidgets('a page pushed over the open sheet and a dialog pauses the scan',
      (tester) async {
    final repository = await pumpThread(tester);
    await openFind(tester, 'needle');
    await confirmScan(tester);
    final scan = repository.scans.single;
    // Popups alone leave the thread on screen: the scan goes on.
    showDialog<void>(
      context: tester.element(find.byType(ThreadDetailScreen)),
      builder: (_) => const AlertDialog(content: Text('a dialog')),
    );
    await tester.pumpAndSettle();
    expect(scan.stopped, isFalse);

    // As an incoming forum link opens a page without closing popups.
    Navigator.of(tester.element(find.byType(ThreadDetailScreen))).push(
      MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('another page'))),
    );
    await tester.pumpAndSettle();
    expect(scan.stopped, isTrue);
    expect(scan.disposed, isFalse);
  });

  testWidgets('a scan confirmed after the session changed never starts',
      (tester) async {
    final repository = await pumpThread(tester);
    await openFind(tester, 'needle');
    await tester.tap(find.text('搜索全部页面'));
    await tester.pumpAndSettle();
    repository.session.value++;
    await tester.tap(find.text('开始搜索'));
    await tester.pumpAndSettle();
    expect(repository.scans, isEmpty);
    expect(find.text('搜索范围：已加载内容'), findsOneWidget);
  });

  testWidgets('a floor blocked while the sheet is open leaves its hits',
      (tester) async {
    final repository = await pumpThread(tester);
    await openFind(tester, 'needle');
    expect(find.textContaining('第 1 页'), findsOneWidget);

    repository.blocking.notifier.value = const BlockingRules(users: [
      BlockedUser(
          uid: '101', name: 'near', userBlocked: true, avatarBlocked: false),
    ]);
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1 页'), findsNothing);
    expect(find.text('已加载的 1 页中没有找到'), findsOneWidget);
  });

  testWidgets('a short window with the keyboard up and large text scrolls',
      (tester) async {
    tester.view.physicalSize = const Size(900, 360);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    addTearDown(tester.view.reset);
    final threadFind = ThreadFind(
      onScanEnded: (_) {},
      pages: () => const [],
      rules: () => const BlockingRules(),
    );
    addTearDown(threadFind.dispose);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            // As the thread screen opens it.
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              useSafeArea: true,
              constraints: const BoxConstraints(maxWidth: 640),
              builder: (_) => ThreadFindSheet(
                find: threadFind,
                authorFilterName: '该作者',
                createScan: () => throw UnimplementedError(),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('范围：只看 该作者'), 40,
        scrollable: find
            .ancestor(
                of: find.byType(TextField), matching: find.byType(Scrollable))
            .first);
    expect(find.text('范围：只看 该作者').hitTestable(), findsOneWidget);
  });

  testWidgets('pages read at different times count the most pages seen',
      (tester) async {
    ThreadDetail page(int number, int total) => ThreadDetail(
          thread: const ForumThread(
              title: 'find', url: _url, replies: 0, section: ''),
          body: '',
          pagination: ThreadPagination(currentPage: number, totalPages: total),
          replies: const [],
        );
    final threadFind = ThreadFind(
      onScanEnded: (_) {},
      pages: () => [page(1, 3), page(2, 2)],
      rules: () => const BlockingRules(),
    );
    addTearDown(threadFind.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ThreadFindSheet(
          find: threadFind,
          authorFilterName: null,
          createScan: () => throw UnimplementedError(),
        ),
      ),
    ));
    await tester.enterText(find.byType(TextField), 'needle');
    await tester.pumpAndSettle();
    // Page 3 was never read: nothing here may say the thread lacks it.
    expect(find.text('搜索全部页面'), findsOneWidget);
    expect(find.textContaining('本帖没有找到'), findsNothing);
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
    _progress = const ScanProgress(
        state: ScanState.running, scannedPages: 1, totalPages: 3);
    notifyListeners();
  }

  /// Ends the way a scan of all three pages would.
  void finish() {
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

  bool stopped = false;

  @override
  void stop() {
    stopped = true;
    _progress = const ScanProgress(
        state: ScanState.stopped,
        scannedPages: 1,
        totalPages: 3,
        canResume: true);
    notifyListeners();
  }

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
  final session = ValueNotifier<int>(0);
  // Page 2 repeats page 1's post, as when the thread moved while reading.
  bool repeatPost = false;

  @override
  ValueListenable<int> get sessionEpoch => session;

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
    if (repeatPost) page = 1;
    final shownPage = pages.last;
    final text = page == 1 ? 'near needle' : 'far needle';
    return ThreadDetail(
      thread: const ForumThread(
          title: 'find', url: _url, replies: 60, section: 'synthetic'),
      body: '',
      pagination: ThreadPagination(currentPage: shownPage, totalPages: 3),
      replies: [
        ThreadReply(
          postId: repeatPost ? '101' : null,
          author: page == 1 ? 'near' : 'far',
          authorUrl:
              'https://south-plus.net/u.php?action-show-uid-${page}01.html',
          content: text,
          floor: '${page * 20}F',
          segments: [ThreadContentSegment.text(text)],
          anchors: ['${page}01'],
        ),
      ],
    );
  }
}
