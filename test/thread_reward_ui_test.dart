import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/board/board_thread_list_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_compose_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_reward_view.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// Synthetic fixtures only: fictional tid, pids, uids and authors.
const _url = 'https://south-plus.net/read.php?tid-7.html';
const _board = ForumCategory(
  name: '询问',
  slug: 'f9',
  url: 'https://south-plus.net/thread.php?fid-9.html',
);

ThreadRewardAction _action(ThreadRewardKind kind, String pid) =>
    ThreadRewardAction(
      kind: kind,
      url: 'job.php?action-reward-tid-7-pid-$pid-type-'
          '${kind == ThreadRewardKind.bestAnswer ? 1 : 2}.html',
      tid: '7',
      pid: pid,
    );

class _Repo extends ForumRepository {
  _Repo({
    this.outcome = ThreadRewardOutcome.unknown,
    this.form,
    this.postResult = const ReplyResult(success: true, message: '主题已发布'),
  });

  final ThreadRewardOutcome outcome;
  final ReplyResult postResult;
  final ThreadComposeDraft? form;
  int detailLoads = 0;
  final drafts = <ThreadRewardAction>[];
  final sent = <(ThreadRewardDraft, bool)>[];
  final posts = <Map<String, Object?>>[];

  @override
  Future<ForumThreadPage> fetchBoardThreadPage(
    ForumCategory category, {
    int page = 1,
    ForumThreadOrder order = ForumThreadOrder.lastPost,
    ForumBoardFilter? filter,
  }) async {
    ForumThread row(int tid, ForumBounty? bounty) => ForumThread(
          title: '求物 $tid',
          url: 'read.php?tid-$tid.html',
          replies: 0,
          section: '询问',
          author: '楼主$tid',
          bounty: bounty,
        );
    return ForumThreadPage(
      currentPage: 1,
      totalPages: 1,
      threads: [
        row(
            1,
            const ForumBounty(
                amount: 310,
                status: ForumBountyStatus.active,
                source: ForumBountySource.native)),
        row(
            2,
            const ForumBounty(
                status: ForumBountyStatus.unknown,
                source: ForumBountySource.native)),
        row(3, null),
      ],
    );
  }

  @override
  Future<List<ForumSearchBoard>> fetchSearchBoards() async => const [];

  @override
  Future<ThreadReadPosition?> loadThreadReadPosition(ForumThread t) async =>
      null;

  @override
  Future<void> saveThreadReadPosition(
    ForumThread t,
    ThreadReadPosition p,
  ) async {}

  @override
  Future<ThreadDetail> fetchThreadDetail(
    ForumThread thread, {
    int page = 1,
  }) async {
    detailLoads++;
    return ThreadDetail(
      thread: thread.copyWith(title: '合成求物', author: '楼主甲'),
      body: 'opening body',
      bodyBounty: const ThreadBounty(
        status: ForumBountyStatus.active,
        text: '',
        remainingHours: 720,
        bestAmount: 20,
        helpfulRemaining: 10,
      ),
      bodyRatings: const [
        ThreadRating(currency: 'SP币', amount: 109, text: 'SP币:+109'),
        ThreadRating(currency: 'HP', amount: -10, text: 'HP:-10'),
      ],
      replies: [
        const ThreadReply(
          author: '路人乙',
          content: 'first answer',
          floor: 'B1F',
          award: ThreadAward(
            kind: ThreadRewardKind.helpful,
            amount: 1,
            text: '',
          ),
        ),
        ThreadReply(
          author: '路人丙',
          content: 'second answer',
          floor: 'B2F',
          rewardActions: [
            _action(ThreadRewardKind.bestAnswer, '102'),
            _action(ThreadRewardKind.helpful, '102'),
          ],
        ),
        ThreadReply(
          author: '路人丁',
          content: 'third answer',
          floor: 'B3F',
          rewardActions: [_action(ThreadRewardKind.bestAnswer, '103')],
        ),
      ],
    );
  }

  @override
  Future<ThreadRewardDraft> fetchRewardDraft(ThreadRewardAction action) async {
    drafts.add(action);
    return ThreadRewardDraft(
      action: action,
      controls: const [],
      actionPath: 'job.php?action=reward',
      notifyDefault: true,
    );
  }

  @override
  Future<ThreadRewardResult> submitReward({
    required ThreadRewardDraft draft,
    bool notify = true,
  }) async {
    sent.add((draft, notify));
    return ThreadRewardResult(outcome: outcome, message: '');
  }

  @override
  Future<ThreadComposeDraft> fetchThreadComposeDraft(
    ForumCategory category,
  ) async =>
      form ?? (throw StateError('offline'));

  @override
  Future<ReplyResult> submitThread({
    required ForumCategory category,
    required String title,
    required String content,
    bool enableReplyNotice = false,
    ThreadComposeDraft? draft,
    String? categoryValue,
    int? bestAnswerAmount,
    int? helpfulAmount,
    bool confirmBounty = false,
  }) async {
    posts.add({
      'draft': draft,
      'category': categoryValue,
      'best': bestAnswerAmount,
      'helpful': helpfulAmount,
      'confirm': confirmBounty,
    });
    return postResult;
  }
}

const _bountyForm = ThreadComposeDraft(
  categories: [
    ThreadComposeCategory(value: '1', label: '二次元'),
    ThreadComposeCategory(value: '3', label: '全年龄'),
  ],
  // The parser's shape for the native placeholder <option value="">.
  selectedCategory: '',
  bountySupported: true,
  controls: [],
  actionPath: 'post.php?',
  fid: '9',
  defaultBestAmount: 20,
  defaultHelpfulAmount: 10,
  minBestAmount: 20,
  minHelpfulAmount: 10,
  bountyCurrency: 'SP币',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('copy', () {
    test('a board row never claims an answer from a missing amount', () {
      ForumBounty b(ForumBountyStatus s, [int? amount]) => ForumBounty(
          status: s, amount: amount, source: ForumBountySource.native);
      expect(boardBountyLabel(null), isNull);
      expect(boardBountyLabel(b(ForumBountyStatus.active, 310)), '悬赏 310');
      expect(boardBountyLabel(b(ForumBountyStatus.active)), '悬赏中');
      expect(boardBountyLabel(b(ForumBountyStatus.unknown)), '悬赏帖');
      expect(boardBountyLabel(b(ForumBountyStatus.expired)), '悬赏已到期');
      expect(boardBountyLabel(b(ForumBountyStatus.ended)), '悬赏已结束');
    });

    test('best answer warns of the end and the automatic helpful split', () {
      const bounty = ThreadBounty(
        status: ForumBountyStatus.active,
        text: '',
        helpfulRemaining: 9,
      );
      final best =
          rewardConsequences(ThreadRewardKind.bestAnswer, bounty: bounty);
      expect(best.first, contains('结束悬赏'));
      expect(best.join(), contains('剩余 9 SP币'));
      expect(best.join(), contains('每楼 1 分自动发放'));
      expect(best.last, contains('先给热心助人'));
      final helpful = rewardConsequences(ThreadRewardKind.helpful);
      expect(helpful.join(), contains('不能再被选为最佳答案'));
      expect(helpful.join(), contains('无法撤销'));
    });

    test('a bounty charges the best answer twice plus the helpful pool', () {
      BountyInput input(int? best, int? helpful) => BountyInput(
            best: best,
            helpful: helpful,
            minBest: 20,
            minHelpful: 10,
            currency: 'SP币',
          );
      expect(input(20, 10).error, isNull);
      expect(input(20, 10).charge, 50);
      expect(input(25, 12).charge, 62);
      expect(input(25, 12).terms.join(), contains('选出最佳答案后退回 25'));
      expect(input(19, 10).error, '最佳答案悬赏至少 20');
      expect(input(20, 9).error, '热心助人悬赏至少 10');
      expect(input(null, 10).error, '请填写最佳答案悬赏');
      expect(input(20, null).error, '请填写热心助人悬赏');
    });
  });

  testWidgets('board rows show the native amount, and no answer claim',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: BoardThreadListScreen(category: _board, repository: _Repo()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('悬赏 310'), findsOneWidget);
    expect(find.text('悬赏帖 · 楼主2 · 0 回复'), findsOneWidget);
    expect(find.text('楼主3 · 0 回复'), findsOneWidget);
    expect(find.textContaining('答案'), findsNothing);
    expect(find.textContaining('已结束'), findsNothing);
  });

  Future<_Repo> pumpThread(
    WidgetTester tester, {
    ThreadRewardOutcome outcome = ThreadRewardOutcome.unknown,
  }) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo(outcome: outcome);
    await tester.pumpWidget(MaterialApp(
      home: ThreadDetailScreen(
        repository: repo,
        thread:
            const ForumThread(title: '', url: _url, replies: 0, section: ''),
      ),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('native bounty, ratings and awards read as the forum states',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpThread(tester);
    expect(find.text('悬赏中'), findsOneWidget);
    expect(find.text('剩余 720 小时'), findsOneWidget);
    expect(find.text('最佳答案 20 SP币'), findsOneWidget);
    expect(find.text('热心助人剩余 10 SP币'), findsOneWidget);
    expect(find.text('SP币 +109'), findsOneWidget);
    expect(find.text('HP -10'), findsOneWidget);
    expect(find.bySemanticsLabel('最近评分 SP币 +109，HP -10'), findsOneWidget);
    expect(find.text('热心助人 +1 SP币'), findsOneWidget);
    // Only the floor with native award links offers them.
    expect(find.byKey(const ValueKey('reward-best-102')), findsOneWidget);
    expect(find.text('选为最佳答案'), findsNWidgets(2));
    semantics.dispose();
  });

  testWidgets('cancelling an award sends nothing', (tester) async {
    final repo = await pumpThread(tester);
    await tester.tap(find.byKey(const ValueKey('reward-best-102')));
    await tester.pumpAndSettle();
    expect(find.text('选 B2F 为最佳答案？'), findsOneWidget);
    expect(find.textContaining('已提交过评选'), findsNothing,
        reason: 'nothing is sent while the author decides');
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('剩余 10 SP币'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repo.sent, isEmpty);
  });

  testWidgets('an unconfirmed award locks awards and offers a refresh',
      (tester) async {
    final repo = await pumpThread(tester);
    await tester.tap(find.byKey(const ValueKey('reward-helpful-102')));
    await tester.pumpAndSettle();
    expect(find.text('给 B2F 热心助人？'), findsOneWidget);
    await tester.tap(find.text('短消息通知对方'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认，不可撤销'));
    await tester.pumpAndSettle();

    expect(repo.sent, hasLength(1));
    expect(repo.sent.single.$1.action.kind, ThreadRewardKind.helpful);
    expect(repo.sent.single.$2, isFalse, reason: 'notify switched off');
    expect(find.text('结果未确认'), findsOneWidget);
    final other = find.byKey(const ValueKey('reward-best-103'));
    expect(tester.widget<OutlinedButton>(other).onPressed, isNull,
        reason: 'every award waits for the page to be read again');
    final loads = repo.detailLoads;
    await tester.tap(find.text('刷新'));
    await tester.pumpAndSettle();
    expect(repo.detailLoads, loads + 1);

    // The floor sent to stays locked even if the page still offers it; the
    // fresh page governs every other floor.
    final best = find.byKey(const ValueKey('reward-best-102'));
    expect(tester.widget<OutlinedButton>(best).onPressed, isNull);
    expect(find.textContaining('已提交过评选'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(other).onPressed, isNotNull);
  });

  testWidgets('a confirmed award reloads the page from the forum',
      (tester) async {
    final repo = await pumpThread(tester, outcome: ThreadRewardOutcome.success);
    final loads = repo.detailLoads;
    await tester.tap(find.byKey(const ValueKey('reward-best-102')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认，不可撤销'));
    await tester.pumpAndSettle();
    expect(repo.sent.single.$2, isTrue,
        reason: 'the forum notifies by default');
    expect(find.text('已选为最佳答案'), findsOneWidget);
    expect(repo.detailLoads, loads + 1);
  });

  Future<_Repo> pumpCompose(
    WidgetTester tester,
    ThreadComposeDraft? form, {
    ReplyResult postResult = const ReplyResult(success: true, message: '主题已发布'),
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo(form: form, postResult: postResult);
    await tester.pumpWidget(MaterialApp(
      home: ThreadComposeScreen(category: _board, repository: repo),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '求一个资源');
    await tester.enterText(
      find.widgetWithText(TextField, '正文'),
      '描述',
    );
    return repo;
  }

  testWidgets('a bounty thread states its charge and posts only once confirmed',
      (tester) async {
    final repo = await pumpCompose(tester, _bountyForm);
    expect(find.text('发布时预先扣除 50 SP币，其中 20 在选出最佳答案后退回'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('compose-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全年龄').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('compose-bounty-best')), '19');
    await tester.pump();
    expect(find.text('最佳答案悬赏至少 20'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('compose-submit')));
    await tester.pumpAndSettle();
    expect(repo.posts, isEmpty);

    await tester.enterText(
        find.byKey(const ValueKey('compose-bounty-best')), '25');
    await tester.enterText(
        find.byKey(const ValueKey('compose-bounty-helpful')), '12');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('compose-submit')));
    await tester.pumpAndSettle();
    expect(find.text('发布悬赏帖？'), findsOneWidget);
    expect(find.textContaining('最佳答案 25 × 2 = 50'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repo.posts, isEmpty);

    await tester.tap(find.byKey(const ValueKey('compose-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认发布并扣除 62 SP币'));
    await tester.pumpAndSettle();
    expect(repo.posts.single, {
      'draft': _bountyForm,
      'category': '3',
      'best': 25,
      'helpful': 12,
      'confirm': true,
    });
  });

  testWidgets('an unconfirmed post keeps the draft and never sends again',
      (tester) async {
    final repo = await pumpCompose(
      tester,
      _bountyForm,
      postResult: const ReplyResult(
        success: false,
        unconfirmed: true,
        message: 'ack missing',
      ),
    );
    await tester.tap(find.byKey(const ValueKey('compose-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认发布并扣除 50 SP币'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('compose-unconfirmed')), findsOneWidget);
    expect(find.textContaining('不要重复发布'), findsOneWidget);
    expect(find.text('ack missing'), findsNothing);
    final submit = find.byKey(const ValueKey('compose-submit'));
    expect(tester.widget<ButtonStyleButton>(submit).enabled, isFalse);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(repo.posts, hasLength(1));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('draft.thread.f9.title'), '求一个资源');
    expect(prefs.getString('draft.thread.f9.content'), '描述');
  });

  testWidgets('without the board form, a thread posts with no bounty claim',
      (tester) async {
    final repo = await pumpCompose(tester, null);
    expect(find.text('分类和悬赏设置加载失败'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('compose-submit')));
    await tester.pumpAndSettle();
    expect(repo.posts.single['confirm'], isFalse);
    expect(repo.posts.single['best'], isNull);
  });
}
