import 'package:html/parser.dart' as html_parser;

class ForumResponseParser {
  const ForumResponseParser();

  String pageMessage(String html) {
    final document = html_parser.parse(html);
    final title = _cleanText(document.querySelector('title')?.text ?? '');
    if (title.isNotEmpty) {
      return title
          .replaceFirst(' - 南+ South Plus - powered by Pu!mdHd', '')
          .trim();
    }

    final text = _cleanText(document.body?.text ?? '');
    if (text.isEmpty) return '登录失败';
    final hints = ['认证码', '验证码', '密码', '用户名', '非法', '错误', '失败'];
    for (final hint in hints) {
      final index = text.indexOf(hint);
      if (index == -1) continue;
      final start = index - 24 < 0 ? 0 : index - 24;
      final end = index + 80 > text.length ? text.length : index + 80;
      return text.substring(start, end);
    }
    return text.length > 120 ? text.substring(0, 120) : text;
  }

  bool isReplySuccess(String html, String message) {
    if (message.contains('错误') ||
        message.contains('失败') ||
        message.contains('不能为空') ||
        message.contains('灌水') ||
        message.contains('权限') ||
        message.contains('认证码')) {
      return false;
    }
    return html.contains('发帖完毕') ||
        html.contains('回复成功') ||
        html.contains('发表成功') ||
        html.contains('顺利') ||
        message.contains('发帖完毕') ||
        message.contains('回复成功') ||
        message.contains('发表成功');
  }

  bool isPurchaseSuccess(String html, String message) {
    if (message.contains('错误') ||
        message.contains('失败') ||
        message.contains('权限') ||
        message.contains('金币不足') ||
        message.contains('SP币不足') ||
        message.contains('认证码')) {
      return false;
    }
    return html.contains('操作完成') ||
        html.contains('购买成功') ||
        message.contains('操作完成') ||
        message.contains('购买成功');
  }

  bool isFavoriteAddSuccess(String message) {
    if (message.contains('非法') ||
        message.contains('错误') ||
        message.contains('失败') ||
        message.contains('权限') ||
        message.contains('认证码')) {
      return false;
    }
    return message.contains('收藏');
  }

  bool isFavoriteRemoveSuccess(String html, String message) {
    if (message.contains('错误') ||
        message.contains('失败') ||
        message.contains('权限') ||
        message.contains('认证码')) {
      return false;
    }
    return html.contains('操作完成') ||
        message.contains('操作完成') ||
        message.contains('删除') ||
        message.contains('取消');
  }

  String ajaxMessage(String xml) {
    final cdata = RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true)
        .firstMatch(xml)
        ?.group(1);
    if (cdata != null) return _cleanText(cdata);

    final document = html_parser.parse(xml);
    final ajax = _cleanText(document.querySelector('ajax')?.text ?? '');
    if (ajax.isNotEmpty) return ajax;

    final text = _cleanText(document.body?.text ?? xml);
    return text.isEmpty ? '操作失败' : text;
  }

  String? loggedInUsername(String html) {
    final document = html_parser.parse(html);
    for (final link in document.querySelectorAll('a[href]')) {
      final href = link.attributes['href'] ?? '';
      final text = _cleanText(link.text);
      if ((href == 'u.php' || href.endsWith('/u.php')) &&
          text.isNotEmpty &&
          !{'个人首页', '查看个人资料'}.contains(text)) {
        return text;
      }
    }

    final logoutLink =
        document.querySelector('a[href*="login.php?action=quit"]') ??
            document.querySelector('a[href*="login.php?action-quit"]');
    if (logoutLink != null) {
      final nearbyText = _cleanText(logoutLink.parent?.text ?? '');
      final match = RegExp(r'([\w\u4e00-\u9fa5.-]{2,24})\s*(退出|注销|登出)')
          .firstMatch(nearbyText);
      if (match != null) return match.group(1);
    }

    for (final selector in [
      '#winduid',
      '.user-info',
      '.user-infoWraptwo',
      '.toptool',
      '#td_userinfomore',
      '#head_user',
    ]) {
      final text = _cleanText(document.querySelector(selector)?.text ?? '');
      final username = _usernameFromText(text);
      if (username != null) return username;
    }

    final bodyText = _cleanText(document.body?.text ?? '');
    return _usernameFromText(bodyText);
  }

  String? _usernameFromText(String text) {
    if (text.isEmpty) return null;
    for (final pattern in [
      RegExp(r'欢迎您?[，,\s]+([\w\u4e00-\u9fa5.-]{2,24})'),
      RegExp(r'用户[:：\s]+([\w\u4e00-\u9fa5.-]{2,24})'),
      RegExp(r'会员[:：\s]+([\w\u4e00-\u9fa5.-]{2,24})'),
      RegExp(r'([\w\u4e00-\u9fa5.-]{2,24})\s*(退出|注销|登出)'),
    ]) {
      final match = pattern.firstMatch(text);
      if (match != null) return match.group(1);
    }
    return null;
  }

  String _cleanText(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
