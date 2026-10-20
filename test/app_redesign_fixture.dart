import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/home/home_shell.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// All account names, messages and URLs are synthetic; no network is needed.
class AppRedesignRepository extends ForumRepository {
  AppRedesignRepository({String? user = 'fixture-owner-a'})
      : owner = ValueNotifier(user);

  final ValueNotifier<String?> owner;
  final epoch = ValueNotifier(0);
  final pmRequests = <(ForumPmBox, String?)>[];

  void changeOwner(String? user) {
    owner.value = user;
    epoch.value++;
  }

  @override
  ValueListenable<String?> get sessionUser => owner;

  @override
  ValueListenable<int> get sessionEpoch => epoch;

  @override
  String? get currentUsername => owner.value;

  @override
  bool get isLoggedIn => owner.value != null;

  @override
  Future<void> loadAccountNickname() async {}

  @override
  Future<ForumHomeSnapshot> fetchHome() async => ForumHomeSnapshot(
        latest: [
          for (var i = 0; i < 8; i++)
            ForumThread(
              title: '${owner.value} home topic $i',
              url: 'https://fixture.invalid/read.php?tid-${100 + i}.html',
              replies: i,
              section: 'Fixture board',
            ),
        ],
        hot: const [],
        sections: const [],
      );

  @override
  Future<List<ForumThread>> fetchQuickList(ForumQuickList list) async => [];

  @override
  Future<ForumTaskSnapshot?> loadCachedForumTaskSnapshot() async => null;

  @override
  Future<ForumTaskQuickClaimResult?> autoClaimForumTaskRewardsIfDue() async =>
      null;

  @override
  Future<FavoriteCollections> fetchFavoriteCollections(
          {String? categoryId}) async =>
      FavoriteCollections(
        categories: const [],
        items: [
          for (var i = 0; i < 8; i++)
            FavoriteCollectionEntry(
              id: '$i',
              thread: UserListItem(
                title: '${owner.value} favorite $i',
                url: 'https://fixture.invalid/read.php?tid-${200 + i}.html',
              ),
            ),
        ],
      );

  @override
  Future<ForumPmPage> fetchPmBox(ForumPmBox box, {String? pagePath}) {
    pmRequests.add((box, pagePath));
    return SynchronousFuture(ForumPmPage(
      box: box,
      messages: [
        for (var i = 0; i < 8; i++)
          ForumPmSummary(
            box: box,
            type: ForumPmType.personal,
            id: '${box.name}-$i',
            peer: 'fixture-peer',
            title: '${owner.value} ${box.name} message $i',
            time: '2026-01-01',
            detailPath: 'message.php?action-read-mid-${300 + i}.html',
          ),
      ],
    ));
  }

  @override
  Future<List<ForumReplyNotice>> fetchReplyNotices() async => [];
}

Finder redesignNavigation() => find.byWidgetPredicate(
      (widget) => widget is NavigationBar || widget is NavigationRail,
    );

Future<void> selectRedesignTab(WidgetTester tester, String label,
    {bool settle = true}) async {
  await tester.tap(
      find.descendant(of: redesignNavigation(), matching: find.text(label)));
  if (settle) await tester.pumpAndSettle();
}

Future<AppRedesignRepository> pumpRedesignShell(
  WidgetTester tester, {
  Size size = const Size(360, 800),
  double textScale = 1,
  ThemeMode mode = ThemeMode.light,
  bool reducedMotion = false,
  Key? paintKey,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  AppThemeController.notifier.value = mode;
  addTearDown(() => AppThemeController.notifier.value = ThemeMode.system);
  final repository = AppRedesignRepository();
  Widget app = MaterialApp(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: mode,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reducedMotion,
      ),
      child: child!,
    ),
    home: HomeShell(repository: repository),
  );
  if (paintKey != null) app = RepaintBoundary(key: paintKey, child: app);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  return repository;
}
