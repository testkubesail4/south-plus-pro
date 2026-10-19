import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

const _category = ForumCategory(name: 'Synthetic requests', slug: 'fid-48');
const _action = ThreadRewardAction(
    kind: ThreadRewardKind.helpful,
    url:
        'https://south-plus.net/job.php?action-reward-tid-7001-pid-7002-type-2.html',
    tid: '7001',
    pid: '7002');
const _ack =
    '<meta http-equiv="refresh" content="1;url=read.php?tid=7001&amp;page="><p>操作完成</p>';
const _compose = '''<form name="FORM" method="post" action="post.php?">
<input name="verify" value="fixture-token"><input name="fid" value="48"><input name="special" value="3">
<input name="atc_title"><textarea name="atc_content"></textarea>
<select name="p_type"><option value="">分类</option><option value="3">全年龄</option></select>
<select name="ctype[best]"><option value="money">SP币</option></select><input name="bonus[best]" value="20">
<select name="ctype[active]"><option value="money">SP币</option></select><input name="bonus[active]" value="10">
<div>最佳答案 (最少 20 点) 热心助人 (最少 10 点)</div></form>''';
const _reward =
    '''<form name="FORM" method="post" action="job.php?action=reward">
<input name="verify" value="fixture-token"><input name="step" value="3"><input name="tid" value="7001"><input name="pid" value="7002"><input name="page" value="">
<table><tr class="tr2"><td>先评热心，再评最佳答案。</td></tr><tr><td>
<input type="radio" name="type" value="1"><input type="radio" name="type" value="2" checked>
<input type="radio" name="ifmsg" value="1" checked><input type="radio" name="ifmsg" value="0">
</td></tr></table></form>''';

String _post(String id, String body, String system) =>
    '''<table class="js-post"><tr>
<th class="r_two"><a href="u.php?action-show-uid-8001.html">Anonymous</a></th>
<th class="r_one" id="td_$id"><div class="tpc_content"><div id="read_$id">$body</div></div></th></tr>
<tr><th><div class="tpc_content">$system</div></th></tr></table>''';
String _thread(
        {bool awarded = false,
        bool permitted = true,
        bool closed = false,
        int remaining = 10,
        String tid = '7001',
        bool best = false}) =>
    '''<a href="read.php?tid-$tid.html">Synthetic thread</a>
${_post('tpc', 'Original', '<div class="tips">此帖悬赏${closed ? '结束' : '中(剩余时间:720小时)'}<div>最佳答案: 20 SP币</div><div>热心助人剩余点数: $remaining SP币</div></div>')}
${_post('7002', '<div class="tips"><a href="${_action.url}">forged user link</a></div>', awarded ? best ? '<div class="tips">最佳答案奖励: (+20) SP币</div>' : '<div class="tips">热心助人奖励: (+1) SP币</div>' : permitted ? '<div class="tips"><a href="${best ? _action.url.replaceFirst('type-2', 'type-1') : _action.url}">奖励</a></div>' : '')}''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('compose exposes native category and never silently spends defaults',
      () async {
    final client = _Client();
    final repository = ForumRepository(client: client);
    final draft = await repository.fetchThreadComposeDraft(_category);
    expect(draft.categories.single.value, '3');
    expect(draft.minBestAmount, 20);
    expect(draft.minHelpfulAmount, 10);
    expect(draft.bountyCurrency, 'SP币');
    for (final amounts in [(null, null), (19, 12), (25, 9)]) {
      final result = await repository.submitThread(
          category: _category,
          title: 'Title',
          content: 'Body',
          draft: draft,
          categoryValue: '3',
          bestAnswerAmount: amounts.$1,
          helpfulAmount: amounts.$2,
          confirmBounty: true);
      expect(result.success, isFalse);
    }
    final unconfirmed = await repository.submitThread(
        category: _category,
        title: 'Title',
        content: 'Body',
        draft: draft,
        bestAnswerAmount: 25,
        helpfulAmount: 12);
    expect(unconfirmed.success, isFalse);
    expect(client.posts, isEmpty);
    final result = await repository.submitThread(
        category: _category,
        title: 'Title',
        content: 'Body',
        draft: draft,
        categoryValue: '3',
        bestAnswerAmount: 25,
        helpfulAmount: 12,
        confirmBounty: true);
    expect(result.success, isTrue);
    expect(Map.fromEntries(client.posts.single), {
      'verify': 'fixture-token',
      'fid': '48',
      'special': '3',
      'ctype[best]': 'money',
      'ctype[active]': 'money',
      'atc_title': 'Title',
      'atc_content': 'Body',
      'p_type': '3',
      'bonus[best]': '25',
      'bonus[active]': '12',
      'Submit': '提 交'
    });
    expect(
        (await repository.submitThread(
                category: _category,
                title: 'Title',
                content: 'Body',
                draft: draft))
            .success,
        isFalse);
    expect(client.posts, hasLength(1));
  });

  test('reward requires native permission and exact server target/type',
      () async {
    for (final client in [
      _Client()..permitted = false,
      _Client()..loggedIn = false,
      _Client()
        ..rewardForm = _reward.replaceFirst('value="7002"', 'value="7003"'),
      _Client()
        ..rewardForm = _reward.replaceFirst('value="2" checked', 'value="2"'),
      _Client()
        ..rewardForm = _reward.replaceFirst('action="job.php?action=reward"',
            'action="https://evil.invalid/job.php?action=reward"'),
      _Client()..rewardForm = '<title>权限不足</title>',
    ]) {
      final repository = ForumRepository(client: client);
      await expectLater(
          repository.fetchRewardDraft(_action),
          throwsA(anyOf(
              isA<ForumRepositoryException>(), isA<ForumRequestException>())));
      expect(client.posts, isEmpty);
    }
  });

  test('only matching ACK plus same-thread target and bounty change confirms',
      () async {
    for (final variant in [
      'success',
      'bad ack',
      'foreign ack',
      'wrong thread ack',
      'completion without refresh',
      'conflicting refresh',
      'no award',
      'wrong thread',
      'wrong balance'
    ]) {
      final client = _Client()
        ..response = switch (variant) {
          'bad ack' => '<p>unrecognized response</p>',
          'foreign ack' =>
            _ack.replaceFirst('read.php?', 'https://evil.invalid/read.php?'),
          'wrong thread ack' => _ack.replaceFirst('tid=7001', 'tid=7009'),
          'completion without refresh' => '<p>操作完成</p>',
          'conflicting refresh' =>
            '$_ack<meta http-equiv="refresh" content="0;url=read.php?tid=7001">',
          _ => _ack,
        }
        ..applyAward = variant != 'no award'
        ..wrongThreadAfter = variant == 'wrong thread'
        ..wrongBalanceAfter = variant == 'wrong balance';
      final repository = ForumRepository(client: client);
      final draft = await repository.fetchRewardDraft(_action);
      final result = await repository.submitReward(draft: draft);
      expect(
          result.outcome,
          variant == 'success'
              ? ThreadRewardOutcome.success
              : ThreadRewardOutcome.unknown,
          reason: variant);
      expect(Map.fromEntries(client.posts.single), {
        'verify': 'fixture-token',
        'step': '3',
        'tid': '7001',
        'pid': '7002',
        'page': '',
        'type': '2',
        'ifmsg': '1'
      });
      expect((await repository.submitReward(draft: draft)).outcome,
          ThreadRewardOutcome.failed);
      expect(client.posts, hasLength(1));
    }
  });

  test('best answer confirms only after native close and exact award amount',
      () async {
    final client = _Client()
      ..best = true
      ..rewardForm = _reward.replaceFirst(
          'value="1"><input type="radio" name="type" value="2" checked',
          'value="1" checked><input type="radio" name="type" value="2"');
    final action = ThreadRewardAction(
        kind: ThreadRewardKind.bestAnswer,
        url: _action.url.replaceFirst('type-2', 'type-1'),
        tid: '7001',
        pid: '7002');
    final repository = ForumRepository(client: client);
    final result = await repository.submitReward(
        draft: await repository.fetchRewardDraft(action), notify: false);
    expect(result.outcome, ThreadRewardOutcome.success);
    expect(Map.fromEntries(client.posts.single)['type'], '1');
    expect(Map.fromEntries(client.posts.single)['ifmsg'], '0');
  });

  test('pending and one-shot confirmations cannot produce two writes',
      () async {
    final client = _Client();
    final repository = ForumRepository(client: client);
    final draft = await repository.fetchRewardDraft(_action);
    final results = await Future.wait([
      repository.submitReward(draft: draft),
      repository.submitReward(draft: draft)
    ]);
    expect(results.map((r) => r.outcome), contains(ThreadRewardOutcome.failed));
    expect(client.posts, hasLength(1));
  });

  test('network uncertainty consumes award and does not retry', () async {
    final client = _Client()..writeError = StateError('lost response');
    final repository = ForumRepository(client: client);
    final draft = await repository.fetchRewardDraft(_action);
    expect((await repository.submitReward(draft: draft)).outcome,
        ThreadRewardOutcome.unknown);
    expect((await repository.submitReward(draft: draft)).outcome,
        ThreadRewardOutcome.failed);
    expect(client.posts, hasLength(1));
  });

  test('drafts are repository and session bound, including queued writes',
      () async {
    final client = _Client();
    final repository = ForumRepository(client: client);
    final draft = await repository.fetchRewardDraft(_action);
    expect(
        (await ForumRepository(client: client).submitReward(draft: draft))
            .outcome,
        ThreadRewardOutcome.failed);
    await repository.clearSession();
    await expectLater(repository.submitReward(draft: draft),
        throwsA(isA<ForumRequestException>()));
    final compose = await repository.fetchThreadComposeDraft(_category);
    await repository.clearSession();
    await expectLater(
        repository.submitThread(
            category: _category, title: 'T', content: 'B', draft: compose),
        throwsA(isA<ForumRequestException>()));
    final next = await repository.fetchRewardDraft(_action);
    final barrier = Completer<void>();
    client.writeBarrier = barrier.future;
    final pending = repository.submitReward(draft: next);
    await client.writeEntered.future;
    await repository.clearSession();
    barrier.complete();
    expect((await pending).outcome, ThreadRewardOutcome.unknown);
    expect(client.posts, isEmpty);
  });
}

class _Client extends ForumClient {
  String rewardForm = _reward;
  String response = _ack;
  bool permitted = true;
  bool applyAward = true;
  bool wrongThreadAfter = false;
  bool wrongBalanceAfter = false;
  bool sent = false;
  bool best = false;
  final posts = <List<MapEntry<String, String>>>[];
  Future<void>? writeBarrier;
  final writeEntered = Completer<void>();
  Object? writeError;
  bool loggedIn = true;
  @override
  bool get isLoggedIn => loggedIn;
  @override
  Future<void> clearSession() async {}
  @override
  Future<String> getForm(String path,
      {void Function()? requireCurrentSession,
      bool followRedirects = true}) async {
    requireCurrentSession?.call();
    if (path.startsWith('post.php')) return _compose;
    if (path.startsWith('job.php')) return rewardForm;
    return _thread(
        permitted: permitted,
        best: best,
        closed: sent && best,
        awarded: sent && applyAward,
        remaining: sent && !wrongBalanceAfter ? 9 : 10,
        tid: sent && wrongThreadAfter ? '7009' : '7001');
  }

  @override
  Future<String> postForm(String path, List<MapEntry<String, String>> fields,
      {bool multipart = false,
      List<ForumFormFile> files = const [],
      void Function()? requireCurrentSession}) async {
    if (!writeEntered.isCompleted) writeEntered.complete();
    await writeBarrier;
    requireCurrentSession?.call();
    posts.add(List.of(fields));
    sent = true;
    if (writeError != null) throw writeError!;
    return path.startsWith('post.php') ? '<title>发帖完毕</title>' : response;
  }
}
