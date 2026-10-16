import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/cached_forum_image.dart';
import 'package:south_plus_rewrite/features/home/home_shell.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// Synthetic account names and avatar URL only.
const _avatar = 'https://south-plus.net/images/face/fixture.png';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpHome(WidgetTester tester, _Repo repo) async {
    await tester.pumpWidget(MaterialApp(home: HomeShell(repository: repo)));
    await tester.pump();
  }

  Future<void> openAccountTab(WidgetTester tester) async {
    await tester.tap(find.text('我的'));
    await tester.pump();
  }

  Iterable<String> avatarUrls(WidgetTester tester) => tester
      .widgetList<CachedForumImage>(find.descendant(
        of: find.byType(CircleAvatar),
        matching: find.byType(CachedForumImage),
      ))
      .map((image) => image.url);

  testWidgets('我的 shows the nickname first and the avatar in a circle',
      (tester) async {
    final repo = _Repo(const ForumAccountIdentity(
      systemName: 'fixture_login',
      avatarUrl: _avatar,
    ));
    await pumpHome(tester, repo);
    expect(find.text('fixture_login'), findsOneWidget, reason: 'home chip');
    expect(avatarUrls(tester), [_avatar]);
    expect(repo.nicknameLoads, 0, reason: 'never fetched for home');

    await openAccountTab(tester);
    expect(repo.nicknameLoads, 1);
    expect(find.text('fixture_login'), findsOneWidget,
        reason: 'system name until the nickname arrives');
    repo.nickname.complete();
    await tester.pump();
    expect(find.text('Fixture Nick'), findsOneWidget);
    expect(find.text('fixture_login'), findsOneWidget,
        reason: 'system name stays visible under the nickname');
    expect(avatarUrls(tester), [_avatar]);
  });

  testWidgets('without a nickname or avatar 我的 shows the system name',
      (tester) async {
    final repo = _Repo(const ForumAccountIdentity(
      systemName: 'fixture_login',
      nickname: '  ',
    ));
    await pumpHome(tester, repo);
    expect(find.text('fixture_login'), findsOneWidget, reason: 'home chip');
    expect(avatarUrls(tester), isEmpty);

    await openAccountTab(tester);
    expect(find.text('fixture_login'), findsOneWidget);
    expect(avatarUrls(tester), isEmpty);
    expect(
      find.descendant(
        of: find.byType(CircleAvatar),
        matching: find.byIcon(Icons.account_circle_outlined),
      ),
      findsWidgets,
    );
  });
}

class _Repo extends ForumRepository {
  _Repo(ForumAccountIdentity identity) : _identity = ValueNotifier(identity);

  final ValueNotifier<ForumAccountIdentity?> _identity;
  final nickname = Completer<void>();
  var nicknameLoads = 0;

  @override
  Future<void> loadAccountNickname() async {
    nicknameLoads++;
    await nickname.future;
    final identity = _identity.value!;
    _identity.value = ForumAccountIdentity(
      systemName: identity.systemName,
      nickname: ' Fixture Nick ',
      avatarUrl: identity.avatarUrl,
    );
  }

  @override
  ValueListenable<ForumAccountIdentity?> get accountIdentity => _identity;

  @override
  bool get isLoggedIn => true;

  @override
  String? get currentUsername => 'fixture_login';

  @override
  Future<ForumHomeSnapshot> fetchHome() async => const ForumHomeSnapshot(
        latest: [
          ForumThread(
            title: 'Topic',
            url: 'read.php?tid-1.html',
            replies: 0,
            section: 'Board',
          ),
        ],
        hot: [],
        sections: [],
      );

  @override
  Future<ForumTaskSnapshot?> loadCachedForumTaskSnapshot() async => null;

  @override
  Future<ForumTaskQuickClaimResult?> autoClaimForumTaskRewardsIfDue() async =>
      null;
}
