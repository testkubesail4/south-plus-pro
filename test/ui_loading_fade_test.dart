import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/common/async_state_view.dart';
import 'package:south_plus_rewrite/features/common/native_form_fields.dart';
import 'package:south_plus_rewrite/models/forum_account_models.dart';

// One shared native form page stands for every settings form read from
// the forum (资料, 论坛偏好): it fades in over its skeleton, and a form read
// for another account drops the shown one at once.
ForumAccountForm _form(String nick) =>
    ForumAccountForm(kind: ForumAccountFormKind.preferences, fields: [
      ForumAccountField(
          name: 'field_1', label: '昵称', type: 'text', values: [nick]),
    ]);

void main() {
  late List<Completer<ForumAccountForm>> loads;
  late ValueNotifier<int> epoch;

  Future<void> pump(WidgetTester tester, {bool reduce = false}) async {
    loads = [];
    epoch = ValueNotifier(0);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: NativeFormPage(
          title: '测试',
          sessionEpoch: epoch,
          load: () {
            final load = Completer<ForumAccountForm>();
            loads.add(load);
            return load.future;
          },
          save: (form, changes, _) async {},
          builder: (context, c) =>
              [NativeFieldRow(controller: c, name: 'field_1')],
        ),
      ),
    ));
  }

  double opacityOf(WidgetTester tester, Finder finder) => tester
      .widget<FadeTransition>(find
          .ancestor(of: finder, matching: find.byType(FadeTransition))
          .first)
      .opacity
      .value;

  testWidgets('the form fades in over its skeleton', (tester) async {
    await pump(tester);
    expect(find.byType(ThreadListSkeleton), findsOneWidget);
    loads.single.complete(_form('old'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Mid-fade: the skeleton leaves as the form comes in.
    expect(find.byType(ThreadListSkeleton), findsOneWidget);
    expect(opacityOf(tester, find.text('昵称')), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(find.byType(ThreadListSkeleton), findsNothing);
    expect(opacityOf(tester, find.text('昵称')), 1);
  });

  testWidgets('another account\'s form never fades out', (tester) async {
    await pump(tester);
    loads.single.complete(_form('old'));
    await tester.pumpAndSettle();
    expect(find.text('old'), findsOneWidget);

    epoch.value++;
    await tester.pump();
    expect(find.text('old'), findsNothing);
    expect(find.text('昵称'), findsNothing);
    expect(find.byType(ThreadListSkeleton), findsOneWidget);
  });

  testWidgets('reduced motion shows the form at once', (tester) async {
    await pump(tester, reduce: true);
    loads.single.complete(_form('old'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(ThreadListSkeleton), findsNothing);
    expect(find.text('old'), findsOneWidget);
  });
}
