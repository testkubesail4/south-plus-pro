import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

const _root = ValueKey('route-paint-root');

// Mean darkness of the screen: content fading towards white lowers it.
Future<double> _ink(WidgetTester tester) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_root));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 0.5);
    final data = (await image.toByteData())!;
    image.dispose();
    final pixels = data.lengthInBytes ~/ 4;
    var darkness = 0.0;
    for (var i = 0; i < pixels; i++) {
      darkness += 255 -
          (0.299 * data.getUint8(i * 4) +
              0.587 * data.getUint8(i * 4 + 1) +
              0.114 * data.getUint8(i * 4 + 2));
    }
    return darkness / pixels / 255;
  }))!;
}

class _Page extends StatelessWidget {
  const _Page(this.name, {this.next});

  final String name;
  final Widget? next;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(name)),
        body: ListView(
          children: [
            if (next != null)
              ListTile(
                title: const Text('open'),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => next!)),
              ),
            for (var i = 0; i < 12; i++) ListTile(title: Text('$name row $i')),
          ],
        ),
      );
}

/// Lowest ink seen while a push and its pop animate, against the lower of
/// the two settled pages.
Future<double> _lowestInkRatio(WidgetTester tester, ThemeData theme) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RepaintBoundary(
    key: _root,
    child: MaterialApp(
      theme: theme,
      home: const _Page('First', next: _Page('Second')),
    ),
  ));
  final first = await _ink(tester);
  var lowest = double.infinity;
  Future<void> sample() async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final ink = await _ink(tester);
      if (ink < lowest) lowest = ink;
    }
    await tester.pumpAndSettle();
  }

  await tester.tap(find.text('open'));
  await sample();
  final second = await _ink(tester);
  await tester.pageBack();
  await sample();
  final settled = first < second ? first : second;
  // ignore: avoid_print
  print('ink first=$first second=$second lowest=$lowest');
  return lowest / settled;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('route changes never fade the screen through blank',
      (tester) async {
    expect(await _lowestInkRatio(tester, AppTheme.light),
        greaterThanOrEqualTo(0.6));
  });

  test('only Android route motion differs from the platform defaults', () {
    final builders = AppTheme.light.pageTransitionsTheme.builders;
    final defaults = const PageTransitionsTheme().builders;
    expect(builders[TargetPlatform.android], isA<ZoomPageTransitionsBuilder>());
    for (final platform in defaults.keys) {
      if (platform == TargetPlatform.android) continue;
      expect(builders[platform].runtimeType, defaults[platform].runtimeType,
          reason: '$platform');
    }
  });

  testWidgets('a profile shows loaded content at full strength at once',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: _root,
      child: MaterialApp(
        theme: AppTheme.light,
        home: UserProfileScreen(
          userUrl: _CachedProfileRepo.profile.url,
          repository: _CachedProfileRepo(),
        ),
      ),
    ));
    for (var i = 0;
        i < 5 && find.text('fixture-user').evaluate().isEmpty;
        i++) {
      await tester.pump();
    }
    expect(find.text('fixture-user'), findsWidgets);
    final first = await _ink(tester);
    await tester.pumpAndSettle();
    expect(first / await _ink(tester), greaterThanOrEqualTo(0.9));
  });
}

class _CachedProfileRepo extends ForumRepository {
  static const profile = UserProfile(
    uid: '1',
    name: 'fixture-user',
    url: 'https://fixture.invalid/u.php?uid-1.html',
    favorites: [
      UserListItem(title: 'Fixture favorite', url: 'read.php?tid-1.html'),
    ],
  );

  @override
  Future<UserProfile?> cachedUserProfileOverview(String url) async => profile;

  // Revalidation stays in flight; the cached page is what shows.
  @override
  Future<UserProfile> fetchUserProfileOverview(String url) =>
      Completer<UserProfile>().future;

  @override
  Future<UserProfile> fetchUserProfileDetails(
    UserProfile overview, {
    bool forceReload = false,
  }) =>
      SynchronousFuture(overview);
}
