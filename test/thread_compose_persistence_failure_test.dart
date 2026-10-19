import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/thread/thread_compose_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// Synthetic board only. A post's outcome must survive a local storage failure.
const _board = ForumCategory(
  name: '茶馆',
  slug: 'f9',
  url: 'https://south-plus.net/thread.php?fid-9.html',
);

class _Repo extends ForumRepository {
  _Repo(this.result);

  final ReplyResult result;
  int posts = 0;

  @override
  Future<ThreadComposeDraft> fetchThreadComposeDraft(
    ForumCategory category,
  ) async =>
      const ThreadComposeDraft(
        categories: [],
        selectedCategory: '',
        bountySupported: false,
        controls: [],
        actionPath: 'post.php?',
        fid: '9',
      );

  @override
  Future<ReplyResult> submitThread({
    required ForumCategory category,
    required String title,
    required String content,
    bool enableReplyNotice = false,
    ThreadComposeDraft? draft,
    String? categoryValue,
    int? bestAnswerAmount,
    int? helpfulAmount,
    bool confirmBounty = false,
  }) async {
    posts++;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var writesFail = true;

  tearDown(() {
    SharedPreferences.resetStatic();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<_Repo> open(WidgetTester tester, ReplyResult result) async {
    final repo = _Repo(result);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<bool>(
              builder: (_) => ThreadComposeScreen(
                category: _board,
                repository: repo,
              ),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '标题');
    await tester.enterText(find.widgetWithText(TextField, '正文'), '正文内容');
    return repo;
  }

  for (final failure in ['exception', 'title', 'content']) {
    group(failure, () {
      setUp(() {
        writesFail = true;
        SharedPreferences.resetStatic();
        final stored = <String, Object>{};
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getAll') return Map<String, Object>.of(stored);
          final arguments = Map<String, dynamic>.from(call.arguments as Map);
          final key = arguments['key'] as String;
          if (writesFail) {
            if (failure == 'exception') {
              throw PlatformException(code: 'fixture-write-failure');
            }
            if (key.endsWith('.$failure')) return false;
          }
          if (call.method == 'remove') {
            stored.remove(key);
          } else {
            stored[key] = arguments['value'] as Object;
          }
          return true;
        });
      });

      testWidgets(
          'an unconfirmed post stays locked when its draft cannot be kept',
          (tester) async {
        final repo = await open(
          tester,
          const ReplyResult(success: false, unconfirmed: true, message: ''),
        );
        await tester.tap(find.byKey(const ValueKey('compose-submit')));
        await tester.pumpAndSettle();
        expect(find.textContaining('不要重复发布'), findsOneWidget);
        expect(find.textContaining('草稿未能保存到本机'), findsOneWidget);
        final submit = find.byKey(const ValueKey('compose-submit'));
        expect(tester.widget<ButtonStyleButton>(submit).enabled, isFalse);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(repo.posts, 1);
        writesFail = false;
        await tester.tap(find.byTooltip('存草稿'));
        await tester.pumpAndSettle();
        expect(find.text('草稿已保存'), findsOneWidget);
        expect(find.textContaining('草稿已保留'), findsOneWidget);
        expect(tester.widget<ButtonStyleButton>(submit).enabled, isFalse);
        expect(repo.posts, 1);
      });

      testWidgets(
          'a confirmed post leaves even when its draft cannot be cleared',
          (tester) async {
        final repo = await open(
          tester,
          const ReplyResult(success: true, message: 'ok'),
        );
        await tester.tap(find.byKey(const ValueKey('compose-submit')));
        await tester.pumpAndSettle();
        expect(find.byType(ThreadComposeScreen), findsNothing);
        expect(find.text('主题已发布'), findsOneWidget);
        expect(repo.posts, 1);
      });

      testWidgets('manual draft saving reports failure and allows retry',
          (tester) async {
        final repo = await open(
          tester,
          const ReplyResult(success: true, message: 'ok'),
        );
        await tester.tap(find.byTooltip('存草稿'));
        await tester.pumpAndSettle();
        expect(find.textContaining('草稿未能保存到本机'), findsOneWidget);
        expect(find.text('草稿已保存'), findsNothing);
        expect(find.widgetWithText(TextField, '正文内容'), findsOneWidget);
        expect(repo.posts, 0);
        await tester.pumpAndSettle(const Duration(seconds: 5));
        writesFail = false;
        await tester.tap(find.byTooltip('存草稿'));
        await tester.pumpAndSettle();
        expect(find.text('草稿已保存'), findsOneWidget);
        expect(repo.posts, 0);
      });
    });
  }
}
