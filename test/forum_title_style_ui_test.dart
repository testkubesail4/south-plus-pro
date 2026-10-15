import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/board/board_thread_list_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

// Synthetic titles and ids only.
const _magenta = ForumTitleStyle(bold: true, colorValue: 0xFFFF00FF);
const _blue = ForumTitleStyle(
  italic: true,
  underline: true,
  colorValue: 0xFF0000FF,
);

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => AppThemeController.notifier.value = ThemeMode.system);

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('board list keeps site title highlight readable ($mode)',
        (tester) async {
      AppThemeController.notifier.value = mode;
      await tester.pumpWidget(MaterialApp(
        home: BoardThreadListScreen(
          category: const ForumCategory(name: 'Board', slug: 'fid-42'),
          repository: _Repo(),
        ),
      ));
      await tester.pumpAndSettle();
      TextStyle style(String title) =>
          tester.widget<Text>(find.text(title)).style!;

      final magenta = style('Pink topic');
      expect(magenta.fontWeight, FontWeight.w800);
      expect(magenta.fontStyle, isNot(FontStyle.italic));
      final blue = style('Blue topic');
      expect(blue.fontStyle, FontStyle.italic);
      expect(blue.decoration, TextDecoration.underline);
      for (final (text, site) in [
        (magenta, Color(_magenta.colorValue!)),
        (blue, Color(_blue.colorValue!)),
      ]) {
        expect(_contrast(text.color!, AppColors.surface),
            greaterThanOrEqualTo(4.5));
        // Same hue the site chose, only lightness adjusted.
        expect(HSLColor.fromColor(text.color!).hue,
            closeTo(HSLColor.fromColor(site).hue, 1));
      }

      final plain = style('Plain topic');
      expect(plain.color, AppColors.text);
      expect(plain.decoration, isNot(TextDecoration.underline));
    });
  }
}

class _Repo extends ForumRepository {
  @override
  Future<ForumThreadPage> fetchBoardThreadPage(
    ForumCategory category, {
    int page = 1,
    ForumThreadOrder order = ForumThreadOrder.lastPost,
    ForumBoardFilter? filter,
  }) async =>
      const ForumThreadPage(
        threads: [
          ForumThread(
            title: 'Pink topic',
            url: 'read.php?tid-1.html',
            replies: 0,
            section: 'Board',
            titleStyle: _magenta,
          ),
          ForumThread(
            title: 'Blue topic',
            url: 'read.php?tid-2.html',
            replies: 0,
            section: 'Board',
            titleStyle: _blue,
          ),
          ForumThread(
            title: 'Plain topic',
            url: 'read.php?tid-3.html',
            replies: 0,
            section: 'Board',
          ),
        ],
        currentPage: 1,
        totalPages: 1,
      );
}
