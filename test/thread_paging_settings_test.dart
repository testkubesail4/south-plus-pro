import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/thread_paging_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('auto-loading defaults off and restores the persisted choice', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await ThreadPagingSettings.load(), isFalse);
    await ThreadPagingSettings.save(true);
    expect(ThreadPagingSettings.notifier.value, isTrue);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'settings.autoLoadNextPage',
      ),
      isTrue,
    );
    ThreadPagingSettings.notifier.value = false;
    expect(await ThreadPagingSettings.load(), isTrue);
    await ThreadPagingSettings.save(false);
    ThreadPagingSettings.notifier.value = true;
    expect(await ThreadPagingSettings.load(), isFalse);
  });
}
