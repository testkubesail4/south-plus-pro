import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/user_note_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final uid in ['42', '43']) {
    testWidgets('local state completes in consecutive widget test zone $uid',
        (tester) async {
      var completed = false;
      Map<String, String>? notes;
      Object? error;
      UserNoteStore.save(uid, '备注$uid')
          .then((_) => UserNoteStore.load())
          .then<void>((value) {
        notes = value;
        completed = true;
      }, onError: (Object failure, StackTrace _) {
        error = failure;
        completed = true;
      });

      await tester.pump();
      expect(completed, isTrue,
          reason: 'Idle local state must not use a previous test zone.');
      expect(error, isNull);
      expect(notes, {uid: '备注$uid'});
    });
  }
}
