import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/auth/login_screen.dart';
import 'package:south_plus_rewrite/features/common/session_bound.dart';
import 'package:south_plus_rewrite/features/profile/account_screen.dart';
import 'package:south_plus_rewrite/features/profile/account_switcher_sheet.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_account_registry.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// test-audit authoring gate:
// 1) Protects AccountScreen switcher entry, add-mode stack (no popUntil),
//    private SessionBound survival on cancel-add, and active display after select.
// 2) Credible regressions: opening switcher missing, add login clearing the
//    stack, cancel-add bumping epoch / emptying private pages, wrong identity.
// 3) Distinct from account_switcher_sheet_ui_test (sheet chrome) and
//    account_page_ui_test (row inventory).
// 4) Fake ForumRepository only; no production seams.
// Legacy lifecycle cases use AccountScreen -> openLogin with guest or expired
// active credentials. They cover cancellation, late errors, and success cleanup.

class _FakeRepo extends ForumRepository {
  _FakeRepo({
    List<AccountSummary> accounts = const [],
    AccountSummary? active,
  }) : super(
          config: const ForumNetworkConfig(site: ForumSite('fixture.invalid')),
        ) {
    _accounts.value = accounts;
    _active.value = active;
    if (active != null) {
      _identity.value = ForumAccountIdentity(
        systemName: active.systemName ?? active.displayName,
        uid: active.uid,
        avatarUrl: active.avatarUrl,
      );
      _sessionUser.value = active.systemName ?? active.displayName;
      loggedIn = true;
    }
  }

  bool loggedIn = false;
  final _accounts = ValueNotifier<List<AccountSummary>>(const []);
  final _active = ValueNotifier<AccountSummary?>(null);
  final _identity = ValueNotifier<ForumAccountIdentity?>(null);
  final _sessionUser = ValueNotifier<String?>(null);
  final _sessionEpoch = ValueNotifier<int>(0);

  int loginChallengeCalls = 0;
  int loginSubmitCalls = 0;
  int cancelLoginCalls = 0;
  Completer<LoginChallenge>? loginChallengeGate;
  Completer<LoginResult>? loginSubmitGate;

  int addChallengeCalls = 0;
  int cancelAddCalls = 0;
  int reauthChallengeCalls = 0;
  int cancelReauthCalls = 0;
  String? lastReauthId;
  ForumNetworkConfig _network =
      const ForumNetworkConfig(site: ForumSite('fixture.invalid'));

  void changeSite(String host) {
    _network = ForumNetworkConfig(site: ForumSite(host));
    _sessionEpoch.value++;
  }

  @override
  ForumNetworkConfig get networkConfig => _network;
  int selectCalls = 0;
  String? lastSelectedId;
  bool selectThrows = false;
  Completer<void>? selectGate;

  @override
  bool get isLoggedIn => loggedIn;
  @override
  String? get currentUsername => _sessionUser.value;
  @override
  ValueListenable<List<AccountSummary>> get accounts => _accounts;
  @override
  ValueListenable<AccountSummary?> get activeAccount => _active;
  @override
  ValueListenable<ForumAccountIdentity?> get accountIdentity => _identity;
  @override
  ValueListenable<String?> get sessionUser => _sessionUser;
  @override
  ValueListenable<int> get sessionEpoch => _sessionEpoch;

  @override
  Future<void> loadAccountNickname() async {}

  @override
  Future<void> selectAccount(String accountId) async {
    selectCalls++;
    lastSelectedId = accountId;
    if (selectThrows) {
      throw StateError('select failed');
    }
    final next = _accounts.value.map((account) {
      final active = account.id == accountId;
      return account.copyWith(isActive: active);
    }).toList();
    _accounts.value = next;
    final active = next.cast<AccountSummary?>().firstWhere(
          (account) => account?.id == accountId,
          orElse: () => null,
        );
    _active.value = active;
    loggedIn = active != null && active.status == AccountReadyState.ready;
    _identity.value = active == null
        ? null
        : ForumAccountIdentity(
            systemName: active.systemName ?? active.displayName,
            uid: active.uid,
            avatarUrl: active.avatarUrl,
          );
    _sessionUser.value = active?.systemName ?? active?.displayName;
    _sessionEpoch.value++;
    await selectGate?.future;
  }

  @override
  Future<void> logoutCurrent() async {
    _accounts.value = [
      for (final account in _accounts.value)
        account.copyWith(
            status: AccountReadyState.needsReauth, isActive: false),
    ];
    _active.value = null;
    loggedIn = false;
    _identity.value = null;
    _sessionUser.value = null;
    _sessionEpoch.value++;
  }

  @override
  Future<void> removeAccount(String accountId) async {
    final wasActive = _active.value?.id == accountId;
    _accounts.value = [
      for (final account in _accounts.value)
        if (account.id != accountId) account
    ];
    if (wasActive) {
      _active.value = null;
      loggedIn = false;
      _identity.value = null;
      _sessionUser.value = null;
      _sessionEpoch.value++;
    }
  }

  @override
  Future<LoginChallenge> fetchLoginChallenge() async {
    loginChallengeCalls++;
    final gate = loginChallengeGate;
    return gate == null ? _challenge() : await gate.future;
  }

  @override
  Future<LoginResult> submitLogin({
    required String username,
    required String password,
    required String captcha,
    required Map<String, String> fields,
  }) async {
    loginSubmitCalls++;
    final gate = loginSubmitGate;
    return gate == null
        ? const LoginResult(success: true, message: '登录成功')
        : await gate.future;
  }

  @override
  Future<void> cancelLogin() async {
    cancelLoginCalls++;
  }

  @override
  Future<LoginChallenge> fetchAddAccountChallenge() async {
    addChallengeCalls++;
    return _challenge();
  }

  @override
  Future<LoginChallenge> fetchReauthChallenge(String accountId) async {
    reauthChallengeCalls++;
    lastReauthId = accountId;
    return _challenge();
  }

  LoginChallenge _challenge() {
    // 1x1 PNG so LoginScreen can decode the captcha image in tests.
    return LoginChallenge(
      fields: const {'step': '2'},
      captchaBytes: Uint8List.fromList(const [
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x0D,
        0x49,
        0x48,
        0x44,
        0x52,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x01,
        0x08,
        0x02,
        0x00,
        0x00,
        0x00,
        0x90,
        0x77,
        0x53,
        0xDE,
        0x00,
        0x00,
        0x00,
        0x0C,
        0x49,
        0x44,
        0x41,
        0x54,
        0x08,
        0xD7,
        0x63,
        0xF8,
        0xCF,
        0xC0,
        0x00,
        0x00,
        0x00,
        0x03,
        0x00,
        0x01,
        0x00,
        0x05,
        0xFE,
        0x02,
        0xFE,
        0xDC,
        0xCC,
        0x59,
        0xE7,
        0x00,
        0x00,
        0x00,
        0x00,
        0x49,
        0x45,
        0x4E,
        0x44,
        0xAE,
        0x42,
        0x60,
        0x82,
      ]),
    );
  }

  @override
  Future<void> cancelAddAccount() async {
    cancelAddCalls++;
  }

  @override
  Future<void> cancelReauthAccount() async {
    cancelReauthCalls++;
  }

  @override
  Future<List<BrowsingHistoryEntry>> browsingHistory({int limit = 100}) async =>
      const [];

  @override
  Future<UserProfile?> cachedUserProfileOverview(String url) async => null;

  @override
  Future<UserProfile> fetchUserProfileOverview(String url) async =>
      UserProfile(uid: '1', name: 'Alice', url: url);

  @override
  Future<UserProfile> fetchUserProfileDetails(UserProfile overview,
          {bool forceReload = false}) async =>
      overview;
}

AccountSummary _account({
  required String id,
  required String name,
  required String uid,
  bool active = false,
  AccountReadyState status = AccountReadyState.ready,
}) =>
    AccountSummary(
      id: id,
      displayName: name,
      systemName: name,
      uid: uid,
      status: status,
      isActive: active,
    );

Future<void> _pumpAccount(
  WidgetTester tester,
  _FakeRepo repository, {
  bool rebuildOnSession = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: ValueListenableBuilder<int>(
      valueListenable: repository.sessionEpoch,
      builder: (context, epoch, _) => Scaffold(
        body: AccountScreen(
          key: rebuildOnSession ? ValueKey(epoch) : null,
          repository: repository,
          onLoggedOut: () {},
        ),
      ),
    ),
  ));
  await tester.pump();
}

Future<void> _submitLegacySignIn(WidgetTester tester) async {
  Finder field(String label) => find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );
  await tester.enterText(field('用户名'), 'Bob');
  await tester.enterText(field('密码'), 'fixture-password');
  await tester.enterText(field('验证码'), '1234');
  await tester.tap(find.widgetWithText(FilledButton, '登录'));
  await tester.pump();
}

void main() {
  final alice = _account(
    id: 'https://fixture.invalid\u001f1',
    name: 'Alice',
    uid: '1',
    active: true,
  );
  final bob = _account(
    id: 'https://fixture.invalid\u001f2',
    name: 'Bob',
    uid: '2',
  );

  for (final retainedAccount in [false, true]) {
    for (final pendingSubmit in [false, true]) {
      testWidgets(
          'legacy sign-in cancels on back (retained account=$retainedAccount, submit=$pendingSubmit)',
          (tester) async {
        final repo = _FakeRepo(
          accounts: retainedAccount ? [alice] : [],
          active: retainedAccount ? alice : null,
        )..loggedIn = false;
        final challengeGate = Completer<LoginChallenge>();
        final submitGate = Completer<LoginResult>();
        if (pendingSubmit) {
          repo.loginSubmitGate = submitGate;
        } else {
          repo.loginChallengeGate = challengeGate;
        }
        final activeBefore = repo.activeAccount.value;
        final identityBefore = repo.accountIdentity.value;
        final accountsBefore = [...repo.accounts.value];
        final epochBefore = repo.sessionEpoch.value;
        await _pumpAccount(tester, repo);
        await tester.tap(find.text('登录南+账号'));
        if (pendingSubmit) {
          await tester.pumpAndSettle();
          await _submitLegacySignIn(tester);
          expect(repo.loginSubmitCalls, 1);
        } else {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
        }

        final login = find.byType(LoginScreen);
        expect(tester.widget<LoginScreen>(login).mode, LoginMode.signIn);
        expect(repo.loginChallengeCalls, 1);
        final loginState = tester.state(login);
        final messenger = ScaffoldMessenger.of(tester.element(login));
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(loginState.mounted, isFalse);
        expect(find.byType(AccountScreen), findsOneWidget);

        if (pendingSubmit) {
          await tester.pumpWidget(const MaterialApp(
            key: ValueKey('replacement after cancelled login'),
            home: Scaffold(body: Text('Replacement home')),
          ));
          await tester.pump();
          expect(messenger.mounted, isFalse);
          submitGate.completeError(StateError('late sign-in failure'));
        } else {
          challengeGate.complete(repo._challenge());
        }
        await tester.pumpAndSettle();

        expect(repo.cancelLoginCalls, 1);
        expect(repo.cancelAddCalls, 0);
        expect(repo.cancelReauthCalls, 0);
        expect(repo.activeAccount.value, activeBefore);
        expect(repo.accountIdentity.value, identityBefore);
        expect(repo.accounts.value, accountsBefore);
        expect(repo.sessionEpoch.value, epochBefore);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
        'successful legacy sign-in closes without cancelling (retained account=$retainedAccount)',
        (tester) async {
      final repo = _FakeRepo(
        accounts: retainedAccount ? [alice] : [],
        active: retainedAccount ? alice : null,
      )..loggedIn = false;
      await _pumpAccount(tester, repo);
      await tester.tap(find.text('登录南+账号'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<LoginScreen>(find.byType(LoginScreen)).mode,
        LoginMode.signIn,
      );
      await _submitLegacySignIn(tester);
      await tester.pumpAndSettle();

      expect(repo.loginSubmitCalls, 1);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(repo.cancelLoginCalls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('我的 opens the switcher from 切换账号', (tester) async {
    final repo = _FakeRepo(accounts: [alice, bob], active: alice);
    await _pumpAccount(tester, repo);
    await tester.tap(find.text('切换账号'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountSwitcherSheet), findsOneWidget);
    expect(find.text('Alice'), findsWidgets);
    expect(find.text('Bob'), findsOneWidget);
  });

  for (final rebuildOnSession in [false, true]) {
    testWidgets(
        'selecting another account closes after persistence (tab rebuilt=$rebuildOnSession)',
        (tester) async {
      final gate = Completer<void>();
      final repo = _FakeRepo(accounts: [alice, bob], active: alice)
        ..selectGate = gate;
      await _pumpAccount(tester, repo, rebuildOnSession: rebuildOnSession);
      await tester.tap(find.text('切换账号'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bob'));
      await tester.pump();
      expect(repo.selectCalls, 1);
      expect(repo.lastSelectedId, bob.id);
      expect(find.byType(AccountSwitcherSheet), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AccountSwitcherSheet), findsNothing);
      expect(find.text('Bob'), findsOneWidget);
    });
  }

  for (final reauthenticate in [false, true]) {
    testWidgets(
        'opening login replaces the switcher route (reauth=$reauthenticate)',
        (tester) async {
      final saved = reauthenticate
          ? alice.copyWith(
              status: AccountReadyState.needsReauth,
              isActive: false,
            )
          : alice;
      final repo = _FakeRepo(
        accounts: [saved],
        active: reauthenticate ? null : saved,
      );
      await _pumpAccount(tester, repo);
      await tester.tap(find.text('切换账号'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(reauthenticate ? '重新登录' : '添加账号'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        find.byType(AccountSwitcherSheet, skipOffstage: false),
        findsNothing,
      );
      if (reauthenticate) {
        expect(repo.reauthChallengeCalls, 1);
        expect(repo.lastReauthId, alice.id);
      } else {
        expect(repo.addChallengeCalls, 1);
      }

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(find.byType(AccountSwitcherSheet), findsNothing);
      expect(reauthenticate ? repo.cancelReauthCalls : repo.cancelAddCalls, 1);
    });
  }

  testWidgets('reauth without a saved username does not submit UID as username',
      (tester) async {
    const saved = AccountSummary(
      id: 'https://fixture.invalid\u001f42',
      displayName: 'Saved account',
      uid: '42',
      status: AccountReadyState.needsReauth,
    );
    final repo = _FakeRepo(accounts: [saved]);
    await _pumpAccount(tester, repo);
    await tester.tap(find.text('切换账号'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新登录'));
    await tester.pumpAndSettle();

    final username = tester.widget<TextField>(find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '用户名',
    ));
    expect(username.controller!.text, isEmpty);
    expect(repo.lastReauthId, saved.id);
  });

  testWidgets(
      'switcher follows the current site without listing foreign accounts',
      (tester) async {
    final foreign = alice.copyWith(
      id: alice.id.replaceFirst('fixture.invalid', 'other.invalid'),
      displayName: 'Other site',
      systemName: 'Other site',
      isActive: false,
    );
    final repo = _FakeRepo(accounts: [alice, foreign], active: alice);
    await _pumpAccount(tester, repo);
    await tester.tap(find.text('切换账号'));
    await tester.pumpAndSettle();
    final sheet = find.byType(AccountSwitcherSheet);
    expect(
      find.descendant(of: sheet, matching: find.text('Alice')),
      findsOneWidget,
    );
    expect(find.text('Other site'), findsNothing);

    repo.changeSite('other.invalid');
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: sheet, matching: find.text('Alice')),
      findsNothing,
    );
    expect(find.text('Other site'), findsOneWidget);
  });

  testWidgets(
      'foreign-only accounts keep the current site in the add empty state',
      (tester) async {
    final foreign = alice.copyWith(
      id: alice.id.replaceFirst('fixture.invalid', 'other.invalid'),
      displayName: 'Other site',
      systemName: 'Other site',
      isActive: false,
    );
    final repo = _FakeRepo(accounts: [foreign]);
    await _pumpAccount(tester, repo);
    expect(find.text('切换账号'), findsNothing);
    await tester.tap(find.byTooltip('切换账号'));
    await tester.pumpAndSettle();
    expect(find.text('Other site'), findsNothing);
    expect(find.text('添加账号'), findsOneWidget);
    expect(find.byTooltip('账号操作'), findsNothing);
  });

  testWidgets('add account does not popUntil private routes', (tester) async {
    final repo = _FakeRepo(accounts: [alice], active: alice);
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(
            children: [
              Expanded(
                child: AccountScreen(repository: repo, onLoggedOut: () {}),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SessionBound(
                        repository: repo,
                        title: '短消息',
                        child: const Scaffold(
                          body: Center(child: Text('secret draft')),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('open-private'),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('open-private'));
    await tester.pumpAndSettle();
    expect(find.text('secret draft'), findsOneWidget);
    final epochBefore = repo.sessionEpoch.value;

    unawaited(openAddAccount(tester.element(find.text('secret draft')), repo));
    await tester.pumpAndSettle();
    expect(find.text('添加账号'), findsWidgets);
    expect(repo.addChallengeCalls, 1);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('secret draft'), findsOneWidget);
    expect(find.text('账号已切换'), findsNothing);
    expect(repo.sessionEpoch.value, epochBefore);
    expect(repo.cancelAddCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('a completed switch never closes a route opened after its sheet',
      (tester) async {
    final gate = Completer<void>();
    final repo = _FakeRepo(accounts: [alice, bob], active: alice)
      ..selectGate = gate;
    await _pumpAccount(tester, repo);
    await tester.tap(find.text('切换账号'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bob'));
    await tester.pump();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    unawaited(navigator.push<void>(MaterialPageRoute(
      builder: (_) => const Scaffold(body: Text('External destination')),
    )));
    await tester.pumpAndSettle();
    expect(find.text('External destination'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('External destination'), findsOneWidget);
    expect(
        find.byType(AccountSwitcherSheet, skipOffstage: false), findsNothing);
  });

  testWidgets('select failure stays on sheet with 切换失败', (tester) async {
    final repo = _FakeRepo(accounts: [alice, bob], active: alice)
      ..selectThrows = true;
    await _pumpAccount(tester, repo);
    await tester.tap(find.text('切换账号'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountSwitcherSheet), findsOneWidget);

    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();

    expect(find.text('切换失败'), findsOneWidget);
    expect(find.byType(AccountSwitcherSheet), findsOneWidget);
    expect(repo.selectCalls, 1);
  });
}
