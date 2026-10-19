import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/user_display_name_store.dart';
import 'package:south_plus_rewrite/services/user_note_store.dart';
import 'package:south_plus_rewrite/services/user_tag_store.dart';
import 'package:south_plus_rewrite/features/common/user_tags_inline.dart';

// Synthetic fixtures only: fictional tid, uids and authors.
const _url = 'https://south-plus.net/read.php?tid-7.html';
const _longSignature = '这是一条非常非常长的个性签名，用来确认它不会挤掉发帖时间也不会撑破楼层的布局';
String _profile(int uid) =>
    'https://south-plus.net/u.php?action-show-uid-$uid.html';

class _Repo extends ForumRepository {
  _Repo({this.laterPage = false});

  /// A page 2+ shape: the opening post's metadata without its body.
  final bool laterPage;

  @override
  Future<ThreadReadPosition?> loadThreadReadPosition(ForumThread t) async =>
      null;

  @override
  Future<void> saveThreadReadPosition(
    ForumThread t,
    ThreadReadPosition p,
  ) async {}

  @override
  Future<ThreadDetail> fetchThreadDetail(
    ForumThread thread, {
    int page = 1,
  }) async =>
      ThreadDetail(
        thread: thread.copyWith(
          title: '合成主题',
          author: '楼主甲',
          authorUrl: _profile(3),
          // The list's last-reply time, which is not the opening post's.
          lastPost: '2099-01-01 00:00',
        ),
        body: laterPage ? '' : 'opening body',
        pagination: ThreadPagination(
            currentPage: laterPage ? 2 : 1, totalPages: laterPage ? 2 : 1),
        bodyPostedAt: '2026-10-01 08:00',
        personalSignature: '楼主签名',
        replies: [
          ThreadReply(
            author: '路人乙',
            authorUrl: _profile(4),
            content: 'reply',
            segments: [ThreadContentSegment.text('reply')],
            floor: 'B1F',
            postedAt: '2026-10-12 10:20',
            personalSignature: _longSignature,
            quoteUrl: 'post.php?action-quote-tid-7-pid-1.html',
          ),
        ],
      );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpThread(
    WidgetTester tester, {
    double scale = 1,
    bool laterPage = false,
  }) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: ThreadDetailScreen(
        repository: _Repo(laterPage: laterPage),
        thread:
            const ForumThread(title: '', url: _url, replies: 0, section: ''),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the opening post shows its own time, never the list time',
      (tester) async {
    await pumpThread(tester);

    expect(find.text('2026-10-01 08:00'), findsOneWidget);
    expect(find.text('2099-01-01 00:00'), findsNothing);
    expect(find.text('楼主签名'), findsOneWidget);
  });

  testWidgets(
      'page 2 keeps a compact opening header: time, signature, tags, note',
      (tester) async {
    await UserTagStore.save('3', ['资源佬']);
    await UserNoteStore.save('3', '老甲');
    await pumpThread(tester, laterPage: true, scale: 2);

    expect(find.text('opening body'), findsNothing);
    expect(find.text('2026-10-01 08:00'), findsOneWidget);
    expect(find.text('2099-01-01 00:00'), findsNothing);
    expect(find.text('楼主签名'), findsOneWidget);
    expect(find.textContaining('老甲'), findsOneWidget);
    expect(find.bySemanticsLabel('标签 资源佬'), findsOneWidget);
    expect(find.text('只看楼主'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 2.0x the time stays whole and the signature drops below it',
      (tester) async {
    await pumpThread(tester, scale: 2);

    final time = find.text('2026-10-12 10:20 · B1F');
    expect(time, findsOneWidget);
    final timeRect = tester.getRect(time);
    expect(timeRect.right, lessThanOrEqualTo(360));
    expect(
      tester.renderObject<RenderParagraph>(time).didExceedMaxLines,
      isFalse,
    );

    final signature = find.text(_longSignature);
    expect(signature, findsOneWidget);
    expect(
        tester.getRect(signature).top, greaterThanOrEqualTo(timeRect.bottom));
    expect(tester.getRect(signature).right, lessThanOrEqualTo(360));
  });

  testWidgets(
      'OP and replies show bounded tags live without crowding author or time at text2',
      (tester) async {
    await UserTagStore.save('3', ['资源佬', '熟人', '第三个']);
    await UserTagStore.save('4', [for (var i = 0; i < 8; i++) '标签$i']);
    final semantics = tester.ensureSemantics();
    await pumpThread(tester, scale: 2);
    expect(find.byType(UserTagsInline), findsNWidgets(2));
    expect(find.text('楼主甲'), findsOneWidget);
    expect(find.text('路人乙'), findsOneWidget);
    expect(find.text('2026-10-12 10:20 · B1F'), findsOneWidget);
    expect(find.bySemanticsLabel('标签 资源佬、熟人、第三个'), findsOneWidget);
    expect(
        find.bySemanticsLabel(
            '标签 ${[for (var i = 0; i < 8; i++) '标签$i'].join('、')}'),
        findsOneWidget);
    expect(find.byType(UserTagCapsule).evaluate().length, lessThanOrEqualTo(4));
    expect(tester.takeException(), isNull);
    await UserTagStore.save('3', ['新楼主标签']);
    await UserTagStore.clear('4');
    await tester.pumpAndSettle();
    expect(find.byType(UserTagsInline), findsOneWidget);
    expect(find.bySemanticsLabel('标签 新楼主标签'), findsOneWidget);
    expect(find.text('2026-10-12 10:20 · B1F'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('a local note shows beside the original name and updates live',
      (tester) async {
    await pumpThread(tester);
    expect(find.textContaining('老乙'), findsNothing);

    await UserNoteStore.save('4', '老乙');
    await tester.pumpAndSettle();

    final label = find.textContaining('老乙');
    expect(label, findsOneWidget);
    expect(
      tester.widget<Text>(label).textSpan!.toPlainText(),
      contains('路人乙'),
    );
  });

  testWidgets(
      'saving an annotation from a floor remembers that author\'s shown name for that UID only',
      (tester) async {
    await UserTagStore.save('4', ['熟人']);
    await pumpThread(tester);
    await tester.tap(find.byType(UserTagsInline));
    await tester.pumpAndSettle();
    expect(find.text('原名：路人乙　UID 4'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '老乙');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect((await UserNoteStore.load())['4'], '老乙');
    final names = await UserDisplayNameStore.load();
    expect(names['4']?.nickname, '路人乙');
    expect(names.containsKey('3'), isFalse,
        reason: 'unannotated authors are not recorded');
  });

  testWidgets('an unchanged Save records no name', (tester) async {
    await UserTagStore.save('4', ['熟人']);
    await pumpThread(tester);
    await tester.tap(find.byType(UserTagsInline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(await UserDisplayNameStore.load(), isEmpty);
  });
}
