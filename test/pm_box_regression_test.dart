import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/forum_link_opener.dart';
import 'package:south_plus_rewrite/features/messages/pm_box_screen.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_http_routing.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

import 'app_redesign_fixture.dart';

class _BoxRepository extends ForumRepository {
  _BoxRepository({this.collidingIds = false});

  final bool collidingIds;

  @override
  Future<ForumPmPage> fetchPmBox(ForumPmBox box, {String? pagePath}) =>
      SynchronousFuture(ForumPmPage(box: box, messages: [
        if (collidingIds) ...[
          for (final type in [ForumPmType.personal, ForumPmType.broadcast])
            ForumPmSummary(
              box: box,
              type: type,
              id: '701',
              peer: 'Fixture peer',
              title: '${type.name} identity 701',
              time: '2026-01-01',
              detailPath: type == ForumPmType.personal
                  ? 'message.php?action-read-mid-701.html'
                  : 'message.php?action-readpub-mid-701.html',
            ),
        ] else
          for (var i = 0; i < 16; i++)
            ForumPmSummary(
              box: box,
              type: box == ForumPmBox.inbox
                  ? ForumPmType.personal
                  : ForumPmType.sent,
              id: '${box.name}-$i',
              peer: 'Fixture peer',
              title: '${box.name} message $i',
              time: '2026-01-01',
              detailPath: 'message.php?action-read-mid-${100 + i}.html',
            ),
      ]));
}

// The HTTP boundary is synthetic; session guards, parsing and durable settings
// publication remain the production repository's responsibility.
class _HttpFixture extends ForumClient {
  _HttpFixture()
      : super(
            config: const ForumNetworkConfig(
                site: ForumNetworkConfig.defaultSite,
                mode: ForumNetworkMode.native));

  @override
  bool get isLoggedIn => true;

  @override
  Future<void> restoreCookies() async {}

  @override
  Future<String> get(String path) async => '''<html><body>
<div id="user-login"><a href="u.php">Synthetic A</a></div>
<div id="menu_profile"><div class="ul2"><a href="u.php?action-show-uid-901.html">个人资料</a></div></div>
</body></html>''';

  @override
  Future<String> getForm(String path,
      {void Function()? requireCurrentSession,
      bool followRedirects = true}) async {
    requireCurrentSession?.call();
    const html =
        '''<html><body><img src="images/colorImagination/shortmail.gif">
<form method="post" action="message.php">
<input type="hidden" name="verify" value="fixture-token">
<input type="hidden" name="towhere" value="receivebox">
<table><tr><td>ID</td><td>发件人</td><td>标题</td><td>时间</td><td>选择</td></tr>
<tr><td>1</td><td><a href="u.php?action-show-uid-901.html">Synthetic peer</a></td>
<td><a class="b" href="message.php?action-read-mid-701.html">Synthetic A private inbox title</a></td>
<td>2020-01-01 10:00</td><td><input type="checkbox" name="delid[]" value="701"></td></tr></table>
</form></body></html>''';
    requireCurrentSession?.call();
    return html;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    SharedPreferences.resetStatic();
    messenger.setMockMethodCallHandler(channel,
        (call) async => call.method == 'getAll' ? <String, Object>{} : true);
  });
  tearDown(() {
    SharedPreferences.resetStatic();
    messenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('personal and broadcast messages with equal IDs both survive',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: PmBoxScreen(repository: _BoxRepository(collidingIds: true))));
    await tester.pumpAndSettle();
    expect(find.text('personal identity 701'), findsOneWidget);
    expect(find.text('broadcast identity 701'), findsOneWidget);
  });

  testWidgets('an embedded mailbox cannot pop another route on epoch change',
      (tester) async {
    final repository = await pumpRedesignShell(tester);
    await selectRedesignTab(tester, '消息');
    expect(find.text('fixture-owner-a inbox message 0'), findsOneWidget);
    final navigator =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Network settings route'))));
    await tester.pumpAndSettle();

    // Committing network settings changes the epoch while this route is open.
    repository.epoch.value++;
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Network settings route').hitTestable(), findsOneWidget);
    expect(navigator.canPop(), isTrue);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('fixture-owner-a inbox message 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final reverse in [false, true]) {
    testWidgets('desktop box transitions permit scrolling (reverse=$reverse)',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      try {
        await tester.pumpWidget(
            MaterialApp(home: PmBoxScreen(repository: _BoxRepository())));
        await tester.pumpAndSettle();
        expect(find.text('inbox message 0'), findsOneWidget);
        await tester.tap(find.text('发件箱'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        if (reverse) {
          await tester.tap(find.text('收件箱'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 80));
        }
        final entering = find
            .text('${reverse ? 'inbox' : 'sendbox'} message 0')
            .hitTestable();
        expect(entering, findsOneWidget);
        await tester.drag(entering, const Offset(0, -100));
        await tester.pump(const Duration(milliseconds: 40));
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('a pending site change revokes a subsequently linked mailbox',
      (tester) async {
    final persisted = <String, Object>{};
    final entered = Completer<void>();
    final acknowledge = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') return Map<String, Object>.of(persisted);
      final args = call.arguments as Map;
      final key = args['key'] as String;
      if (call.method == 'remove') {
        persisted.remove(key);
      } else {
        persisted[key] = args['value'] as Object;
      }
      if (key == 'flutter.forum_network_config_v2') {
        entered.complete();
        await acknowledge.future;
      }
      return true;
    });
    addTearDown(() {
      if (!acknowledge.isCompleted) acknowledge.complete();
      messenger.setMockMethodCallHandler(channel, null);
      SharedPreferences.resetStatic();
      ForumHttpRouting.updateConfig(const ForumNetworkConfig(
          site: ForumNetworkConfig.defaultSite, mode: ForumNetworkMode.native));
    });
    final repository = ForumRepository(client: _HttpFixture());
    expect(await repository.restoreSession(), isTrue);
    expect(repository.currentUsername, 'Synthetic A');
    Future<void>? save;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                    body: Column(children: [
                  TextButton(
                    onPressed: () {
                      save = repository.updateNetworkConfig(
                          const ForumNetworkConfig(
                              site: ForumSite('other.fixture.invalid'),
                              mode: ForumNetworkMode.native));
                    },
                    child: const Text('Save site change'),
                  ),
                  TextButton(
                    onPressed: () => openForumLink(
                        context,
                        repository,
                        repository.networkConfig.baseUri
                            .resolve('message.php?action-receivebox.html')
                            .toString()),
                    child: const Text('Incoming mailbox link'),
                  ),
                ])))));
    await tester.tap(find.text('Save site change'));
    await tester.pump();
    await entered.future;
    expect(repository.currentUsername, 'Synthetic A');
    await tester.tap(find.text('Incoming mailbox link'));
    await tester.pumpAndSettle();
    expect(find.byType(PmBoxScreen), findsOneWidget);
    expect(find.text('Synthetic A private inbox title'), findsOneWidget);
    final oldEpoch = repository.sessionEpoch.value;
    acknowledge.complete();
    await save;
    expect(repository.sessionEpoch.value, greaterThan(oldEpoch));
    expect(repository.networkConfig.site.host, 'other.fixture.invalid');
    expect(repository.isLoggedIn, isFalse);
    await tester.pump();
    expect(find.text('Synthetic A private inbox title', skipOffstage: false),
        findsNothing);
    expect(find.text('账号已切换'), findsOneWidget);
  });
}
