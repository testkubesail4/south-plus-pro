import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/home/home_shell.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// test-audit authoring gate:
// 1) Protects home_layout_shape bucket = stable localPreferenceAccount, not
//    display username; late save after switch must not write the new scope.
// 2) Credible regressions: two origins sharing username reuse one shape key;
//    fetch completing after switch saves under the new account / username.
// 3) Distinct from home_layout_ui_test (geometry/skeleton chrome) — this owns
//    the account-scope isolation contract only.
// 4) Fake ForumRepository + SharedPreferences; Completer gates, no sleep.

ForumThread _thread(String title) => ForumThread(
      title: title,
      url: 'read.php?tid-1.html',
      replies: 0,
      section: '',
    );

String _shapeKey(String? account) =>
    'home_layout_shape/${Uri.encodeComponent(account ?? '')}';

class _ScopeRepo extends ForumRepository {
  _ScopeRepo({
    required this.scope,
  });

  String scope;
  String? username = 'same_display_name';
  final epoch = ValueNotifier<int>(0);
  Completer<void>? homeGate;
  var fetchCalls = 0;

  void switchScope(String next) {
    scope = next;
    epoch.value++;
  }

  @override
  String? get currentUsername => username;

  @override
  String get localPreferenceAccount => scope;

  @override
  ValueListenable<int> get sessionEpoch => epoch;

  @override
  bool get isLoggedIn => username != null;

  @override
  Future<ForumHomeSnapshot> fetchHome() async {
    fetchCalls++;
    await homeGate?.future;
    return ForumHomeSnapshot(
      latest: [_thread('Latest 1')],
      quickLists: const [
        ForumQuickList(title: '最新讨论'),
        ForumQuickList(title: '最新回复'),
      ],
      hot: [
        for (var i = 1; i <= 4; i++)
          ForumCategory(name: 'Hot $i', slug: 'fid-$i'),
      ],
      sections: [
        ForumSection(
          title: 'Boards',
          items: [
            ForumBoard(
              name: 'Fixture board',
              url: 'https://fixture.invalid/thread.php?fid-1.html',
              section: 'Boards',
              lastPostTitle: 'Topic',
              lastPostTime: '2026-01-01 10:00',
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<List<ForumThread>> fetchQuickList(ForumQuickList list) async => [];

  @override
  Future<void> loadAccountNickname() async {}
}

Finder _hotBones() => find.byWidgetPredicate(
      (widget) =>
          widget is ActionChip &&
          widget.label is Text &&
          (widget.label as Text).data == '\u3000' * 4,
    );

void main() {
  const scopeA = 'https://origin-a.example:account:same_display_name';
  const scopeB = 'https://origin-b.example:account:same_display_name';

  testWidgets(
      'same display username on two stable scopes keeps separate shapes',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      _shapeKey(scopeA): jsonEncode({
        'hot': 3,
        'sections': [
          [2]
        ],
      }),
      _shapeKey(scopeB): jsonEncode({
        'hot': 8,
        'sections': [
          [5]
        ],
      }),
      // Legacy username bucket must not win over stable scope.
      _shapeKey('same_display_name'): jsonEncode({
        'hot': 1,
        'sections': [
          [1]
        ],
      }),
    });

    final repo = _ScopeRepo(scope: scopeA)..homeGate = Completer<void>();
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: ForumHomePage(repository: repo),
    ));
    await tester.pump();
    await tester.pump();

    expect(_hotBones(), findsNWidgets(3),
        reason: 'scope A remembered hot=3, not username bucket hot=1');

    // Rebuild for scope B with the same display username.
    await tester.pumpWidget(MaterialApp(
      home: ForumHomePage(
        key: const ValueKey('b'),
        repository: _ScopeRepo(scope: scopeB)..homeGate = Completer<void>(),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(_hotBones(), findsNWidgets(8),
        reason: 'scope B remembered hot=8; scopes must not share');
  });

  testWidgets(
      'late home fetch after scope switch does not save under the new scope',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = _ScopeRepo(scope: scopeA)..homeGate = Completer<void>();

    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: ForumHomePage(repository: repo),
    ));
    await tester.pump();
    expect(repo.fetchCalls, 1);

    // Switch stable account while fetch is in flight (same display name).
    repo.switchScope(scopeB);
    await tester.pump();

    repo.homeGate!.complete();
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_shapeKey(scopeB)), isNull,
        reason: 'abandoned fetch must not write the new stable scope');
    expect(prefs.getString(_shapeKey('same_display_name')), isNull,
        reason: 'must not fall back to display-username bucket');
    // Old scope may or may not receive a write; !_current aborts — either is
    // fine so long as scope B stays clean.
    expect(prefs.getString(_shapeKey(scopeB)), isNull);
  });
}
