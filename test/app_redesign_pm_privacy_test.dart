import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/messages/pm_compose_screen.dart';
import 'package:south_plus_rewrite/features/messages/pm_detail_screen.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

import 'app_redesign_fixture.dart';

enum _Surface { detail, chatlog, compose }

const _message = ForumPmSummary(
  box: ForumPmBox.inbox,
  type: ForumPmType.personal,
  id: '14',
  peer: 'fixture-peer',
  title: 'Fixture private message',
  time: '2026-01-01',
  detailPath: 'message.php?action-read-mid-14.html',
);

class _PrivacyRepository extends AppRedesignRepository {
  _PrivacyRepository(String user) : super(user: user);

  Completer<void>? gate;
  final requestedOwners = <String>[];

  Future<String> _readOwner() async {
    final owner = currentUsername!;
    requestedOwners.add(owner);
    await gate?.future;
    return owner;
  }

  @override
  Future<ForumPmDetail> fetchPmDetail(ForumPmSummary message) async {
    final owner = await _readOwner();
    return ForumPmDetail(
      summary: message,
      sender: 'fixture-peer',
      title: '$owner private title',
      time: '2026-01-01',
      content: '$owner private body',
    );
  }

  @override
  Future<ForumPmChatlog> fetchPmChatlog(String path) async {
    final owner = await _readOwner();
    return ForumPmChatlog(records: [
      ForumPmChatRecord(
        id: '14',
        sender: 'fixture-peer',
        title: '$owner private title',
        time: '2026-01-01',
        content: '$owner private body',
      ),
    ]);
  }

  @override
  Future<ForumPmCompose> fetchPmCompose({String? path}) async {
    final owner = await _readOwner();
    return ForumPmCompose(
      actionPath: 'message.php',
      fields: const {},
      recipientUid: '901',
      title: '$owner private title',
      body: '$owner private body',
    );
  }
}

Future<void> _open(WidgetTester tester, _PrivacyRepository repository,
    _Surface surface) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Widget page() => switch (surface) {
        _Surface.detail =>
          PmDetailScreen(repository: repository, message: _message),
        _Surface.chatlog => PmChatlogScreen(
            repository: repository,
            path: 'message.php?action=chatlog&withuid=901'),
        _Surface.compose => PmComposeScreen(repository: repository),
      };
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => page())),
          child: const Text('Open private surface'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open private surface'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  if (repository.gate == null) await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (surface, oldOwner, newOwner) in const [
    (_Surface.detail, 'fixture-owner-a', 'fixture-owner-b'),
    (_Surface.chatlog, 'fixture-owner-b', 'fixture-owner-a'),
    (_Surface.compose, 'fixture-owner-a', null),
  ]) {
    testWidgets(
        '$surface removes $oldOwner private content in the first frame after $newOwner',
        (tester) async {
      final repository = _PrivacyRepository(oldOwner);
      await _open(tester, repository, surface);
      if (surface == _Surface.compose) {
        await tester.enterText(
            find.byType(TextField).at(2), '$oldOwner unsent private draft');
      }
      expect(find.textContaining(oldOwner), findsWidgets,
          reason: 'The test must start with actual private content or a draft');
      final semantics = tester.ensureSemantics();
      try {
        repository.changeOwner(newOwner);
        await tester.pump();
        expect(find.textContaining(oldOwner, skipOffstage: false), findsNothing,
            reason:
                'An outgoing route cannot retain old private text or editing controllers');
        expect(find.bySemanticsLabel(RegExp(oldOwner)), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('a late compose form cannot restore the previous owner draft',
      (tester) async {
    final repository = _PrivacyRepository('fixture-owner-a')
      ..gate = Completer<void>();
    await _open(tester, repository, _Surface.compose);
    expect(repository.requestedOwners.first, 'fixture-owner-a');
    repository.changeOwner('fixture-owner-b');
    await tester.pump();
    repository.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('fixture-owner-a', skipOffstage: false),
        findsNothing,
        reason: 'Resolving the old future must not repopulate private content');
    expect(tester.takeException(), isNull);
  });
}
