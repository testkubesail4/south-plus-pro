import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_url_resolver.dart';
import 'package:south_plus_rewrite/services/parsers/user_profile_parser.dart';

void main() {
  test(
    'native mixed feed keeps actors, repeated thread events and friendship targets',
    () {
      final parser = UserProfileParser(
        urls: ForumUrlResolver(baseUri: Uri.parse('https://south-plus.net/')),
      );
      final empty = html.parse('<table class="u-table"></table>');
      final details = parser.appendDetails(
        overview: const UserProfile(
          uid: '101',
          name: 'self',
          url: 'u.php?uid-101.html',
        ),
        homeDocument: html.parse(
          '''<div id="minifeed"><h5>好友近况</h5>
<dl class="feed-list"><dt><a href="u.php?uid-101.html" class="link1">self</a> 发表了主题：
<a href="//blue-plus.net/read.php?tid-701.html"><b>topic title</b></a></dt></dl>
<dl class="feed-list"><dt><a href="u.php?uid-202.html">friend</a> 回复了主题：
<a href="//blue-plus.net/read.php?tid-701.html">topic title</a></dt></dl>
<dl class="feed-list"><dt><a href="u.php?uid-202.html">friend</a> 和
<a href="//blue-plus.net/u.php?uid-303.html">other</a> 成为了好友!</dt></dl>
<dl class="feed-list"><dt><a href="https://external.invalid/u.php?uid-404.html">outsider</a>
发表了主题：<a href="https://external.invalid/read.php?tid-999.html">foreign</a></dt></dl>
</div><div class="u-box-wrap"><a href="read.php?tid-888.html">unrelated legacy</a></div>''',
        ),
        topicsDocument: empty,
        postsDocument: empty,
        favoritesDocument: empty,
      );
      final activities = details.homeActivities;
      expect(activities, hasLength(3));
      expect(activities.map((item) => item.authorUid), ['101', '202', '202']);
      expect(activities.map((item) => item.action), [
        '发表了主题',
        '回复了主题',
        '成为了好友',
      ]);
      expect(
        activities.first.url,
        'https://south-plus.net/read.php?tid-701.html',
      );
      expect(
        activities[1].url,
        activities.first.url,
        reason: 'different actors/actions on one thread remain distinct events',
      );
      expect(activities.last.url, isNull, reason: 'friendship is not a thread');
      expect(activities.last.targetName, 'other');
      expect(activities.last.targetUid, '303');
      expect(
        activities.last.targetUrl,
        'https://south-plus.net/u.php?uid-303.html',
      );
    },
  );
}
