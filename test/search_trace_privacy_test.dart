import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/services/forum_trace_logger.dart';

void main() {
  test('request-form traces redact search terms and private message fields',
      () {
    final trace = ForumTraceLogger.sanitizeForm({
      'keyword': 'fixture-keyword-canary',
      'pwuser': 'fixture-user-canary',
      'atc_content': 'fixture-body-canary',
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
