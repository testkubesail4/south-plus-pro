import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/more_pages.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';

typedef _Page = ({List<String?> ids, String? next});

const _Page _first = (ids: ['1'], next: 'native-next-2');
const _Page _second = (ids: ['2'], next: 'native-next-3');
const _Page _late = (ids: ['3'], next: null);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final reset in [false, true]) {
    test('${reset ? 'reset' : 'cancelPending'} retires a pending append',
        () async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final third = Completer<_Page>();
      final requests = <String>[];
      var changes = 0;
      final more = MorePages<_Page>(
        domain: LoadingDomain.pm,
        fetch: (path) {
          requests.add(path);
          return path == 'native-next-2' ? Future.value(_second) : third.future;
        },
        nextOf: (page) => page.next,
        idsOf: (page) => page.ids,
        changed: () => changes++,
      );
      await more.load(_first, scroll);
      expect(more.pages.map((page) => page.ids), [
        ['2']
      ]);
      final pending = more.load(_first, scroll);
      expect(more.loading, isTrue);
      expect(requests, ['native-next-2', 'native-next-3']);
      if (reset) {
        more.reset();
      } else {
        more.cancelPending();
      }
      final changesAfterRetirement = changes;
      third.complete(_late);
      await pending;
      expect(
          more.pages.map((page) => page.ids),
          reset
              ? isEmpty
              : [
                  ['2']
                ]);
      expect(more.loading, isFalse);
      expect(more.error, isNull);
      expect(changes, changesAfterRetirement,
          reason: 'A retired completion cannot publish into the current view');
    });
  }

  testWidgets('a failed next read waits for explicit retry of the same target',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await LoadingPreferences.load();
    await LoadingPreferences.save(LoadingDomain.pm, LoadingMode.continuous);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: SingleChildScrollView(
        controller: scroll,
        child: const SizedBox(height: 20),
      ),
    ));
    expect(scroll.hasClients, isTrue);
    expect(scroll.position.extentAfter, 0);
    final requests = <String>[];
    final more = MorePages<_Page>(
      domain: LoadingDomain.pm,
      fetch: (path) async {
        requests.add(path);
        if (requests.length == 1) throw StateError('Synthetic page failure');
        return (ids: ['2'], next: null);
      },
      nextOf: (page) => page.next,
      idsOf: (page) => page.ids,
      changed: () {},
    );
    more.maybeLoad(_first, scroll);
    await tester.pump();
    expect(requests, ['native-next-2']);
    expect(more.error, isA<StateError>());
    expect(more.loading, isFalse);
    more.maybeLoad(_first, scroll);
    await tester.pump();
    expect(requests, ['native-next-2'],
        reason: 'Scrolling cannot retry errors');
    more.retry(_first, scroll);
    await tester.pump();
    expect(requests, ['native-next-2', 'native-next-2']);
    expect(more.pages.map((page) => page.ids), [
      ['2']
    ]);
    expect(more.error, isNull);
    expect(more.loading, isFalse);
  });
}
