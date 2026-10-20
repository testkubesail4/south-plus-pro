import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/editor/windcode_toolbar.dart';
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
      replyPath: 'message.php?action-write-remid-14.html',
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

  testWidgets(
      'logout removes a private compose preview from its separate modal route',
      (tester) async {
    const draft = 'fixture-owner-a modal-only private draft';
    final repository = _PrivacyRepository('fixture-owner-a');
    await _open(tester, repository, _Surface.compose);
    await tester.enterText(find.byType(TextField).at(2), draft);
    await tester.tap(find.byTooltip('预览'));
    await tester.pumpAndSettle();
    final sheet = find.byType(DraggableScrollableSheet, skipOffstage: false);
    final privatePreview = find.descendant(
        of: sheet,
        matching:
            find.textContaining(draft, findRichText: true, skipOffstage: false),
        skipOffstage: false);
    expect(sheet, findsOneWidget);
    expect(privatePreview, findsWidgets,
        reason:
            'Only the separate preview is measured, not the compose below it');
    final semantics = tester.ensureSemantics();
    try {
      repository.changeOwner(null);
      await tester.pump();
      expect(privatePreview, findsNothing);
      expect(
          find.descendant(
              of: sheet,
              matching: find.bySemanticsLabel(RegExp(draft)),
              skipOffstage: false),
          findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('a font picker cannot write into a retired PM editor',
      (tester) async {
    final repository = _PrivacyRepository('fixture-owner-a');
    await _open(tester, repository, _Surface.compose);
    expect(find.textContaining('fixture-owner-a'), findsWidgets);
    await tester.ensureVisible(find.byType(WindCodeToolbar));
    if (find.byTooltip('字号').evaluate().isEmpty) {
      final more = find.byTooltip('更多');
      expect(more.hitTestable(), findsOneWidget);
      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.tap(find.text('字号'));
    } else {
      await tester.tap(find.byTooltip('字号'));
    }
    await tester.pumpAndSettle();
    final choice = find.text('5');
    expect(choice.hitTestable(), findsOneWidget);
    repository.changeOwner('fixture-owner-b');
    await tester.pump();
    expect(find.textContaining('fixture-owner-a', skipOffstage: false),
        findsNothing,
        reason:
            'The editor must actually retire before the old picker returns');
    await tester.pumpAndSettle();
    if (choice.evaluate().isNotEmpty) {
      expect(choice.hitTestable(), findsOneWidget);
      await tester.tap(choice);
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason:
            'A separate picker cannot write to the disposed editor controller');
    expect(find.textContaining('fixture-owner-a', skipOffstage: false),
        findsNothing);
  });

  testWidgets(
      'nested PM reply revocation preserves the root and an unrelated new-account route',
      (tester) async {
    final repository = _PrivacyRepository('fixture-owner-a');
    await _open(tester, repository, _Surface.detail);
    await tester.tap(find.text('回复'));
    await tester.pumpAndSettle();
    expect(find.byType(PmComposeScreen), findsOneWidget);
    expect(find.textContaining('fixture-owner-a private body'), findsWidgets);
    final navigator =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    repository.changeOwner('fixture-owner-b');
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('New account route')),
        body: const Text('fixture-owner-b unrelated route'),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('fixture-owner-a', skipOffstage: false),
        findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('fixture-owner-b unrelated route').hitTestable(),
        findsOneWidget,
        reason: 'Old scope listeners may only revoke routes they still own');
    final rootRetained = find
        .text('Open private surface', skipOffstage: false)
        .evaluate()
        .isNotEmpty;
    debugPrint(
        'PM_NESTED canReturn=${navigator.canPop()} rootRetained=$rootRetained');
    expect(rootRetained, isTrue,
        reason: 'The original root route remains below the new-account route');
    expect(navigator.canPop(), isTrue,
        reason:
            'The unrelated new-account route must still have a safe return');
    await tester.pageBack();
    await tester.pumpAndSettle();
    // At most the two original private routes can remain as closed notices.
    for (var remaining = 2; remaining > 0; remaining--) {
      if (find.text('Open private surface').hitTestable().evaluate().isNotEmpty)
        break;
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    expect(find.text('Open private surface').hitTestable(), findsOneWidget,
        reason: 'Revocation must not pop the root Navigator route');
    expect(tester.takeException(), isNull);
  });
}
