import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/board/board_thread_list_screen.dart';
import 'package:south_plus_rewrite/features/common/forum_title_text.dart';
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
    testWidgets(
        'board list marks site-highlighted titles without link styling '
        '($mode)', (tester) async {
      AppThemeController.notifier.value = mode;
      await tester.pumpWidget(MaterialApp(
        // Rows take their text colour from the app theme's roles.
        theme: mode == ThemeMode.dark ? AppTheme.dark : AppTheme.light,
        home: BoardThreadListScreen(
          category: const ForumCategory(name: 'Board', slug: 'fid-42'),
          repository: _Repo(),
        ),
      ));
      await tester.pumpAndSettle();
      TextStyle style(String title) =>
          tester.widget<Text>(find.text(title)).style!;

      // The site colour sits on a marker beside the title.
      Iterable<Color> markers(String title) => tester
          .widgetList<DecoratedBox>(find.descendant(
            of: find.ancestor(
              of: find.text(title),
              matching: find.byType(ForumTitleText),
            ),
            matching: find.byType(DecoratedBox),
          ))
          .map((box) => (box.decoration as BoxDecoration).color!);

      final magenta = style('Pink topic');
      expect(magenta.fontWeight, FontWeight.w700);
      expect(magenta.fontStyle, isNot(FontStyle.italic));
      final blue = style('Blue topic');
      expect(blue.fontStyle, FontStyle.italic);
      for (final (title, site) in [
        ('Pink topic', Color(_magenta.colorValue!)),
        ('Blue topic', Color(_blue.colorValue!)),
      ]) {
        // Title text never looks like a raw link.
        expect(style(title).color, AppColors.text, reason: title);
        expect(style(title).decoration, isNot(TextDecoration.underline));
        final marker = markers(title).single;
        expect(_contrast(marker, AppColors.surface), greaterThanOrEqualTo(4.5));
        // Same hue the site chose, only lightness adjusted.
        expect(HSLColor.fromColor(marker).hue,
            closeTo(HSLColor.fromColor(site).hue, 1));
      }

      final plain = style('Plain topic');
      expect(plain.color, AppColors.text);
      expect(plain.decoration, isNot(TextDecoration.underline));
      expect(markers('Plain topic'), isEmpty);
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
