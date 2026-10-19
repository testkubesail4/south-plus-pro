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

  setUp(() {
    SharedPreferences.resetStatic();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') return <String, Object>{};
      throw PlatformException(code: 'fixture-write-failure');
    });
  });

  tearDown(() {
    SharedPreferences.resetStatic();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<_Repo> post(WidgetTester tester, ReplyResult result) async {
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
    await tester.tap(find.byKey(const ValueKey('compose-submit')));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('an unconfirmed post stays locked when its draft cannot be kept',
      (tester) async {
    final repo = await post(
      tester,
      const ReplyResult(success: false, unconfirmed: true, message: ''),
    );
    expect(find.textContaining('不要重复发布'), findsOneWidget);
    expect(find.textContaining('草稿未能保存到本机'), findsOneWidget);
    final submit = find.byKey(const ValueKey('compose-submit'));
    expect(tester.widget<ButtonStyleButton>(submit).enabled, isFalse);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(repo.posts, 1);
  });

  testWidgets('a confirmed post leaves even when its draft cannot be cleared',
      (tester) async {
    final repo = await post(
      tester,
      const ReplyResult(success: true, message: 'ok'),
    );
    expect(find.byType(ThreadComposeScreen), findsNothing);
    expect(find.text('主题已发布'), findsOneWidget);
    expect(repo.posts, 1);
  });
}
