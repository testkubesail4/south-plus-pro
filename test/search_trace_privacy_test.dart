import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/services/forum_trace_logger.dart';

void main() {
  test('request-form traces redact private fields and blocking configuration',
      () {
    final trace = ForumTraceLogger.sanitizeForm({
      'keyword': 'fixture-keyword-canary',
      'pwuser': 'fixture-user-canary',
      'atc_content': 'fixture-body-canary',
      'atc_title': 'fixture-floor-reply-canary',
      'blocklistconfig': '{"name":"fixture-block-name-canary","uid":"404"}',
      'msg_title': 'fixture-title-canary',
      'touidmsg': 'fixture-recipient-canary',
      'verify': 'fixture-token-canary',
      'sch_time': '31536000',
      'digest': '1',
    });
    expect(trace, isNot(contains('canary')));
    expect(trace, contains('sch_time=31536000'));
    expect(trace, contains('digest=1'));
  });
}
