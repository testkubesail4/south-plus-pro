import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const shareChannel = MethodChannel('south_plus_rewrite/image_saver');
  final copied = <String>[];
  final shared = <Object?>[];

  setUp(() {
    copied.clear();
    shared.clear();
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      shared.add(call.arguments);
      return true;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(shareChannel, null);
  });

  Future<void> pumpProfile(WidgetTester tester, String uid) async {
    await tester.pumpWidget(MaterialApp(
      home: UserProfileScreen(userUrl: 'u.php', repository: _Repo(uid)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('分享 hands the canonical 用户中心 link to the share sheet',
      (tester) async {
    await pumpProfile(tester, '101');
    await tester.tap(find.byTooltip('分享'));
    await tester.pumpAndSettle();

    expect(shared, [
      {
        'text': 'peer-a 的用户中心\n'
            'https://south-plus.net/u.php?action-show-uid-101.html',
      },
    ]);
    expect(copied, isEmpty);
  });

  testWidgets('分享 without a share sheet copies the link and says so',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await pumpProfile(tester, '101');
    await tester.tap(find.byTooltip('分享'));
    await tester.pumpAndSettle();

    expect(copied, ['https://south-plus.net/u.php?action-show-uid-101.html']);
    expect(find.text('已复制链接'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('no UID, no 分享', (tester) async {
    await pumpProfile(tester, '');
    expect(find.byTooltip('分享'), findsNothing);
  });
}

class _Repo extends ForumRepository {
  _Repo(this.uid);

  final String uid;

  UserProfile get _profile => UserProfile(
        uid: uid,
        name: 'peer-a',
        url: 'u.php?action-show-uid-$uid.html',
      );

  @override
  Future<UserProfile?> cachedUserProfileOverview(String url) async => null;

  @override
  Future<UserProfile> fetchUserProfileOverview(String url) async => _profile;

  @override
  Future<UserProfile> fetchUserProfileDetails(UserProfile overview,
          {bool forceReload = false}) async =>
      overview;
}
