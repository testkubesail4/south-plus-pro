import 'package:html/dom.dart' as dom;

import '../../models/forum_models.dart';
import '../forum_url_resolver.dart';

class ThreadRewardParser {
  ThreadRewardParser(this.urls);
  final ForumUrlResolver urls;

  // Only the system TH of this exact post can supply ratings or reward actions.
  Iterable<dom.Element> containers(dom.Element post) sync* {
    for (final cell in post.querySelectorAll('th')) {
      if (cell.classes.contains('r_one') ||
          cell.classes.contains('r_two') ||
          cell.parent?.localName != 'tr' ||
          !(cell.parent?.parent == post ||
              (cell.parent?.parent?.localName == 'tbody' &&
                  cell.parent?.parent?.parent == post))) continue;
      for (final content
          in cell.children.where((e) => e.classes.contains('tpc_content'))) {
        if (content.querySelector('[id^="read_"]') == null) yield content;
      }
    }
  }

  List<ThreadRating> ratings(dom.Element post) => [
        for (final content in containers(post))
          for (final mark in content.children.where(
              (e) => e.id.startsWith('mark_') && e.classes.contains('tips')))
            for (final item in mark.querySelectorAll('li'))
              if (RegExp(r'^\s*([^:：]+)[:：]\s*([+-]\d+)\s*$')
                      .firstMatch(item.text)
                  case final match?)
                ThreadRating(
                    currency: match.group(1)!.trim(),
                    amount: int.parse(match.group(2)!),
                    text: clean(item.text)),
      ];

  ThreadBounty? bounty(dom.Element post) {
    for (final content in containers(post)) {
      for (final box
          in content.children.where((e) => e.classes.contains('tips'))) {
        final text = clean(box.text);
        if (!RegExp(r'此帖悬赏').hasMatch(text)) continue;
        return ThreadBounty(
          status: text.contains('悬赏结束')
              ? ForumBountyStatus.ended
              : RegExp(r'剩余时间\s*[:：]\s*已结束').hasMatch(text)
                  ? ForumBountyStatus.expired
                  : text.contains('悬赏中')
                      ? ForumBountyStatus.active
                      : ForumBountyStatus.unknown,
          text: text,
          bestAmount: number(text, r'最佳答案\s*[:：]\s*(\d+)'),
          helpfulRemaining: number(text, r'热心助人剩余点数\s*[:：]\s*(\d+)'),
          remainingHours: number(text, r'剩余时间\s*[:：]\s*(\d+)'),
        );
      }
    }
    return null;
  }

  ThreadAward? award(dom.Element post) {
    for (final content in containers(post)) {
      for (final box
          in content.children.where((e) => e.classes.contains('tips'))) {
        final text = clean(box.text);
        final match = RegExp(r'^(最佳答案|热心助人)奖励\s*[:：]\s*\(\+(\d+)\)\s*(SP币|HP)')
            .firstMatch(text);
        if (match != null)
          return ThreadAward(
              kind: match.group(1) == '最佳答案'
                  ? ThreadRewardKind.bestAnswer
                  : ThreadRewardKind.helpful,
              amount: int.parse(match.group(2)!),
              currency: match.group(3)!,
              text: text);
      }
    }
    return null;
  }

  ThreadRewardAction? action(String href) {
    if (!urls.isForumUrl(href)) return null;
    final uri = Uri.tryParse(urls.absoluteUrl(href));
    if (uri == null ||
        uri.path != '/job.php' ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) return null;
    final match = RegExp(
            r'^action-reward-tid-([1-9]\d*)-pid-([1-9]\d*)-type-([12])\.html$')
        .firstMatch(uri.query);
    if (match == null) return null;
    return ThreadRewardAction(
        kind: match.group(3) == '1'
            ? ThreadRewardKind.bestAnswer
            : ThreadRewardKind.helpful,
        url: uri.toString(),
        tid: match.group(1)!,
        pid: match.group(2)!);
  }

  List<ThreadRewardAction> actions(dom.Element post, {int page = 1}) => [
        for (final content in containers(post))
          for (final box
              in content.children.where((e) => e.classes.contains('tips')))
            for (final link in box.querySelectorAll('a[href]'))
              if (action(link.attributes['href']!) case final target?)
                if (post.querySelector('th.r_one #read_${target.pid}') != null)
                  ThreadRewardAction(
                      kind: target.kind,
                      url: target.url,
                      tid: target.tid,
                      pid: target.pid,
                      page: page),
      ];

  int? number(String text, String pattern) =>
      int.tryParse(RegExp(pattern).firstMatch(text)?.group(1) ?? '');
  String clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();
}
