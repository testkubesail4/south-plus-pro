import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('fetchLoginChallenge accepts action-based login forms', () async {
    final client = _FakeForumClient('''
      <html>
        <body>
          <form action="login.php">
            <input type="hidden" name="step" value="2">
            <input type="hidden" name="cktime" value="31536000">
            <input name="pwuser" value="">
            <input type="password" name="pwpwd" value="">
            <input name="gdcode" value="">
            <img src="ck.php?foo=1">
          </form>
        </body>
      </html>
    ''');
    final repository = ForumRepository(client: client);

    final challenge = await repository.fetchLoginChallenge();

    expect(challenge, isA<LoginChallenge>());
    expect(challenge.fields, {
      'step': '2',
      'cktime': '31536000',
    });
    expect(client.bytesPath, startsWith('ck.php?foo=1&nowtime='));
  });

  test('fetchLoginChallenge accepts login forms identified by fields',
      () async {
    final client = _FakeForumClient('''
      <html>
        <body>
          <form action="member.php">
            <input type="hidden" name="lgt" value="0">
            <input name="pwuser">
            <input type="password" name="pwpwd">
            <input name="gdcode">
            <img id="ckcode" src="/ck.php">
          </form>
        </body>
      </html>
    ''');
    final repository = ForumRepository(client: client);

    final challenge = await repository.fetchLoginChallenge();

    expect(challenge.fields, {'lgt': '0'});
    expect(client.bytesPath, startsWith('ck.php?nowtime='));
  });

  test('fetchBoardThreadPage carries desktop sub boards with simple threads',
      () async {
    final client = _PathForumClient({
      'simple/index.php?f218.html': '''
        <html>
          <body>
            <ul class="threadlist">
              <li>
                <a href="?t1.html">父版公告<span class="by">论坛公告</span></a>
                <span class="num">0</span>
              </li>
            </ul>
            <ul class="pagination"><li class="active"><b>1</b></li></ul>
          </body>
        </html>
      ''',
      'thread.php?fid-218.html': '''
        <html>
          <body>
            <table>
              <tr><td class="h" colspan="5"><b>子版块</b></td></tr>
              <tr class="tr2">
                <td></td><td>论坛</td><td>版主</td><td>文章</td><td>最后发表</td>
              </tr>
              <tr class="f_one tr3">
                <td><a href="thread.php?fid-213.html"><img src="old.gif"></a></td>
                <th>
                  <a class="bklogo" href="thread.php?fid-213.html"></a>
                  <h2>
                    <a href="thread.php?fid-213.html" class="fnamecolor a1">
                      <b>同人志&CG</b>
                    </a>
                  </h2>
                </th>
                <td></td><td>26246</td><th></th>
              </tr>
            </table>
          </body>
        </html>
      ''',
    });
    final repository = ForumRepository(client: client);

    final page = await repository.fetchBoardThreadPage(
      const ForumCategory(
        name: 'C103',
        slug: 'fid-218',
        url: 'https://south-plus.net/thread.php?fid-218.html',
      ),
    );

    expect(client.paths, [
      'simple/index.php?f218.html',
      'thread.php?fid-218.html',
    ]);
    expect(page.subBoards.map((board) => board.name), ['同人志&CG']);
  });

  test('claimForumTaskRewards applies tasks before claiming rewards', () async {
    final client = _PathForumClient({
      'plugin.php?H_name=tasks&action=ajax&actions=job&cid=14': [
        'success\t任务领取完成',
        'success\t任务奖励领取完成',
      ],
      'plugin.php?H_name=tasks&action=ajax&actions=job&cid=15': [
        'success\t任务领取完成',
        'success\t任务奖励领取完成',
      ],
      'plugin.php?H_name-tasks-actions-newtasks.html.html': [
        '''
          <table>
            <tr>
              <td><b>周常</b> (人气 : 24965565) 任务时效2011-12-03~2028-12-31</td>
              <td>奖励 : SP币 7 G</td>
              <td><span id="p_14"><a onclick="startjob('14');" title="领取此奖励"></a></span></td>
            </tr>
            <tr><td>无所事事的周常 <span>已完成 100 %</span></td></tr>
            <tr>
              <td><b>日常</b> (人气 : 84278697) 任务时效2011-12-03~2028-12-31</td>
              <td>奖励 : SP币 2 G</td>
              <td><span id="p_15"><a onclick="startjob('15');" title="领取此奖励"></a></span></td>
            </tr>
            <tr><td>每日SP+2的日常。 <span>已完成 100 %</span></td></tr>
          </table>
        ''',
        '<html></html>',
      ],
      'plugin.php?H_name-tasks-actions-endtasks.html.html': [
        '<html></html>',
        '''
        <table>
          <tr>
            <td><b>周常</b> (人气 : 24965565) 任务时效2011-12-03~2028-12-31</td>
            <td>奖励 : SP币 7 G</td>
            <td></td>
          </tr>
          <tr><td>无所事事的周常 <span>已完成 100 %</span> 完成时间 2026-06-17 PM:01:00:00</td></tr>
          <tr>
            <td><b>日常</b> (人气 : 84278697) 任务时效2011-12-03~2028-12-31</td>
            <td>奖励 : SP币 2 G</td>
            <td></td>
          </tr>
          <tr><td>每日SP+2的日常。 <span>已完成 100 %</span> 完成时间 2026-06-17 PM:01:00:00</td></tr>
        </table>
      ''',
      ],
      'plugin.php?H_name-tasks.html': [
        '''
          <table>
            <tr>
              <td><b>周常</b> (人气 : 24965565) 任务时效2011-12-03~2028-12-31</td>
              <td>奖励 : SP币 7 G</td>
              <td><span id="p_14"><a onclick="startjob('14');" title="按这申请此任务"></a></span></td>
            </tr>
            <tr><td>无所事事的周常</td></tr>
            <tr>
              <td><b>日常</b> (人气 : 84278697) 任务时效2011-12-03~2028-12-31</td>
              <td>奖励 : SP币 2 G</td>
              <td><span id="p_15"><a onclick="startjob('15');" title="按这申请此任务"></a></span></td>
            </tr>
            <tr><td>每日SP+2的日常。</td></tr>
          </table>
        ''',
        '''
          <table>
            <tr>
              <td><b>周常</b> (人气 : 24965565) 任务时效2011-12-03~2028-12-31</td>
              <td>奖励 : SP币 7 G 上次领取未超过 167 小时</td>
              <td></td>
            </tr>
            <tr><td>无所事事的周常</td></tr>
            <tr>
              <td><b>日常</b> (人气 : 84278697) 任务时效2011-12-03~2028-12-31</td>
              <td>奖励 : SP币 2 G 上次领取未超过 23 小时</td>
              <td></td>
            </tr>
            <tr><td>每日SP+2的日常。</td></tr>
          </table>
        ''',
      ],
    });
    final repository = ForumRepository(client: client);

    final result = await repository.claimForumTaskRewards();

    expect(client.paths, [
      'plugin.php?H_name-tasks-actions-endtasks.html.html',
      'plugin.php?H_name-tasks.html',
      'plugin.php?H_name=tasks&action=ajax&actions=job&cid=14',
      'plugin.php?H_name=tasks&action=ajax&actions=job&cid=15',
      'plugin.php?H_name-tasks-actions-newtasks.html.html',
      'plugin.php?H_name=tasks&action=ajax&actions=job&cid=14',
      'plugin.php?H_name=tasks&action=ajax&actions=job&cid=15',
      'plugin.php?H_name-tasks-actions-endtasks.html.html',
      'plugin.php?H_name-tasks.html',
    ]);
    expect(result.appliedCount, 2);
    expect(result.claimedRewards.map((item) => item.completionMessage), [
      '周常奖励领取完成SP+7',
      '日常奖励领取完成SP+2',
    ]);
    expect(result.failures, isEmpty);
  });

  test('claimForumTaskRewards continues when available task is already started',
      () async {
    final client = _PathForumClient({
      'plugin.php?H_name=tasks&action=ajax&actions=job&cid=14': [
        'error\t领取失败：任务已领取，快去完成任务吧。',
        'success\t任务奖励领取完成',
      ],
      'plugin.php?H_name-tasks-actions-newtasks.html.html': [
        '''
          <table>
            <tr>
              <td><b>周常</b> (人气 : 24965565) 任务时效2011-12-03~2028-12-31</td>
              <td>奖励 : SP币 7 G</td>
              <td><span id="both_14"><a onclick="startjob('14');" title="领取此奖励"></a></span><span id="bmsg_14"></span></td>
            </tr>
            <tr><td>无所事事的周常 <span>已完成 100 %</span></td></tr>
          </table>
        ''',
        '<html></html>',
      ],
      'plugin.php?H_name-tasks-actions-endtasks.html.html': [
        '<html></html>',
        '''
        <table>
          <tr>
            <td><b>周常</b> (人气 : 24965565) 任务时效2011-12-03~2028-12-31</td>
            <td>奖励 : SP币 7 G</td>
            <td></td>
          </tr>
          <tr><td>无所事事的周常 <span>已完成 100 %</span> 完成时间 2026-06-17 PM:01:00:00</td></tr>
        </table>
      ''',
      ],
      'plugin.php?H_name-tasks.html': [
        '''
          <table>
            <tr>
              <td><b>周常</b> (人气 : 24965565) 任务时效2011-12-03~2028-12-31</td>
              <td>奖励 : SP币 7 G</td>
              <td><span id="p_14"><a onclick="startjob('14');" title="按这申请此任务"></a></span></td>
            </tr>
            <tr><td>无所事事的周常</td></tr>
          </table>
        ''',
        '''
          <table>
            <tr>
              <td><b>周常</b> (人气 : 24965565) 任务时效2011-12-03~2028-12-31</td>
              <td>奖励 : SP币 7 G 上次领取未超过 158 小时</td>
              <td></td>
            </tr>
            <tr><td>无所事事的周常</td></tr>
          </table>
        ''',
      ],
    });
    final repository = ForumRepository(client: client);

    final result = await repository.claimForumTaskRewards();

    expect(client.paths, [
      'plugin.php?H_name-tasks-actions-endtasks.html.html',
      'plugin.php?H_name-tasks.html',
      'plugin.php?H_name=tasks&action=ajax&actions=job&cid=14',
      'plugin.php?H_name-tasks-actions-newtasks.html.html',
      'plugin.php?H_name=tasks&action=ajax&actions=job&cid=14',
      'plugin.php?H_name-tasks-actions-endtasks.html.html',
      'plugin.php?H_name-tasks.html',
    ]);
    expect(result.claimedRewards.single.completionMessage, '周常奖励领取完成SP+7');
    expect(result.failures, isEmpty);
  });

  test('claimForumTaskRewards skips cooldown tasks without failing', () async {
    final client = _PathForumClient({
      'plugin.php?H_name-tasks-actions-newtasks.html.html': '<html></html>',
      'plugin.php?H_name-tasks-actions-endtasks.html.html': '<html></html>',
      'plugin.php?H_name-tasks.html': '''
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
      ''',
    });
    final repository = ForumRepository(client: client);

    final result = await repository.claimForumTaskRewards();

    expect(client.paths, [
      'plugin.php?H_name-tasks-actions-endtasks.html.html',
      'plugin.php?H_name-tasks.html',
      'plugin.php?H_name-tasks-actions-newtasks.html.html',
    ]);
    expect(result.hasFailures, isFalse);
    expect(result.hasClaims, isFalse);
    expect(result.cooldowns, isEmpty);
    expect(result.alreadyHandled, isTrue);
  });

  test('claimForumTaskRewards respects completed history with cooldowns',
      () async {
    final client = _PathForumClient({
      'plugin.php?H_name-tasks-actions-endtasks.html.html': '''
        <table>
          <tr>
            <td><b>周常</b> (人气 : 24967385) 任务时效2011-12-03~2028-12-31</td>
            <td>奖励 : SP币 7 G</td>
            <td></td>
          </tr>
          <tr><td>无所事事的周常 已完成 100 % 完成时间 2026-06-17 PM:13:28:02</td></tr>
          <tr>
            <td><b>日常</b> (人气 : 84287885) 任务时效2011-12-03~2028-12-31</td>
            <td>奖励 : SP币 2 G</td>
            <td></td>
          </tr>
          <tr><td>每日SP+2的日常。 已完成 100 % 完成时间 2026-06-17 AM:11:37:46</td></tr>
        </table>
      ''',
      'plugin.php?H_name-tasks.html': '''
        <table>
          <tr>
            <td><b>周常</b> (人气 : 24967383) 任务时效2011-12-03~2028-12-31</td>
            <td>奖励 : SP币 7 G 上次领取未超过 158 小时</td>
            <td></td>
          </tr>
          <tr><td>无所事事的周常</td></tr>
          <tr>
            <td><b>日常</b> (人气 : 84287884) 任务时效2011-12-03~2028-12-31</td>
            <td>奖励 : SP币 2 G 上次领取未超过 18 小时</td>
            <td></td>
          </tr>
          <tr><td>每日SP+2的日常。</td></tr>
        </table>
      ''',
    });
    final repository = ForumRepository(client: client);

    final result = await repository.claimForumTaskRewards();

    expect(client.paths, [
      'plugin.php?H_name-tasks-actions-endtasks.html.html',
      'plugin.php?H_name-tasks.html',
    ]);
    expect(client.paths.any((path) => path.contains('actions=job')), isFalse);
    expect(result.hasClaims, isFalse);
    expect(result.hasFailures, isFalse);
    expect(result.alreadyHandled, isTrue);
  });

  test('claimForumTaskRewards starts next-cycle tasks despite old completion',
      () async {
    final client = _PathForumClient({
      'plugin.php?H_name=tasks&action=ajax&actions=job&cid=15': [
        'success\t任务领取完成',
        'success\t任务奖励领取完成',
      ],
      'plugin.php?H_name-tasks-actions-newtasks.html.html': [
        '''
          <table>
            <tr>
              <td><b>日常</b> (人气 : 84287884) 任务时效2011-12-03~2028-12-31</td>
              <td>奖励 : SP币 2 G</td>
              <td><span id="p_15"><a onclick="startjob('15');" title="领取此奖励"></a></span></td>
            </tr>
            <tr><td>每日SP+2的日常。 已完成 100 %</td></tr>
          </table>
        ''',
        '<html></html>',
      ],
      'plugin.php?H_name-tasks-actions-endtasks.html.html': [
        '''
          <table>
            <tr>
              <td><b>日常</b> (人气 : 84287884) 任务时效2011-12-03~2028-12-31</td>
              <td>奖励 : SP币 2 G</td>
              <td></td>
            </tr>
            <tr><td>每日SP+2的日常。 已完成 100 % 完成时间 2026-06-16 AM:10:00:00</td></tr>
          </table>
        ''',
        '''
          <table>
            <tr>
              <td><b>日常</b> (人气 : 84287884) 任务时效2011-12-03~2028-12-31</td>
              <td>奖励 : SP币 2 G</td>
              <td></td>
            </tr>
            <tr><td>每日SP+2的日常。 已完成 100 % 完成时间 2026-06-17 AM:10:00:00</td></tr>
          </table>
        ''',
      ],
      'plugin.php?H_name-tasks.html': [
        '''
          <table>
            <tr>
              <td><b>日常</b> (人气 : 84287884) 任务时效2011-12-03~2028-12-31</td>
              <td>奖励 : SP币 2 G</td>
              <td><span id="p_15"><a onclick="startjob('15');" title="按这申请此任务"></a></span></td>
            </tr>
            <tr><td>每日SP+2的日常。</td></tr>
          </table>
        ''',
        '''
          <table>
            <tr>
              <td><b>日常</b> (人气 : 84287884) 任务时效2011-12-03~2028-12-31</td>
              <td>奖励 : SP币 2 G 上次领取未超过 23 小时</td>
              <td></td>
            </tr>
            <tr><td>每日SP+2的日常。</td></tr>
          </table>
        ''',
      ],
    });
    final repository = ForumRepository(client: client);

    final result = await repository.claimForumTaskRewards();

    expect(client.paths, [
      'plugin.php?H_name-tasks-actions-endtasks.html.html',
      'plugin.php?H_name-tasks.html',
      'plugin.php?H_name=tasks&action=ajax&actions=job&cid=15',
      'plugin.php?H_name-tasks-actions-newtasks.html.html',
      'plugin.php?H_name=tasks&action=ajax&actions=job&cid=15',
      'plugin.php?H_name-tasks-actions-endtasks.html.html',
      'plugin.php?H_name-tasks.html',
    ]);
    expect(result.appliedCount, 1);
    expect(result.claimedRewards.single.completionMessage, '日常奖励领取完成SP+2');
    expect(result.failures, isEmpty);
  });

  test('claimForumTaskRewards treats action cooldown as handled state',
      () async {
    final client = _PathForumClient({
      'plugin.php?H_name=tasks&action=ajax&actions=job&cid=14':
          'error\t任务申领失败：距离上次申领没超过168小时。',
      'plugin.php?H_name-tasks-actions-newtasks.html.html': '<html></html>',
      'plugin.php?H_name-tasks-actions-endtasks.html.html': '<html></html>',
      'plugin.php?H_name-tasks.html': '''
        <table>
          <tr>
            <td><b>周常</b> (人气 : 24967383) 任务时效2011-12-03~2028-12-31</td>
            <td>奖励 : SP币 7 G</td>
            <td><span id="p_14"><a onclick="startjob('14');" title="按这申请此任务"></a></span></td>
          </tr>
          <tr><td>无所事事的周常</td></tr>
          <tr>
            <td><b>日常</b> (人气 : 84287884) 任务时效2011-12-03~2028-12-31</td>
            <td>奖励 : SP币 2 G 上次领取未超过 18 小时</td>
            <td></td>
          </tr>
          <tr><td>每日SP+2的日常。</td></tr>
        </table>
      ''',
    });
    final repository = ForumRepository(client: client);

    final result = await repository.claimForumTaskRewards();

    expect(result.hasClaims, isFalse);
    expect(result.hasFailures, isFalse);
    expect(result.alreadyHandled, isTrue);
  });

  test('claimForumTaskRewards reports nonclaimable in-progress tasks',
      () async {
    final client = _PathForumClient({
      'plugin.php?H_name-tasks-actions-newtasks.html.html': '''
        <table>
          <tr>
            <td><b>日常</b> (人气 : 84287884) 任务时效2011-12-03~2028-12-31</td>
            <td>奖励 : SP币 2 G</td>
            <td></td>
          </tr>
          <tr><td>每日SP+2的日常。 已完成 60 %</td></tr>
        </table>
      ''',
      'plugin.php?H_name-tasks-actions-endtasks.html.html': '<html></html>',
      'plugin.php?H_name-tasks.html': '''
        <table>
          <tr>
            <td><b>日常</b> (人气 : 84287884) 任务时效2011-12-03~2028-12-31</td>
            <td>奖励 : SP币 2 G</td>
            <td></td>
          </tr>
          <tr><td>每日SP+2的日常。</td></tr>
        </table>
      ''',
    });
    final repository = ForumRepository(client: client);

    final result = await repository.claimForumTaskRewards();

    expect(result.hasClaims, isFalse);
    expect(result.hasFailures, isFalse);
    expect(result.inProgress, ['日常']);
    expect(result.alreadyHandled, isFalse);
  });

  test('claimForumTaskRewards claims in-progress rewards before cooldown state',
      () async {
    final client = _PathForumClient({
      'plugin.php?H_name-tasks-actions-newtasks.html.html': [
        '''
          <table>
            <tr>
              <td><b>周常</b> (人气 : 24966842) 任务时效2011-12-03~2028-12-31</td>
              <td>奖励 : SP币 7 G</td>
              <td><span id="both_14"><a onclick="startjob('14');" title="领取此奖励"><img src="hack/tasks/image/god.png"></a></span></td>
            </tr>
            <tr><td>无所事事的周常 <span>已完成 100 %</span></td></tr>
          </table>
        ''',
        '<html></html>',
      ],
      'plugin.php?H_name-tasks-actions-endtasks.html.html': [
        '<html></html>',
        '''
        <table>
          <tr>
            <td><b>周常</b> (人气 : 24966842) 任务时效2011-12-03~2028-12-31</td>
            <td>奖励 : SP币 7 G</td>
            <td></td>
          </tr>
          <tr><td>无所事事的周常 <span>已完成 100 %</span> 完成时间 2026-06-17 PM:01:02:03</td></tr>
          <tr>
            <td><b>日常</b> (人气 : 84285089) 任务时效2011-12-03~2028-12-31</td>
            <td>奖励 : SP币 2 G</td>
            <td></td>
          </tr>
          <tr><td>每日SP+2的日常。 <span>已完成 100 %</span> 完成时间 2026-06-17 AM:11:37:46</td></tr>
        </table>
      ''',
      ],
      'plugin.php?H_name-tasks.html': '''
        <table>
          <tr>
            <td><b>周常</b> (人气 : 24966842) 任务时效2011-12-03~2028-12-31</td>
            <td>奖励 : SP币 7 G 上次领取未超过 158 小时</td>
            <td></td>
          </tr>
          <tr><td>无所事事的周常</td></tr>
          <tr>
            <td><b>日常</b> (人气 : 84285089) 任务时效2011-12-03~2028-12-31</td>
            <td>奖励 : SP币 2 G 上次领取未超过 18 小时</td>
            <td></td>
          </tr>
          <tr><td>每日SP+2的日常。</td></tr>
        </table>
      ''',
      'plugin.php?H_name=tasks&action=ajax&actions=job&cid=14':
          'success\t任务奖励领取完成',
    });
    final repository = ForumRepository(client: client);

    final result = await repository.claimForumTaskRewards();

    expect(client.paths, [
      'plugin.php?H_name-tasks-actions-endtasks.html.html',
      'plugin.php?H_name-tasks.html',
      'plugin.php?H_name-tasks-actions-newtasks.html.html',
      'plugin.php?H_name=tasks&action=ajax&actions=job&cid=14',
      'plugin.php?H_name-tasks-actions-endtasks.html.html',
      'plugin.php?H_name-tasks.html',
    ]);
    expect(result.claimedRewards.single.completionMessage, '周常奖励领取完成SP+7');
    expect(result.cooldowns, isEmpty);
    expect(result.failures, isEmpty);
  });

  test('refreshForumTaskSnapshot merges completed with cooldown state',
      () async {
    final client = _PathForumClient({
      'plugin.php?H_name-tasks-actions-newtasks.html.html': '<html></html>',
      'plugin.php?H_name-tasks-actions-endtasks.html.html': '''
        <table>
          <tr>
            <td><b>日常</b> (人气 : 84282957) 任务时效2011-12-03~2028-12-31</td>
            <td>奖励 : SP币 2 G</td>
            <td></td>
          </tr>
          <tr><td>每日SP+2的日常。 已完成 100 % 完成时间 2026-06-17 AM:11:37:46</td></tr>
        </table>
      ''',
      'plugin.php?H_name-tasks.html': '''
        <table>
          <tr>
            <td><b>日常</b> (人气 : 84282953) 任务时效2011-12-03~2028-12-31</td>
            <td>奖励 : SP币 2 G 上次领取未超过 18 小时</td>
            <td></td>
          </tr>
          <tr><td>每日SP+2的日常。</td></tr>
        </table>
      ''',
    });
    final repository = ForumRepository(client: client);

    final snapshot = await repository.refreshForumTaskSnapshot();
    final daily = snapshot.taskNamed('日常');

    expect(daily?.availability, ForumTaskAvailability.completed);
    expect(daily?.cooldownRemaining, const Duration(hours: 18));
    expect(daily?.nextAvailableAt, isNotNull);
    expect(daily?.completedAt, '2026-06-17 AM:11:37:46');
  });
}

class _FakeForumClient extends ForumClient {
  _FakeForumClient(this.html);

  final String html;
  String? bytesPath;

  @override
  Future<String> get(String path) async => html;

  @override
  Future<Uint8List> getBytes(String path) async {
    bytesPath = path;
    return Uint8List.fromList([1, 2, 3]);
  }
}

class _PathForumClient extends ForumClient {
  _PathForumClient(this.htmlByPath);

  final Map<String, Object> htmlByPath;
  final paths = <String>[];

  @override
  Future<String> get(String path) async {
    paths.add(path);
    final normalized = path.replaceFirst('https://south-plus.net/', '');
    final value = htmlByPath[normalized] ?? htmlByPath[path];
    if (value is List<String>) {
      if (value.isEmpty) return '<html></html>';
      return value.removeAt(0);
    }
    return value is String ? value : '<html></html>';
  }
}
