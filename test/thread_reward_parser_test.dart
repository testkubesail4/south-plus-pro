import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_url_resolver.dart';
import 'package:south_plus_rewrite/services/parsers/thread_detail_parser.dart';
import 'package:south_plus_rewrite/services/parsers/thread_reward_parser.dart';

void main() {
  test('only this post native sibling TH supplies ratings and rewards', () {
    const fake = '<div id="mark_1" class="tips"><li>HP:-999</li></div>';
    final document = html.parse('''<table class="js-post"><tr>
      <th class="r_two">Anonymous</th><th class="r_one" id="td_7002">
        <div class="tpc_content"><div id="read_7002">Body $fake
          <table><tr><th><div class="tpc_content">$fake</div></th></tr></table>
        </div></div></th></tr><tr><th><div class="tpc_content">
        <div id="mark_7002" class="tips"><li>SP币:+109</li><li>HP:-10</li></div>
        <div class="tips"><span>热心助人奖励</span>: (+1) SP币</div>
        <div class="tips">管理操作:<a href="job.php?action-reward-tid-7001-pid-7002-type-1.html">最佳答案</a>
          <a href="job.php?action-reward-tid-7001-pid-7003-type-2.html">wrong post</a></div>
      </div></th></tr></table>''');
    final reply = ThreadDetailParser().desktopThreadCards(document).single;
    expect(reply.ratings.map((r) => r.amount), [109, -10]);
    expect(reply.ratings.map((r) => r.currency), ['SP币', 'HP']);
    expect(reply.award?.kind, ThreadRewardKind.helpful);
    expect(reply.award?.amount, 1);
    expect(reply.rewardActions.single.pid, '7002');
  });

  test('native OP bounty keeps authoritative amounts and status', () {
    final parser = ThreadRewardParser(ForumUrlResolver());
    for (final (status, native, hours) in [
      (ForumBountyStatus.active, '中(剩余时间:720小时)', 720),
      (ForumBountyStatus.expired, '中(剩余时间:已结束)', null),
      (ForumBountyStatus.ended, '结束', null),
    ]) {
      final post = html.parse(
          '''<table class="js-post"><tr><th class="r_one"><div id="read_tpc">Body</div></th></tr>
      <tr><th><div class="tpc_content"><div class="tips">此帖悬赏$native
      <div>最佳答案: 20 SP币</div><div>热心助人剩余点数: 9 SP币</div></div></div></th></tr></table>''').querySelector('table')!;
      final bounty = parser.bounty(post)!;
      expect(bounty.status, status);
      expect(bounty.bestAmount, 20);
      expect(bounty.helpfulRemaining, 9);
      expect(bounty.remainingHours, hours);
    }
    expect(
        parser.action(
            'https://evil.invalid/job.php?action-reward-tid-1-pid-2-type-1.html'),
        isNull);
  });
}
