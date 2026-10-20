import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/user_note.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/user_note_store.dart';
import 'package:south_plus_rewrite/services/user_tag_store.dart';

class _LoginClient extends ForumClient {
  String? username;
  bool loggedIn = false;
  @override
  bool get isLoggedIn => loggedIn;
  @override
  Future<void> restoreCookies() async {}
  @override
  Future<void> clearSession() async {
    loggedIn = false;
    username = null;
  }

  @override
  Future<String> get(String path) async =>
      username == null ? '' : '<a href="u.php">$username</a>';

  @override
  Future<
      ({
        String response,
        int credentialGeneration,
        bool installedCredentials
      })> postLogin(Map<String, String> form) async {
    final response = await post('login.php', form);
    return (
      response: response,
      credentialGeneration: credentialGeneration,
      installedCredentials: isLoggedIn
    );
  }

  @override
  Future<String> post(String path, Map<String, String> form) async {
    username = form['pwuser'];
    loggedIn = true;
    return '<a href="u.php">$username</a>';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('notes follow the final account on login and logout, never the old one',
      () async {
    await UserNoteStore.save('1', 'guest note');
    await UserNoteStore.save('1', 'account note', account: 'Fixture One');
    await UserTagStore.save('1', ['guest tag']);
    await UserTagStore.save('1', ['account tag'], account: 'Fixture One');
    final repository = ForumRepository(client: _LoginClient());
    final notes = UserNoteController(repository);
    addTearDown(notes.dispose);
    await pumpEventQueue();
    expect(notes.noteFor('1'), 'guest note');

    await repository.login(
        username: 'Fixture One', password: 'fixture', captcha: '1234');
    await pumpEventQueue();
    expect(notes.noteFor('1'), 'account note');
    expect(notes.tagsFor('1'), ['account tag']);

    await repository.clearSession();
    await pumpEventQueue();
    expect(notes.noteFor('1'), 'guest note');
    expect(notes.tagsFor('1'), ['guest tag']);
  });

  test('a custom origin guest has its own notes and never sees official ones',
      () async {
    await UserNoteStore.save('1', 'official guest');
    final repository = ForumRepository(client: _LoginClient());
    final notes = UserNoteController(repository);
    addTearDown(notes.dispose);
    await pumpEventQueue();
    expect(notes.noteFor('1'), 'official guest');

    await repository.updateNetworkConfig(const ForumNetworkConfig(
      site: ForumSite('first.invalid'),
      mode: ForumNetworkMode.native,
      dohProvider: ForumNetworkConfig.defaultProvider,
    ));
    expect(notes.noteFor('1'), isNull);
    await pumpEventQueue();
    expect(notes.noteFor('1'), isNull,
        reason: 'the custom guest scope starts empty');

    await UserNoteStore.save('1', 'custom guest',
        account: repository.localPreferenceAccount);
    await pumpEventQueue();
    expect(notes.noteFor('1'), 'custom guest');

    await repository.updateNetworkConfig(const ForumNetworkConfig(
      site: ForumNetworkConfig.defaultSite,
      mode: ForumNetworkMode.native,
      dohProvider: ForumNetworkConfig.defaultProvider,
    ));
    await pumpEventQueue();
    expect(notes.noteFor('1'), 'official guest');
  });

  testWidgets('an open note editor is dismissed alone when the scope changes',
      (tester) async {
    final repository = ForumRepository(client: _LoginClient());
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showUserNoteEditor(
              context,
              repository: repository,
              uid: '1',
              name: 'Alice',
              note: 'old note',
              tags: const ['old tag'],
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('备注与标签'), findsOneWidget);
    expect(find.text('old note'), findsOneWidget);
    expect(find.text('old tag'), findsOneWidget);

    await repository.updateNetworkConfig(const ForumNetworkConfig(
      site: ForumSite('first.invalid'),
      mode: ForumNetworkMode.native,
      dohProvider: ForumNetworkConfig.defaultProvider,
    ));
    await tester.pumpAndSettle();

    expect(find.text('备注与标签'), findsNothing);
    expect(find.text('old note'), findsNothing);
    expect(find.text('old tag'), findsNothing);
    expect(find.text('open'), findsOneWidget, reason: 'the page below stays');
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('备注与标签'), findsOneWidget, reason: 'reopening works');
  });
}
