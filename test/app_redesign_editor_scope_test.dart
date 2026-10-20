import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/reply/thread_edit_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_compose_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

import 'app_redesign_fixture.dart';

const _link = ThreadActionLink(
  label: '编辑',
  url: 'post.php?action-modify-fid-8-tid-7-pid-501-article-1.html',
);
const _board = ForumCategory(
  name: 'Fixture board',
  slug: 'f9',
  url: 'https://fixture.invalid/thread.php?fid-9.html',
);
const _private = 'fixture-owner-a private BBCode';
ThreadEditDraft _draft() => ThreadEditDraft(
      title: 'fixture-owner-a private title',
      content: '[b]$_private[/b]',
      fields: const {},
      controls: const [],
      actionPath: 'post.php?',
    );

class _EditorRepository extends AppRedesignRepository {
  _EditorRepository({this.bounty = false});

  final bool bounty;
  final reads = <(String?, Completer<ThreadEditDraft>)>[];

  @override
  Future<ThreadEditDraft> fetchEditDraft(ThreadActionLink link) {
    final result = Completer<ThreadEditDraft>();
    reads.add((currentUsername, result));
    return result.future;
  }

  @override
  Future<ThreadComposeDraft> fetchThreadComposeDraft(
    ForumCategory category,
  ) async =>
      ThreadComposeDraft(
        categories: const [],
        selectedCategory: '',
        bountySupported: bounty,
        controls: const [],
        actionPath: 'post.php?',
        fid: '9',
        defaultBestAmount: 20,
        defaultHelpfulAmount: 10,
        minBestAmount: 20,
        minHelpfulAmount: 10,
        bountyCurrency: 'SP币',
      );
}

Future<void> _open(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => page)),
            child: const Text('Open editor'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void _expectOldOwnerGone() {
  expect(
    find.textContaining('fixture-owner-a', skipOffstage: false),
    findsNothing,
    reason:
        'The retired editor may not retain original BBCode or an unsent draft',
  );
  expect(find.bySemanticsLabel(RegExp('fixture-owner-a')), findsNothing);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'an account change removes an open edit form in the first frame',
    (tester) async {
      final repository = _EditorRepository();
      await _open(
        tester,
        ThreadEditScreen(
          repository: repository,
          link: _link,
          openingPost: false,
        ),
      );
      expect(repository.reads.single.$1, 'fixture-owner-a');
      repository.reads.single.$2.complete(_draft());
      await tester.pumpAndSettle();
      expect(find.textContaining(_private), findsOneWidget);
      final semantics = tester.ensureSemantics();
      try {
        repository.changeOwner('fixture-owner-b');
        await tester.pump();
        _expectOldOwnerGone();
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'an edit form finishing after an account change cannot restore A',
    (tester) async {
      final repository = _EditorRepository();
      await _open(
        tester,
        ThreadEditScreen(
          repository: repository,
          link: _link,
          openingPost: false,
        ),
      );
      expect(repository.reads.single.$1, 'fixture-owner-a');
      final old = repository.reads.single.$2;
      repository.changeOwner('fixture-owner-b');
      await tester.pump();
      old.complete(_draft());
      await tester.pumpAndSettle();
      _expectOldOwnerGone();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a retired bounty confirmation cannot paint the previous amount',
      (tester) async {
    final repository = _EditorRepository(bounty: true);
    await _open(
        tester, ThreadComposeScreen(repository: repository, category: _board));
    await tester.enterText(
        find.byType(TextField).first, 'fixture-owner-a bounty title');
    await tester.enterText(
        find.widgetWithText(TextField, '正文'), 'fixture-owner-a bounty body');
    await tester.enterText(
        find.byKey(const ValueKey('compose-bounty-best')), '37');
    await tester.enterText(
        find.byKey(const ValueKey('compose-bounty-helpful')), '11');
    final submit = find.byKey(const ValueKey('compose-submit'));
    expect(submit.hitTestable(), findsOneWidget);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    final amount = find.text('确认发布并扣除 85 SP币', skipOffstage: false);
    expect(amount.hitTestable(), findsOneWidget);
    final semantics = tester.ensureSemantics();
    try {
      repository.changeOwner('fixture-owner-b');
      await tester.pump();
      final spoken = find.semantics.byLabel(RegExp('85 SP币'));
      debugPrint(
          'BOUNTY_RETIRED amountNodes=${amount.evaluate().length} semantics=${spoken.evaluate().length}');
      expect(find.textContaining('fixture-owner-a', skipOffstage: false),
          findsNothing);
      expect(amount, findsNothing,
          reason:
              'Closing-route animation may not retain the retired owner amount');
      expect(spoken, findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'an account change removes the unsent new-thread draft in the first frame',
    (tester) async {
      final repository = _EditorRepository();
      await _open(
        tester,
        ThreadComposeScreen(repository: repository, category: _board),
      );
      await tester.enterText(
        find.byType(TextField).first,
        'fixture-owner-a unsent title',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '正文'),
        'fixture-owner-a unsent body',
      );
      expect(find.textContaining('fixture-owner-a'), findsNWidgets(2));
      final semantics = tester.ensureSemantics();
      try {
        repository.changeOwner('fixture-owner-b');
        await tester.pump();
        _expectOldOwnerGone();
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}
