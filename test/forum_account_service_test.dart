import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_account_models.dart';
import 'package:south_plus_rewrite/services/forum_account_service.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'preferences preserve successful controls and repeated blocked groups, not disabled or password controls',
      () async {
    final client = _Client()
      ..responses.addAll([preferences(), preferences(), success]);
    final service = accountService(client);
    final form = await service.fetchForumPreferences();
    expect(form.field('editor')!.options.map((o) => o.label), ['可视化', '代码']);
    expect(form.field('banidinfo')!.group, 'pm');
    expect(form.field('friendcheck')!.group, 'friend');
    expect(form.field('disabled'), isNull);
    await service.saveForumPreferences(form, {
      'banidinfo': ['123, 456']
    });
    final post = client.posts.single;
    expect(post.path, 'profile.php?action=bbsset');
    expect(post.multipart, false);
    expect(values(post, 'msggroups[]'), ['3', '7']);
    expect(values(post, 'banidinfo'), ['123, 456']);
    expect(values(post, 'unchecked'), isEmpty);
    expect(values(post, 'defaultCheck'), ['on']);
    expect(values(post, 'disabled'), isEmpty);
    expect(values(post, 'disabledFieldset'), isEmpty);
    expect(values(post, 'legendPreserved'), ['yes']);
    expect(values(post, 'multiple[]'), ['b', 'c']);
    expect(values(post, 'disabledSelected'), isEmpty);
    expect(values(post, 'fallbackSelect'), ['enabled']);
    expect(values(post, 'readonly'), ['preserve']);
    expect(values(post, 'oldpwd'), isEmpty);
    expect(values(post, 'unusualPassword'), isEmpty);
    expect(values(post, 'step'), ['2']);
    expect(client.getPaths,
        List.filled(2, 'profile.php?action-bbsset-info_type-msg.html'));
  });

  test(
      'disabled last-checked radio wins native state without submitting an earlier checked value',
      () async {
    final html = preferences()
        .replaceAll('value="2">拒绝', 'value="2" checked disabled>拒绝');
    final client = _Client()..responses.addAll([html, html, success]);
    final service = accountService(client);
    final form = await service.fetchForumPreferences();
    expect(form.field('friendcheck')!.values, isEmpty);
    await service.saveForumPreferences(form, {
      'banidinfo': ['123']
    });
    expect(values(client.posts.single, 'friendcheck'), isEmpty);
  });

  test(
      'checkbox edits preserve same-name hidden defaults in browser submission order',
      () async {
    final html = preferences().replaceAll('<tr><td>屏蔽用户组',
        '<input type="hidden" name="msggroups[]" value="fallback"><tr><td>屏蔽用户组');
    final client = _Client()..responses.addAll([html, html, success]);
    final service = accountService(client);
    final form = await service.fetchForumPreferences();
    expect(form.field('msggroups[]')!.values, ['3', '7']);
    await service.saveForumPreferences(form, {'msggroups[]': []});
    expect(values(client.posts.single, 'msggroups[]'), ['fallback']);
  });

  test(
      'fresh read keeps latest sensitive profile fields and footer without exposing or editing them',
      () async {
    final client = _Client()
      ..responses.addAll([
        profile(token: 'old', sensitive: 'old'),
        profile(token: 'fresh', sensitive: 'fresh'),
        success,
      ]);
    final service = accountService(client);
    final form = await service.fetchAccountProfileForm();
    expect(form.fields.map((f) => f.name), isNot(contains('proemail')));
    expect(form.fields.map((f) => f.name), isNot(contains('alipay')));
    expect(form.fields.map((f) => f.name), isNot(contains('prosign')));
    await service.saveAccountProfileForm(form, {
      'field_1': ['New nickname'],
      'prohonor': ['Short signature']
    });
    final post = client.posts.single;
    expect(post.path, 'profile.php?action=modify&');
    expect(post.multipart, true);
    expect(values(post, 'verify'), ['fresh']);
    expect(values(post, 'proemail'), ['fresh@example.invalid']);
    expect(values(post, 'propublicemail'), ['1']);
    expect(values(post, 'alipay'), ['fresh-payment']);
    expect(values(post, 'contact[]'), ['fresh-contact']);
    expect(values(post, 'tradetype[]'), ['2', '4']);
    expect(values(post, 'prosign'), ['fresh footer']);
    expect(values(post, 'field_1'), ['New nickname']);
    expect(values(post, 'prohonor'), ['Short signature']);
    expect(values(post, 'oldpwd'), isEmpty);
    expect(values(post, 'propwd'), isEmpty);
    expect(values(post, 'check_pwd'), isEmpty);
    expect(post.files.single.name, 'upload');
    expect(post.files.single.bytes, isEmpty);
    await expectLater(
        service.saveAccountProfileForm(form, {
          'field_1': ['Again']
        }),
        invalidInput);
    expect(client.posts, hasLength(1),
        reason: 'successful form cannot be replayed');
  });

  test(
      'sensitive edits, forged forms, nickname blacklist and invalid native options never reach POST',
      () async {
    final client = _Client()..responses.addAll([preferences(), profile()]);
    final service = accountService(client);
    final preferencesForm = await service.fetchForumPreferences();
    final profileForm = await service.fetchAccountProfileForm();
    for (final patch in <Map<String, List<String>>>[
      {
        'banidinfo': ['nickname']
      },
      {
        'banidinfo': ['0']
      },
      {
        'banidinfo': ['1,,2']
      },
      {
        'banidinfo': ['1;2']
      },
      {
        'banidinfo': ['-1']
      },
      {
        'friendcheck': ['9']
      },
      {
        'msggroups[]': ['disabled-group']
      },
      {
        'msggroups[]': ['3', '3']
      },
      {
        'verify': ['attacker']
      },
    ]) {
      await expectLater(
          service.saveForumPreferences(preferencesForm, patch), invalidInput);
    }
    for (final name in [
      'proemail',
      'propublicemail',
      'alipay',
      'contact[]',
      'prosign',
      'oldpwd',
      'propwd',
      'check_pwd'
    ]) {
      await expectLater(
          service.saveAccountProfileForm(profileForm, {
            name: ['unsafe']
          }),
          invalidInput);
    }
    await expectLater(
        service.saveAccountProfileForm(profileForm, {
          'profrom': ['x' * 15]
        }),
        throwsA(isA<ForumAccountValidationException>()
            .having((e) => e.fieldErrors.keys, 'field', ['profrom'])));
    await expectLater(
        service.saveAccountProfileForm(profileForm, {
          'prohomepage': ['javascript:alert(1)']
        }),
        invalidInput);
    await expectLater(
        service.saveForumPreferences(
            ForumAccountForm(
                kind: preferencesForm.kind, fields: preferencesForm.fields),
            {
              'banidinfo': ['1']
            }),
        invalidInput);
    expect(client.posts, isEmpty);
    expect(client.getPaths, hasLength(2),
        reason: 'validation happens before refresh or mutation');
  });

  test(
      'empty blocked groups and blacklist intentionally clear only those controls',
      () async {
    final client = _Client()
      ..responses.addAll([preferences(), preferences(), success]);
    final service = accountService(client);
    final form = await service.fetchForumPreferences();
    await service.saveForumPreferences(form, {
      'msggroups[]': [],
      'banidinfo': ['']
    });
    expect(values(client.posts.single, 'msggroups[]'), isEmpty);
    expect(values(client.posts.single, 'banidinfo'), ['']);
    expect(values(client.posts.single, 'friendcheck'), ['0']);
  });

  test(
      'conflicting edits and changed server permissions do not overwrite current values',
      () async {
    for (final refreshed in [
      preferences(blacklist: '999'),
      preferences().replaceAll('name="banidinfo"', 'disabled name="banidinfo"')
    ]) {
      final client = _Client()..responses.addAll([preferences(), refreshed]);
      final service = accountService(client);
      final form = await service.fetchForumPreferences();
      await expectLater(
          service.saveForumPreferences(form, {
            'banidinfo': ['123']
          }),
          invalidInput);
      expect(client.posts, isEmpty);
    }
  });

  test(
      'form capabilities cannot cross sessions, origins, or clients even with same username',
      () async {
    var epoch = 1;
    var client = _Client()..responses.add(preferences());
    final service = ForumAccountService(
        client: () => client,
        sessionEpoch: () => epoch,
        isLoggedIn: () => true);
    final form = await service.fetchForumPreferences();
    epoch++;
    await expectLater(
        service.saveForumPreferences(form, {
          'banidinfo': ['123']
        }),
        loginRequired);
    epoch--;
    client = _Client();
    await expectLater(
        service.saveForumPreferences(form, {
          'banidinfo': ['123']
        }),
        loginRequired);
    expect(client.getPaths, isEmpty);
    expect(client.posts, isEmpty);
  });

  test(
      'session change while refresh is in flight cannot submit old account fields',
      () async {
    var epoch = 1;
    final client = _Client()..responses.add(preferences());
    final service = ForumAccountService(
        client: () => client,
        sessionEpoch: () => epoch,
        isLoggedIn: () => true);
    final form = await service.fetchForumPreferences();
    final pending = Completer<String>();
    client.getNext = () => pending.future;
    final saving = service.saveForumPreferences(form, {
      'banidinfo': ['123']
    });
    epoch++;
    pending.complete(preferences());
    await expectLater(saving, loginRequired);
    expect(client.posts, isEmpty);
  });

  test(
      'session change during POST never reports success or consumes next account state',
      () async {
    var epoch = 1;
    final client = _Client()..responses.addAll([preferences(), preferences()]);
    final service = ForumAccountService(
        client: () => client,
        sessionEpoch: () => epoch,
        isLoggedIn: () => true);
    final form = await service.fetchForumPreferences();
    client.postNext = () async {
      epoch++;
      return success;
    };
    await expectLater(
        service.saveForumPreferences(form, {
          'banidinfo': ['123']
        }),
        loginRequired);
    expect(client.posts, hasLength(1));
  });

  test(
      'native avatar constraints and script-initialized mode are derived without changing untouched avatar',
      () async {
    final client = _Client()..responses.add(profile());
    final form = await accountService(client).fetchAccountProfileForm();
    expect(form.field('facetype')!.value, '1');
    expect(form.field('proicon')!.type, 'system-avatar');
    expect(form.field('proicon')!.value, 'old.gif');
    expect(form.field('httpurl[1]')!.min, 1);
    expect(form.field('httpurl[1]')!.max, 150);
    expect(form.field('httpurl[2]')!.max, 270);
    expect(form.field('prointroduce')!.maxLength, 500);
  });

  test(
      'system avatar pages are observed capabilities, refreshed before use, not guessed filenames',
      () async {
    final client = _Client()
      ..responses.addAll([
        profile(),
        avatarPage(1),
        avatarPage(2),
        profile(),
        avatarPage(2),
        success
      ]);
    final service = accountService(client);
    final form = await service.fetchAccountProfileForm();
    await expectLater(service.fetchAccountSystemAvatars(page: 2), invalidInput);
    await expectLater(
        service.saveAccountProfileForm(form, {
          'proicon': ['guessed.gif']
        }),
        invalidInput);
    final first = await service.fetchAccountSystemAvatars();
    expect(first.options.single.imageUrl,
        client.baseUri.resolve('images/face/page1.gif').toString());
    expect(first.nextPage, 2);
    expect(first.previousPage, isNull);
    final second =
        await service.fetchAccountSystemAvatars(page: first.nextPage!);
    expect(second.previousPage, 1);
    await service.saveAccountProfileForm(form, {
      'proicon': [second.options.single.value]
    });
    expect(values(client.posts.single, 'proicon'), ['page2.gif']);
    expect(client.getPaths.last, 'pw_ajax.php?action=showface&page=2');
  });

  test(
      'unavailable system choices and expired avatar capabilities cannot be submitted',
      () async {
    var epoch = 1;
    final client = _Client()
      ..responses.addAll([
        profile(),
        avatarPage(1),
        profile(),
        avatarPage(1, icon: 'changed.gif')
      ]);
    final service = ForumAccountService(
        client: () => client,
        sessionEpoch: () => epoch,
        isLoggedIn: () => true);
    final form = await service.fetchAccountProfileForm();
    await service.fetchAccountSystemAvatars();
    await expectLater(
        service.saveAccountProfileForm(form, {
          'proicon': ['page1.gif']
        }),
        invalidInput);
    expect(client.posts, isEmpty);
    epoch++;
    client.responses.add(profile());
    final newForm = await service.fetchAccountProfileForm();
    await expectLater(
        service.saveAccountProfileForm(newForm, {
          'proicon': ['page1.gif']
        }),
        invalidInput);
  });

  test(
      'link avatar width is mandatory integer in native range; blank height stays automatic',
      () async {
    for (final (width, height) in [
      ('0', ''),
      ('151', ''),
      ('1.5', ''),
      ('', ''),
      ('150', '271')
    ]) {
      final client = _Client()..responses.add(profile());
      final service = accountService(client);
      final form = await service.fetchAccountProfileForm();
      await expectLater(
          service.saveAccountProfileForm(form, {
            'facetype': ['2'],
            'httpurl[0]': ['https://example.invalid/avatar.png'],
            'httpurl[1]': [width],
            'httpurl[2]': [height]
          }),
          invalidInput);
      expect(client.posts, isEmpty);
      expect(client.getPaths, hasLength(1));
    }
    final client = _Client()..responses.addAll([profile(), profile(), success]);
    final service = accountService(client);
    final form = await service.fetchAccountProfileForm();
    await service.saveAccountProfileForm(form, {
      'facetype': ['2'],
      'httpurl[0]': ['https://example.invalid/avatar.png'],
      'httpurl[1]': ['150'],
      'httpurl[2]': ['']
    });
    expect(values(client.posts.single, 'httpurl[2]'), ['']);
  });

  test(
      'synthetic accepted upload callback permits fresh snapshot modify without resending file',
      () async {
    final client = _Client()
      ..responses.addAll([
        profile(),
        profile(),
        '<script>parent.facepath("attachment/face/", "uploaded.png", "success", 150, 100);</script>',
        profile(token: 'after-upload', sensitive: 'after-upload'),
        success
      ]);
    final service = accountService(client);
    final form = await service.fetchAccountProfileForm();
    final avatar = ForumAccountUpload(
        bytes: pngBytes, fileName: 'chosen.png', mimeType: 'image/png');
    await service.saveAccountProfileForm(
        form,
        {
          'facetype': ['3'],
          'uploadurl[1]': ['150'],
          'uploadurl[2]': ['']
        },
        avatar: avatar);
    expect(client.posts.map((p) => p.path),
        ['profile.php?action=ajaxface', 'profile.php?action=modify&']);
    expect(client.posts.first.files.single.bytes, pngBytes);
    expect(client.posts.last.files.single.bytes, isEmpty);
    expect(values(client.posts.last, 'proicon'), ['uploaded.png']);
    expect(values(client.posts.last, 'verify'), ['after-upload']);
    expect(values(client.posts.last, 'proemail'),
        ['after-upload@example.invalid']);
    expect(values(client.posts.first, 'oldpwd'), isEmpty);
    expect(client.getPaths, hasLength(3));
  });

  test(
      'avatar callback rejection never proceeds to final save or evaluates JavaScript',
      () async {
    for (final response in [
      '<body>操作完成</body>',
      '<script>parent.facepath("attachment/face/","a.png","undefined_action",1,1);</script>',
      '<script>parent.facepath("attachment/face/","a.png","success",1,1);alert(1);</script>',
      '<script>parent.facepath("https://evil.invalid/","a.png","success",1,1);</script>',
      '<script>parent.facepath("//evil.invalid/","a.png","success",1,1);</script>',
      '<script>parent.facepath("attachment/face/","../a.png","success",1,1);</script>',
      '<script>parent.facepath("attachment/face/","%2e%2e/a.png","success",1,1);</script>',
      '<script>parent.facepath("attachment/face/","a.png",false,1,1);</script>',
    ]) {
      final client = _Client()
        ..responses.addAll([profile(), profile(), response]);
      final service = accountService(client);
      final form = await service.fetchAccountProfileForm();
      await expectLater(
          service.saveAccountProfileForm(
              form,
              {
                'facetype': ['3'],
                'uploadurl[1]': ['150']
              },
              avatar: ForumAccountUpload(
                  bytes: pngBytes, fileName: 'a.png', mimeType: 'image/png')),
          throwsA(isA<ForumRequestException>()));
      expect(client.posts, hasLength(1));
      expect(client.posts.single.path, 'profile.php?action=ajaxface');
    }
  });

  test('SVG, mismatched MIME and native size cap reject before any upload',
      () async {
    for (final upload in [
      ForumAccountUpload(
          bytes: Uint8List.fromList('<svg/>'.codeUnits),
          fileName: 'x.svg',
          mimeType: 'image/svg+xml'),
      ForumAccountUpload(
          bytes: pngBytes, fileName: 'x.jpg', mimeType: 'image/jpeg'),
    ]) {
      final client = _Client()..responses.add(profile());
      final service = accountService(client);
      final form = await service.fetchAccountProfileForm();
      await expectLater(
          service.saveAccountProfileForm(
              form,
              {
                'facetype': ['3'],
                'uploadurl[1]': ['150']
              },
              avatar: upload),
          invalidInput);
      expect(client.posts, isEmpty);
    }
    final limited = profile().replaceAll('</form>',
        '<input type="hidden" name="MAX_FILE_SIZE" value="2"></form>');
    final client = _Client()..responses.addAll([limited, limited]);
    final service = accountService(client);
    final form = await service.fetchAccountProfileForm();
    await expectLater(
        service.saveAccountProfileForm(
            form,
            {
              'facetype': ['3'],
              'uploadurl[1]': ['150']
            },
            avatar: ForumAccountUpload(
                bytes: pngBytes, fileName: 'x.png', mimeType: 'image/png')),
        invalidInput);
    expect(client.posts, isEmpty);
  });

  test(
      'valid forms can contain error phrases in user values without being treated as error pages',
      () async {
    final client = _Client()
      ..responses.add(profile().replaceAll('Old nickname', '请先登录'));
    final form = await accountService(client).fetchAccountProfileForm();
    expect(form.field('field_1')!.value, '请先登录');
  });

  test(
      'unsafe form actions, incomplete forms and login pages are never writable snapshots',
      () async {
    for (final html in [
      preferences().replaceAll('profile.php?action=bbsset',
          'https://evil.invalid/profile.php?action=bbsset'),
      preferences().replaceAll('profile.php?action=bbsset',
          'profile.php?action=bbsset&amp;action=modify'),
      preferences().replaceAll(
          'profile.php?action=bbsset', 'profile.php?action=bbsset#fragment'),
      preferences().replaceAll('name="verify"', 'name="unknown"'),
      preferences().replaceAll('name="step"', 'name="unknown"'),
      '<body>请先登录</body>',
      '<body>没有权限</body>',
      '<body>请求过于频繁</body>',
    ]) {
      final client = _Client()..responses.add(html);
      await expectLater(accountService(client).fetchForumPreferences(),
          throwsA(isA<ForumRequestException>()));
      expect(client.posts, isEmpty);
    }
  });

  test(
      'unknown 200 acknowledges only a fresh readback matching every changed field',
      () async {
    for (final allFieldsMatch in [true, false]) {
      final readback = allFieldsMatch
          ? preferences(blacklist: '123')
              .replaceAll('value="7" checked', 'value="7"')
          : preferences(blacklist: '123');
      final client = _Client()
        ..responses.addAll([
          preferences(),
          preferences(),
          '<body>Unrecognized acknowledgement</body>',
          readback
        ]);
      final service = accountService(client);
      final form = await service.fetchForumPreferences();
      final saving = service.saveForumPreferences(form, {
        'banidinfo': ['123'],
        'msggroups[]': ['3']
      });
      if (allFieldsMatch) {
        await saving;
      } else {
        await expectLater(
            saving,
            throwsA(isA<ForumRequestException>()
                .having((e) => e.kind, 'kind', ForumRequestKind.server)));
      }
      expect(client.posts, hasLength(1));
      expect(client.getPaths, hasLength(3));
    }
  });

  test(
      'unknown 200 readback compares checkbox values without order sensitivity',
      () async {
    final client = _Client()
      ..responses.addAll([
        preferences(),
        preferences(),
        '<body>Unrecognized acknowledgement</body>',
        preferences(blacklist: '123')
      ]);
    final service = accountService(client);
    final form = await service.fetchForumPreferences();
    await service.saveForumPreferences(form, {
      'banidinfo': ['123'],
      'msggroups[]': ['7', '3']
    });
    expect(client.posts, hasLength(1));
  });

  test(
      'unknown ACK readback must confirm uploaded icon as well as native avatar mode and dimensions',
      () async {
    final uploaded = profile()
        .replaceAll("CkFaceType('1')", "CkFaceType('3')")
        .replaceAll('name="proicon" value="old.gif"',
            'name="proicon" value="uploaded.png"')
        .replaceAll('name="uploadurl[1]" maxlength="3" value=""',
            'name="uploadurl[1]" maxlength="3" value="150"');
    for (final iconMatches in [true, false]) {
      final readback = iconMatches
          ? uploaded
          : uploaded.replaceAll('value="uploaded.png"', 'value="other.png"');
      final client = _Client()
        ..responses.addAll([
          profile(),
          profile(),
          '<script>parent.facepath("attachment/face/", "uploaded.png", "success", 150, 100);</script>',
          profile(),
          '<body>Unrecognized acknowledgement</body>',
          readback
        ]);
      final service = accountService(client);
      final form = await service.fetchAccountProfileForm();
      final saving = service.saveAccountProfileForm(
          form,
          {
            'facetype': ['3'],
            'uploadurl[1]': ['150']
          },
          avatar: ForumAccountUpload(
              bytes: pngBytes, fileName: 'a.png', mimeType: 'image/png'));
      if (iconMatches) {
        await saving;
      } else {
        await expectLater(
            saving,
            throwsA(isA<ForumRequestException>()
                .having((e) => e.kind, 'kind', ForumRequestKind.server)));
      }
      expect(client.posts, hasLength(2));
      expect(client.getPaths, hasLength(4));
    }
  });

  test(
      'unknown 200 and echoed forms need matching readback; explicit errors never retry or read back',
      () async {
    for (final (html, kind) in [
      ('<body>Unknown response</body>', ForumRequestKind.server),
      ('<body>认证码错误 操作完成</body>', ForumRequestKind.server),
      ('<body>请先登录 操作完成</body>', ForumRequestKind.loginRequired),
      ('<body>没有权限 操作完成</body>', ForumRequestKind.forbidden),
      ('<body>请求过于频繁 操作完成</body>', ForumRequestKind.rateLimited),
      (
        preferences().replaceAll('</form>', '操作完成</form>'),
        ForumRequestKind.server
      ),
    ]) {
      final client = _Client()
        ..responses.addAll([preferences(), preferences(), html, preferences()]);
      final service = accountService(client);
      final form = await service.fetchForumPreferences();
      await expectLater(
          service.saveForumPreferences(form, {
            'banidinfo': ['123']
          }),
          throwsA(isA<ForumRequestException>()
              .having((e) => e.kind, 'kind', kind)));
      expect(client.posts, hasLength(1));
      expect(
          client.getPaths,
          hasLength(
              html.contains('Unknown') || html.contains('<form') ? 3 : 2));
    }
  });
}

ForumAccountService accountService(_Client client) => ForumAccountService(
    client: () => client, sessionEpoch: () => 1, isLoggedIn: () => true);
final pngBytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
String avatarPage(int page, {String? icon}) => '''<ajax><![CDATA[
<span onclick="showimage('images','${icon ?? 'page$page.gif'}')"><img src="images/face/${icon ?? 'page$page.gif'}"></span>
<a onclick="sendmsg('pw_ajax.php','action=showface&page=${page - 1}','profile')">Previous</a>
<a onclick="sendmsg('pw_ajax.php','action=showface&page=${page + 1}','profile')">Next</a>
]]></ajax>''';
final invalidInput = throwsA(isA<ForumRequestException>()
    .having((e) => e.kind, 'kind', ForumRequestKind.invalidInput));
final loginRequired = throwsA(isA<ForumRequestException>()
    .having((e) => e.kind, 'kind', ForumRequestKind.loginRequired));
List<String> values(_Post post, String name) =>
    post.fields.where((e) => e.key == name).map((e) => e.value).toList();

class _Post {
  _Post(this.path, this.fields, this.multipart, this.files);
  final String path;
  final List<MapEntry<String, String>> fields;
  final bool multipart;
  final List<ForumFormFile> files;
}

class _Client extends ForumClient {
  final responses = <String>[];
  final getPaths = <String>[];
  final posts = <_Post>[];
  Future<String> Function()? getNext;
  Future<String> Function()? postNext;
  @override
  Future<String> getForm(String path,
      {void Function()? requireCurrentSession,
      bool followRedirects = true}) async {
    requireCurrentSession?.call();
    getPaths.add(path);
    return getNext != null ? getNext!() : responses.removeAt(0);
  }

  @override
  Future<String> postForm(
    String path,
    List<MapEntry<String, String>> fields, {
    bool multipart = false,
    List<ForumFormFile> files = const [],
    void Function()? requireCurrentSession,
  }) async {
    requireCurrentSession?.call();
    posts.add(_Post(path, List.of(fields), multipart, List.of(files)));
    return postNext != null ? postNext!() : responses.removeAt(0);
  }
}

const success = '<html><body>操作完成</body></html>';
String preferences({String token = 'fixture', String blacklist = ''}) => '''
<form id="preferences" method="post" action="profile.php?action=bbsset">
<input type="hidden" name="verify" value="$token"><input type="hidden" name="step" value="2">
<table>
<tr><td>编辑器</td><td><label><input type="radio" name="editor" value="1">可视化</label><label><input type="radio" name="editor" value="0" checked>代码</label></td></tr>
<tr><td>好友</td><td><label><input type="radio" name="friendcheck" value="0" checked>允许</label><label><input type="radio" name="friendcheck" value="2">拒绝</label></td></tr>
<tr><td>屏蔽用户组</td><td><label><input type="checkbox" name="msggroups[]" value="3" checked>组三</label><label><input type="checkbox" name="msggroups[]" value="7" checked>组七</label><input type="checkbox" name="msggroups[]" value="disabled-group" disabled></td></tr>
<tr><td>黑名单 UID</td><td><textarea name="banidinfo">$blacklist</textarea></td></tr>
</table>
<input name="t_num" value="20"><input name="readonly" value="preserve" readonly>
<input name="disabled" value="never" disabled><input type="checkbox" name="unchecked" value="never">
<input type="checkbox" name="defaultCheck" checked><input name="oldpwd" value="never"><input name="unusualPassword" type="password" value="never">
<fieldset disabled><legend><input name="legendPreserved" value="yes"></legend><input name="disabledFieldset" value="never"></fieldset>
<select name="multiple[]" multiple><option value="a">A</option><option value="b" selected>B</option><option selected>c</option><optgroup disabled><option selected value="never">Never</option></optgroup><option selected disabled value="never2">Never</option></select>
<select name="disabledSelected"><option selected disabled value="never">Never</option><option value="not-selected">Other</option></select>
<select name="fallbackSelect"><option disabled value="never">Never</option><option value="enabled">Enabled</option></select>
<input type="submit" name="submit" value="never">
</form>
''';
String profile({String token = 'fixture', String sensitive = 'fixture'}) => '''
<form method="post" action="profile.php?action=modify&amp;" enctype="multipart/form-data">
<input type="hidden" name="verify" value="$token"><input type="hidden" name="step" value="2">
<table>
<tr><td>昵称</td><td><input name="field_1" value="Old nickname"></td></tr>
<tr><td>来自</td><td><input name="profrom" value="Old place" maxlength="14"></td></tr>
<tr><td>个人主页</td><td><input name="prohomepage" value="" maxlength="75"></td></tr>
<tr><td>个性签名</td><td><input name="prohonor" value="Old signature"></td></tr>
<tr><td>自我简介</td><td><textarea name="prointroduce">Old intro</textarea></td></tr>
<tr><td>头像</td><td><label><input name="facetype" type="radio" value="1">系统头像</label><label><input name="facetype" type="radio" value="2">头像链接</label><label><input name="facetype" type="radio" value="3">头像上传</label><input type="hidden" name="proicon" value="old.gif"><input name="httpurl[0]" value="">头像宽度<input name="httpurl[1]" maxlength="3" value="">必须是 1 -- 150 之间的一个整数。头像高度<input name="httpurl[2]" maxlength="3" value="">必须是 1 -- 270 之间的一个整数。头像高度留空，则根据宽度自适应。头像宽度<input name="uploadurl[1]" maxlength="3" value="">必须是 1 -- 150 之间的一个整数。头像高度<input name="uploadurl[2]" maxlength="3" value="">必须是 1 -- 270 之间的一个整数。<input type="file" name="upload"></td></tr>
</table>
<textarea name="prosign">$sensitive footer</textarea><input name="proemail" value="$sensitive@example.invalid"><input name="propublicemail" type="checkbox" value="1" checked>
<input name="alipay" value="$sensitive-payment"><input name="contact[]" value="$sensitive-contact"><input type="checkbox" name="tradetype[]" value="2" checked><input type="checkbox" name="tradetype[]" value="4" checked>
<input name="oldpwd" type="password" value="never"><input name="propwd" type="password" value="never"><input name="check_pwd" type="password" value="never">
</form>
<script>CkFaceType('1'); if(document.creator.prointroduce.value.length>500){alert('limit');}</script>
''';
