import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/app.dart';
import 'package:south_plus_rewrite/features/board/board_thread_list_screen.dart';
import 'package:south_plus_rewrite/features/common/forum_title_text.dart';
import 'package:south_plus_rewrite/features/editor/windcode_toolbar.dart';
import 'package:south_plus_rewrite/features/home/home_shell.dart';
import 'package:south_plus_rewrite/features/messages/pm_compose_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_network_setup_store.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_session_store.dart';
import 'package:south_plus_rewrite/services/image_loading_settings.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

// Reuse the app's repository injection; local HTTP stays out of production config.
class _FixtureSite extends ForumSite {
  const _FixtureSite() : super('127.0.0.1');

  @override
  Uri get baseUri => Uri.parse('http://127.0.0.1:8765/');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late ForumRepository repository;
  late String window;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      ForumNetworkSetupStore.completedKey: true,
    });
    await ImageLoadingSettings.saveMode(ImageLoadMode.automatic);
    await AppThemeController.setMode(ThemeMode.light);
    repository = ForumRepository(
      config: const ForumNetworkConfig(
        site: _FixtureSite(),
        dohEnabled: false,
        dohProvider: ForumNetworkConfig.defaultProvider,
      ),
    );
  });

  Widget app(Widget Function() home) => ValueListenableBuilder<ThemeMode>(
        valueListenable: AppThemeController.notifier,
        builder: (context, mode, _) => MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          home: home(),
        ),
      );

  Future<void> findWindow() async {
    final search = await Process.run('xdotool',
        ['search', '--onlyvisible', '--name', r'^south_plus_rewrite$']);
    expect(search.exitCode, 0, reason: '${search.stderr}');
    window = '${search.stdout}'.trim().split('\n').first;
  }

  Future<void> screenshot(String name) async {
    // Let the native compositor present the Flutter frame before X reads it.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await findWindow();
    // Linux integration_test has no native screenshot implementation.
    final result = await Process.run('import', [
      '-window',
      window,
      '/output/$name.png',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(File('/output/$name.png').lengthSync(), greaterThan(1000));
  }

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (finder.evaluate().isEmpty) await screenshot('failure');
    expect(finder, findsWidgets);
  }

  testWidgets('Linux launches, loads home, opens a thread and captures it',
      (tester) async {
    await tester.pumpWidget(app(() => SessionGate(repository: repository)));
    await waitFor(tester, find.text('Fixture thread'));
    await tester.tap(find.text('Fixture thread').first);
    await waitFor(
        tester, find.textContaining('Fixture post body', findRichText: true));
    expect(find.text('Fixture author'), findsWidgets);
    await tester.pumpAndSettle();
    await screenshot('thread-smoke');
  });

  double contrast(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
  }

  // The site's bold magenta: a bold title in the body colour, the magenta on
  // a readable bar before it.
  void expectHighlight(WidgetTester tester, Finder title) {
    final style = tester.widget<Text>(title).style!;
    expect(style.fontWeight, FontWeight.w700);
    expect(style.color, AppColors.text);
    final bar = find.descendant(
      of: find.ancestor(of: title, matching: find.byType(ForumTitleText)),
      matching: find.byType(DecoratedBox),
    );
    final color =
        (tester.widget<DecoratedBox>(bar).decoration as BoxDecoration).color!;
    // The fixture's colour is opaque, so the bar must paint it fully.
    expect(color.a, 1.0);
    expect(HSVColor.fromColor(color).hue, closeTo(300, 1));
    expect(contrast(color, AppColors.surface), greaterThanOrEqualTo(4.5));
    final rect = tester.getRect(bar);
    expect(rect.width, greaterThan(0));
    expect(rect.height, greaterThan(0));
    expect(rect.right, lessThanOrEqualTo(tester.getRect(title).left));
  }

  testWidgets('board highlights, stable portrait image and single-row composer',
      (tester) async {
    await tester.pumpWidget(app(() => BoardThreadListScreen(
          repository: repository,
          category: const ForumCategory(
            name: 'Fixture board',
            slug: 'f900',
            url: 'http://127.0.0.1:8765/thread.php?fid-900.html',
          ),
        )));
    final title = find.text('Fixture highlighted title');
    await waitFor(tester, title);
    // Finding the title only proves it is built; settle so it is presented.
    await tester.pumpAndSettle();
    expectHighlight(tester, title);
    await screenshot('board-highlight-light');
    await AppThemeController.setMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(title)).brightness, Brightness.dark);
    expectHighlight(tester, title);
    await screenshot('board-highlight-dark');
    await AppThemeController.setMode(ThemeMode.light);

    final resize =
        await Process.run('xdotool', ['windowsize', window, '400', '800']);
    expect(resize.exitCode, 0, reason: '${resize.stderr}');
    await tester.pumpAndSettle();
    await tester.tap(title);
    await waitFor(
        tester, find.textContaining('Fixture post body', findRichText: true));
    final loadedImage = find.byWidgetPredicate(
        (widget) => widget is RawImage && widget.image != null);
    await waitFor(tester, loadedImage);
    final imageRect = tester.getRect(loadedImage.first);
    expect(imageRect.height, greaterThan(imageRect.width));
    // Sample from the first decoded frame, including the placeholder fade.
    for (var frame = 1; frame <= 13; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      final rect = tester.getRect(loadedImage.first);
      expect(rect.left, imageRect.left, reason: 'image x at ${frame * 100}ms');
      expect(rect.width, imageRect.width);
      if (frame == 3) await screenshot('portrait-image-loaded');
      if (frame == 13) await screenshot('portrait-image-after-1s');
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await ForumSessionStore().saveCookies({
      'fixture': ForumStoredCookie.session(
        name: 'fixture_winduser',
        value: 'synthetic-local-session',
        origin: const _FixtureSite().baseUri,
      ),
    });
    final client = ForumClient(config: repository.networkConfig);
    addTearDown(() => client.close(force: true));
    await client.restoreCookies();
    final composerRepository = ForumRepository(client: client);
    expect(composerRepository.isLoggedIn, isTrue);
    await tester
        .pumpWidget(app(() => PmComposeScreen(repository: composerRepository)));
    await waitFor(tester, find.byType(WindCodeToolbar));
    await tester.ensureVisible(find.byType(WindCodeToolbar));
    await tester.pumpAndSettle();
    expect(MediaQuery.sizeOf(tester.element(find.byType(WindCodeToolbar))),
        const Size(400, 800));
    final more = find.byTooltip('更多');
    expect(more, findsOneWidget);
    final buttons = find.descendant(
        of: find.byType(WindCodeToolbar), matching: find.byType(IconButton));
    final y = tester.getCenter(more).dy;
    for (final button in buttons.evaluate()) {
      expect(tester.getCenter(find.byWidget(button.widget)).dy, y);
    }
    await screenshot('composer-portrait');
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.text('代码'), findsOneWidget);
  });

  testWidgets('home adapts to four native window sizes in both themes',
      (tester) async {
    for (final size in const [
      Size(400, 800),
      Size(800, 600),
      Size(1280, 800),
      Size(1920, 1080),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await findWindow();
      final resize = await Process.run('xdotool', [
        'windowsize',
        window,
        '${size.width.toInt()}',
        '${size.height.toInt()}',
      ]);
      expect(resize.exitCode, 0, reason: '${resize.stderr}');
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(() => SessionGate(repository: repository)));
      await waitFor(tester, find.text('Fixture thread'));
      await tester.pumpAndSettle();
      expect(MediaQuery.sizeOf(tester.element(find.byType(HomeShell))), size);
      if (size.width < 600) {
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byType(NavigationRail), findsNothing);
      } else {
        expect(find.byType(NavigationBar), findsNothing);
        expect(
            tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
            isFalse);
      }
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await AppThemeController.setMode(mode);
        await tester.pumpAndSettle();
        expect(Theme.of(tester.element(find.text('Fixture thread'))).brightness,
            mode == ThemeMode.dark ? Brightness.dark : Brightness.light);
        await screenshot(
            'home-${size.width.toInt()}x${size.height.toInt()}-${mode.name}');
        // The page's vertical list holds the 速览 header and the sections;
        // 'Fixture thread' sits in the quick lists' own scrollables.
        final scrollElement = tester.element(find
            .ancestor(
              of: find.text('速览'),
              matching: find.byType(Scrollable),
            )
            .first);
        final scrollable = find
            .byElementPredicate((element) => identical(element, scrollElement));
        expect(tester.widget<Scrollable>(scrollable).axisDirection,
            AxisDirection.down);
        await tester.scrollUntilVisible(find.text('Fixture section 3'), 300,
            scrollable: scrollable);
        if (find.text('Fixture board 3.3').evaluate().isEmpty) {
          await tester.tap(find.text('Fixture section 3'));
          await tester.pumpAndSettle();
        }
        await tester.scrollUntilVisible(find.text('Fixture board 3.3'), 200,
            scrollable: scrollable);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.state<ScrollableState>(scrollable).position.jumpTo(0);
        await tester.pumpAndSettle();
      }
    }
  });
}
