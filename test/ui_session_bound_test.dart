import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/common/session_bound.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

class _Repo extends ForumRepository {
  final epoch = ValueNotifier<int>(0);

  @override
  ValueListenable<int> get sessionEpoch => epoch;
}

void main() {
  testWidgets('nested private pages close down to the outer one, not past it',
      (tester) async {
    final repository = _Repo();
    Widget private(String text, {Widget? next}) => SessionBound(
          repository: repository,
          title: '短消息',
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: next == null
                    ? null
                    : () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => next)),
                child: Text(text),
              ),
            ),
          ),
        );
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) =>
                  private('outer secret', next: private('inner secret')))),
          child: const Text('root'),
        ),
      ),
    ));
    await tester.tap(find.text('root'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('outer secret'));
    await tester.pumpAndSettle();

    repository.epoch.value++;
    await tester.pump();
    expect(find.textContaining('secret', skipOffstage: false), findsNothing);

    await tester.pumpAndSettle();
    // The outer page stays, emptied; its 返回 leads to the root.
    expect(find.text('账号已切换'), findsOneWidget);
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(find.text('root'), findsOneWidget);
  });
}
