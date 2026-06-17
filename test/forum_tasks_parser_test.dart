import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/parsers/forum_tasks_parser.dart';

void main() {
  const parser = ForumTasksParser();

  test('parses available daily and weekly tasks from real page structure', () {
    final document = html_parser.parse('''
      <table>
        <tr class="f_one">
          <td width="100" rowspan="2"><img src="weekly.png"></td>
          <td><b>周常</b>&nbsp;(人气 : 24965565)&nbsp;
            <font color="blue">任务时效2011-12-03~2028-12-31</font></td>
          <td>奖励 : SP币 7 G</td>
          <td><span id="p_14"><a onclick="startjob('14');" title="按这申请此任务"></a></span></td>
        </tr>
        <tr class="f_one"><td>无所事事的周常</td></tr>
        <tr class="f_one">
          <td width="100" rowspan="2"><img src="Nichijou.png"></td>
          <td><b>日常</b>&nbsp;(人气 : 84278697)&nbsp;
            <font color="blue">任务时效2011-12-03~2028-12-31</font></td>
          <td>奖励 : SP币 2 G</td>
          <td><span id="p_15"><a onclick="startjob('15');" title="按这申请此任务"></a></span></td>
        </tr>
        <tr class="f_one"><td>每日SP+2的日常。</td></tr>
      </table>
    ''');

    final tasks = parser.parse(document, ForumTaskStatus.available);

    expect(tasks, hasLength(2));
    expect(tasks.first.name, '周常');
    expect(tasks.first.id, '14');
    expect(tasks.first.reward, 'SP币 7 G');
    expect(tasks.first.description, '无所事事的周常');
    expect(tasks.last.name, '日常');
    expect(tasks.last.id, '15');
    expect(tasks.last.actionLabel, '按这申请此任务');
  });

  test('parses claimed reward completion time from completed tasks', () {
    final document = html_parser.parse('''
      <table>
        <tr>
          <td></td>
          <td><b>日常</b> (人气 : 84279264) 任务时效2011-12-03~2028-12-31</td>
          <td>奖励 : SP币 2 G</td>
          <td></td>
        </tr>
        <tr>
          <td>每日SP+2的日常。 <span>已完成 100 %</span>
          完成时间 2026-06-17 AM:11:37:46</td>
        </tr>
      </table>
    ''');

    final tasks = parser.parse(document, ForumTaskStatus.completed);

    expect(tasks, hasLength(1));
    expect(tasks.single.name, '日常');
    expect(tasks.single.status, ForumTaskStatus.completed);
    expect(tasks.single.reward, 'SP币 2 G');
    expect(tasks.single.progressPercent, 100);
    expect(tasks.single.completedAt, '2026-06-17 AM:11:37:46');
  });

  test('parses cooldown rows without treating them as runnable tasks', () {
    final document = html_parser.parse('''
      <table>
        <tr>
          <td><b>周常</b> (人气 : 24966409) 任务时效2011-12-03~2028-12-31</td>
          <td>奖励 : SP币 7 G 上次领取未超过 158 小时</td>
          <td></td>
        </tr>
        <tr><td>无所事事的周常</td></tr>
        <tr>
          <td><b>日常</b> (人气 : 84282953) 任务时效2011-12-03~2028-12-31</td>
          <td>奖励 : SP币 2 G 上次领取未超过 18 小时</td>
          <td></td>
        </tr>
        <tr><td>每日SP+2的日常。</td></tr>
      </table>
    ''');

    final tasks = parser.parse(document, ForumTaskStatus.available);

    expect(tasks, hasLength(2));
    expect(tasks.first.name, '周常');
    expect(tasks.first.reward, 'SP币 7 G');
    expect(tasks.first.cooldownRemaining, const Duration(hours: 158));
    expect(tasks.first.canRun, isFalse);
    expect(tasks.last.name, '日常');
    expect(tasks.last.reward, 'SP币 2 G');
    expect(tasks.last.cooldownRemaining, const Duration(hours: 18));
    expect(tasks.last.canRun, isFalse);
  });
}
