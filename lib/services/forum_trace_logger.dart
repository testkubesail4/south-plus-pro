import 'dart:io';

class ForumTraceLogger {
  static const bool enabled =
      bool.fromEnvironment('FORUM_TRACE', defaultValue: false);

  static void log(String scope, String message) {
    if (!enabled) return;
    final timestamp = DateTime.now().toIso8601String();
    final prefix = '[ForumTrace][$timestamp][$scope]';
    final normalized = message.replaceAll('\r\n', '\n');
    for (final line in normalized.split('\n')) {
      stdout.writeln('$prefix $line');
    }
  }

  static void logBlock(String scope, String title, String body) {
    if (!enabled) return;
    log(scope, '$title BEGIN');
    log(scope, body);
    log(scope, '$title END');
  }

  static String sanitizeForm(Map<String, String> form) {
    final entries = <String>[];
    final keys = form.keys.toList()..sort();
    for (final key in keys) {
      final lower = key.toLowerCase();
      final isSensitive = lower.contains('pwd') ||
          lower.contains('pass') ||
          lower.contains('answer') ||
          lower.contains('question') ||
          lower.contains('verify');
      final value = isSensitive ? '<redacted>' : form[key];
      entries.add('$key=$value');
    }
    return entries.join('&');
  }

  static bool shouldLogFullBody(Uri uri) {
    final value = uri.toString().toLowerCase();
    return value.contains('h_name-tasks') ||
        value.contains('actions=job') ||
        value.contains('action=tasks');
  }
}
