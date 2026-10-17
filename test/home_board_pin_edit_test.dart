import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/home/home_shell.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_search_preferences.dart';

// Synthetic boards only. The shared-preferences channel is the real storage
// boundary, so a write can be held and then rejected.
const _account = 'fixture_login';

class _Repo extends ForumRepository {
  @override
  bool get isLoggedIn => true;

  @override
  String? get currentUsername => _account;

  @override
  String? get localPreferenceAccount => _account;

  @override
  final accountIdentity = ValueNotifier(const ForumAccountIdentity(
      systemName: _account, nickname: 'Fixture user'));

  @override
  Future<ForumHomeSnapshot> fetchHome() async => ForumHomeSnapshot(
        latest: [],
        quickLists: [],
        hot: [ForumCategory(name: 'Hot board', slug: 'fid-7')],
        sections: [],
      );

  @override
  Future<ForumTaskSnapshot?> loadCachedForumTaskSnapshot() async => null;

  @override
  Future<ForumTaskQuickClaimResult?> autoClaimForumTaskRewardsIfDue() async =>
      null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final persisted = <String, Object>{};
  Completer<bool>? heldWrite;
  Completer<void>? writeStarted;

  setUp(() {
    SharedPreferences.resetStatic();
    persisted.clear();
    heldWrite = null;
    writeStarted = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') return Map<String, Object>.of(persisted);
      if (heldWrite case final held?) {
        heldWrite = null;
        writeStarted?.complete();
        if (!await held.future) return false;
      }
      final args = call.arguments as Map;
      persisted[args['key'] as String] = args['value'] as Object;
      return true;
    });
  });

  tearDown(() {
    SharedPreferences.resetStatic();
    messenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets(
      'a second pin edit waits while one save is pending, so a failed '
      'removal is never committed later', (tester) async {
    await ForumSearchPreferences.savePinnedBoards(
      const [
        ForumSearchPinnedBoard(id: '42', label: 'Pin one'),
        ForumSearchPinnedBoard(id: '43', label: 'Pin two'),
      ],
      account: _account,
    );
    tester.view.physicalSize = const Size(360, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: HomeShell(key: UniqueKey(), repository: _Repo()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑常用版块'), findsOneWidget);

    // The handler consumes heldWrite; this one releases it.
    final rejectedWrite = heldWrite = Completer<bool>();
    writeStarted = Completer<void>();
    await tester.tap(find.byTooltip('移除 Pin one'));
    await tester.pump();
    await writeStarted!.future;
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // The second removal is refused while the first is unacknowledged.
    await tester.tap(find.byTooltip('移除 Pin two'), warnIfMissed: false);
    await tester.pump();

    rejectedWrite.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('保存失败，请重试'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byTooltip('移除 Pin one'), findsOneWidget);
    expect(find.byTooltip('移除 Pin two'), findsOneWidget);
    expect(
      [
        for (final pin in (await ForumSearchPreferences.load(account: _account))
            .pinnedBoards)
          pin.label,
      ],
      ['Pin one', 'Pin two'],
    );

    // Idle again: the second removal is its own edit of the stored list.
    await tester.tap(find.byTooltip('移除 Pin two'));
    await tester.pumpAndSettle();
    expect(
      [
        for (final pin in (await ForumSearchPreferences.load(account: _account))
            .pinnedBoards)
          pin.label,
      ],
      ['Pin one'],
    );
  });
}
