import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_text_size_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('text sizes default safely and persist with notifier updates', () async {
    expect(ForumTextSizeSettings.notifier.value, ForumTextSize.normal);
    for (final (stored, expected) in [
      (null, ForumTextSize.normal),
      ('fixture-invalid', ForumTextSize.normal),
      ('small', ForumTextSize.small),
      ('normal', ForumTextSize.normal),
      ('large', ForumTextSize.large),
    ]) {
      SharedPreferences.setMockInitialValues({
        if (stored != null) 'settings.forumTextSize': stored,
      });
      expect(await ForumTextSizeSettings.load(), expected);
      expect(ForumTextSizeSettings.notifier.value, expected);
    }

    final changes = <ForumTextSize>[];
    void listener() => changes.add(ForumTextSizeSettings.notifier.value);
    ForumTextSizeSettings.notifier.addListener(listener);
    addTearDown(() => ForumTextSizeSettings.notifier.removeListener(listener));
    for (final (size, factor) in [
      (ForumTextSize.small, 0.9),
      (ForumTextSize.normal, 1.0),
      (ForumTextSize.large, 1.15),
    ]) {
      await ForumTextSizeSettings.save(size);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('settings.forumTextSize'), size.name);
      expect(ForumTextSizeSettings.notifier.value, size);
      expect(size.scale, factor);
      expect(await ForumTextSizeSettings.load(), size);
    }
    expect(changes, [
      ForumTextSize.small,
      ForumTextSize.normal,
      ForumTextSize.large,
    ]);
  });
}
