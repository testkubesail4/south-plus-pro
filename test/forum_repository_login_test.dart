import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_task_state_store.dart';

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

  test('fetchBoardThreadPage uses thread_new only and keeps sticky threads',
      () async {
    final client = _PathForumClient({
      'thread_new.php?fid-218-page-1.html': '''
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
            <table id="ajaxtable">
              <tr class="tr3 t_one">
                <td><img src="images/colorImagination/thread/topichot.gif"></td>
                <td id="td_1">
                  <h3><a href="read.php?tid-1.html" id="a_ajax_1">
                    <b>总置顶主题</b>
                  </a></h3>
                  <img src="images/colorImagination/file/headtopic_3.gif"
                       title="置顶帖标志">
                </td>
                <td><a class="bl" href="u.php?action-show-uid-1.html">admin</a>
                  <div>2026-06-01</div>
                </td>
                <td>8 / 100</td>
                <td></td>
              </tr>
              <tr class="tr3 t_one">
                <td><img src="images/colorImagination/thread/topichot.gif"></td>
                <td id="td_ad">
                  <h3><a href="https://example.com/ad">
                    <b>外链广告</b>
                  </a></h3>
                  <img src="images/colorImagination/file/headtopic_3.gif"
                       title="置顶帖标志">
                </td>
                <td><a class="bl" href="u.php?action-show-uid-1.html">admin</a></td>
                <td>0 / 1</td>
                <td></td>
              </tr>
              <tr class="tr3 t_one">
                <td><img src="images/colorImagination/thread/topiclock.gif"></td>
                <td id="td_3">
                  <h3><a href="read.php?tid-3.html" id="a_ajax_3">
                    <b>版块置顶主题</b>
                  </a></h3>
                  <img src="images/colorImagination/file/headtopic_1.gif"
                       title="置顶帖标志">
                </td>
                <td><a class="bl" href="u.php?action-show-uid-3.html">mod</a>
                  <div>2026-06-04</div>
                </td>
                <td>2 / 30</td>
                <td></td>
              </tr>
            </table>
            <ul class="stream">
              <li class="dcsns-li dcsns-rss dcsns-feed-0">
                <div class="inner">
                  <span class="section-title">
                    <a href="./read.php?tid-2.html">图墙主题</a>
                  </span>
                  <span class="section-text">
                    <span style="float:right">回复/人气：12/&nbsp;345</span>
                    <div>
                      <a href="./read.php?tid-2.html">
                        <img src="/attachment/Mon_2606/preview.jpg">
                      </a>
                    </div>
                  </span>
                  <span class="section-intro">
                    <table><tr>
                      <td>作者：<a class="bl" href="u.php?action-show-uid-2.html">alice</a></td>
                      <td>2026-06-17</td>
                    </tr></table>
                  </span>
                </div>
              </li>
            </ul>
            <div class="pages">
              <a href="thread_new.php?fid-218-page-1.html">1</a>
              <a href="thread_new.php?fid-218-page-2.html">2</a>
            </div>
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

    expect(client.paths, ['thread_new.php?fid-218-page-1.html']);
    expect(page.subBoards.map((board) => board.name), ['同人志&CG']);
    expect(page.currentPage, 1);
    expect(page.totalPages, 2);
    expect(page.threads.map((thread) => thread.title), [
      '版块置顶主题',
      '图墙主题',
    ]);
    expect(page.ads.map((ad) => ad.title), ['外链广告']);
    expect(page.ads.single.url, 'https://example.com/ad');
    expect(page.threads.first.isSticky, isTrue);
    expect(page.threads.last.previewImageUrl,
        'https://south-plus.net/attachment/Mon_2606/preview.jpg');
  });

  test('fetchBoardThreadPage returns sub boards for empty parent boards',
      () async {
    final client = _PathForumClient({
      'thread_new.php?fid-226-page-1.html': '''
        <html>
          <body>
            <table>
              <tr><td class="h" colspan="5"><b>子版块</b></td></tr>
              <tr class="tr2">
                <td></td><td>论坛</td><td>版主</td><td>文章</td><td>最后发表</td>
              </tr>
              <tr class="f_one tr3">
                <td><a href="thread.php?fid-227.html"><img src="new.gif"></a></td>
                <th>
                  <a class="bklogo" href="thread.php?fid-227.html"></a>
                  <h2>
                    <a href="thread.php?fid-227.html" class="fnamecolor a1">
                      <b>同人志&amp;CG</b>
                    </a>
                  </h2>
                </th>
                <td></td><td>3774</td><th>Re:(C107)</th>
              </tr>
              <tr class="f_one tr3">
                <td><a href="thread.php?fid-228.html"><img src="old.gif"></a></td>
                <th>
                  <a class="bklogo" href="thread.php?fid-228.html"></a>
                  <h2>
                    <a href="thread.php?fid-228.html" class="fnamecolor a1">
                      <b>同人志&amp;CG (图墙模式)</b>
                    </a>
                  </h2>
                </th>
                <td></td><td>0</td><th></th>
              </tr>
            </table>
            <table id="ajaxtable">
              <tr class="tr3 t_one">
                <td><img src="images/colorImagination/thread/anc.gif"></td>
                <td><h3><a href="notice.php?fid-.html#72">Contact / DMCA</a></h3></td>
                <td>论坛公告</td><td>0 / 1</td><td></td>
              </tr>
              <tr class="tr3 t_one">
                <td><img src="images/colorImagination/thread/topiclock.gif"></td>
                <td id="td_1">
                  <h3><a href="read.php?tid-3373.html" id="a_ajax_3373">
                    <b>新人报道帖子（回帖已修复）</b>
                  </a></h3>
                  <img src="images/colorImagination/file/headtopic_3.gif"
                       title="置顶帖标志">
                </td>
                <td><a class="bl" href="u.php?action-show-uid-1.html">admin</a></td>
                <td>64007 / 2018411</td><td></td>
              </tr>
            </table>
          </body>
        </html>
      ''',
    });
    final repository = ForumRepository(client: client);

    final page = await repository.fetchBoardThreadPage(
      const ForumCategory(
        name: 'Comic Market 107',
        slug: 'fid-226',
        url: 'https://south-plus.net/thread.php?fid-226.html',
      ),
    );

    expect(client.paths, ['thread_new.php?fid-226-page-1.html']);
    expect(page.threads, isEmpty);
    expect(page.subBoards.map((board) => board.name), [
      '同人志&CG',
      '同人志&CG (图墙模式)',
    ]);
    expect(page.currentPage, 1);
    expect(page.totalPages, 1);
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

  test('autoClaimForumTaskRewardsIfDue skips requests while cache is fresh',
      () async {
    final now = DateTime.now().toUtc();
    final snapshot = ForumTaskSnapshot(
      updatedAt: now,
      tasks: [
        ForumTaskState(
          name: '日常',
          availability: ForumTaskAvailability.completed,
          reward: 'SP币 2 G',
          spAmount: 2,
          nextAvailableAt: now.add(const Duration(hours: 2)),
        ),
        ForumTaskState(
          name: '周常',
          availability: ForumTaskAvailability.completed,
          reward: 'SP币 7 G',
          spAmount: 7,
          nextAvailableAt: now.add(const Duration(days: 2)),
        ),
      ],
    );
    const store = ForumTaskStateStore();
    await store.save(snapshot);
    final client = _PathForumClient({}, loggedIn: true);
    final repository = ForumRepository(client: client, taskStateStore: store);

    final result = await repository.autoClaimForumTaskRewardsIfDue();

    expect(result, isNull);
    expect(client.paths, isEmpty);
  });

  test('autoClaimForumTaskRewardsIfDue runs one-click flow when cache is due',
      () async {
    final now = DateTime.now().toUtc();
    final snapshot = ForumTaskSnapshot(
      updatedAt: now.subtract(const Duration(days: 1)),
      tasks: [
        ForumTaskState(
          name: '日常',
          availability: ForumTaskAvailability.completed,
          reward: 'SP币 2 G',
          spAmount: 2,
          nextAvailableAt: now.subtract(const Duration(minutes: 1)),
        ),
        ForumTaskState(
          name: '周常',
          availability: ForumTaskAvailability.completed,
          reward: 'SP币 7 G',
          spAmount: 7,
          nextAvailableAt: now.add(const Duration(days: 2)),
        ),
      ],
    );
    const store = ForumTaskStateStore();
    await store.save(snapshot);
    final client = _PathForumClient({
      'plugin.php?H_name=tasks&action=ajax&actions=job&cid=15': [
        'success\t任务领取完成',
        'success\t任务奖励领取完成',
      ],
      'plugin.php?H_name-tasks-actions-endtasks.html.html': [
        '<html></html>',
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
    }, loggedIn: true);
    final repository = ForumRepository(client: client, taskStateStore: store);

    final result = await repository.autoClaimForumTaskRewardsIfDue();

    expect(result?.claimedRewards.single.completionMessage, '日常奖励领取完成SP+2');
    expect(client.paths, contains('plugin.php?H_name-tasks.html'));
    expect(
      client.paths,
      contains('plugin.php?H_name=tasks&action=ajax&actions=job&cid=15'),
    );
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
  _PathForumClient(this.htmlByPath, {this.loggedIn = false});

  final Map<String, Object> htmlByPath;
  final bool loggedIn;
  final paths = <String>[];

  @override
  bool get isLoggedIn => loggedIn;

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
