import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/attachment_saver.dart';

const _url = 'job.php?action-download-pid-tpc-tid-2965509-aid-479474.html';
const _archive = [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c, 1, 2, 3];

class _RealHttpOverrides extends HttpOverrides {}

class _LocalForumClient extends ForumClient {
  _LocalForumClient(this.origin, HttpClient transport)
      : super(httpClient: transport, delay: (_) async {});
  final Uri origin;
  @override
  Uri get baseUri => origin;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late Directory directory;
  late HttpClient transport;
  late ForumClient client;
  late void Function(HttpRequest) serve;
  late List<HttpRequest> requests;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    directory = await Directory.systemTemp.createTemp('attachment_test_');
    transport = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(), _RealHttpOverrides());
    client = _LocalForumClient(
        Uri.parse('http://127.0.0.1:${server.port}/'), transport);
    requests = [];
    server.listen((request) {
      if (request.uri.path == '/session') {
        request.response.cookies.add(Cookie('winduser', 'test-session'));
        request.response.write('ok');
        request.response.close();
      } else {
        requests.add(request);
        serve(request);
      }
    });
    await client.get('/session');
  });
  tearDown(() async {
    transport.close(force: true);
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test('app session downloads attachment bytes instead of anonymous HTML',
      () async {
    serve = (request) {
      request.response.headers.contentType =
          ContentType('application', 'x-7z-compressed');
      request.response.headers
          .set('content-disposition', 'attachment; filename="Record.7z"');
      request.response.add(_archive);
      request.response.close();
    };
    final attachment = await client.downloadAttachment(_url,
        directory: directory, suggestedName: ' Record.7z');
    expect(await attachment.file.readAsBytes(), _archive,
        reason: 'ATTACHMENT: save real archive, not browser login page');
    expect(requests.single.headers.value(HttpHeaders.cookieHeader),
        'winduser=test-session',
        reason: 'ATTACHMENT: app session owns request');
    expect(attachment.fileName, 'Record.7z');
  });

  test(
      'streamed binary is exact and an interrupted body leaves no partial file',
      () async {
    var truncate = false;
    final payload = List<int>.filled(2048, 0x5a);
    serve = (request) {
      request.response.headers.contentType = ContentType.binary;
      request.response.contentLength = truncate ? 4096 : payload.length;
      request.response.add(payload);
      request.response.close().catchError((_) {});
    };
    final attachment =
        await client.downloadAttachment(_url, directory: directory);
    expect(await attachment.file.readAsBytes(), payload,
        reason:
            'ATTACHMENT: streaming after the bounded sniff preserves bytes');
    await attachment.file.parent.delete(recursive: true);
    truncate = true;
    await expectLater(client.downloadAttachment(_url, directory: directory),
        throwsA(isA<HttpException>()));
    expect(await directory.list().toList(), isEmpty,
        reason:
            'ATTACHMENT: interrupted response is never exported or retained');
  });

  test('only genuine attachment links at exact active origin are admitted',
      () async {
    expect(client.isAttachmentUrl(_url), isTrue);
    expect(
        client.isAttachmentUrl(
            '${client.baseUri}job.php?action=download&aid=479474'),
        isTrue);
    for (final url in [
      '${client.baseUri}job.php?action=download&aid=0',
      '${client.baseUri}read.php?tid-2965509.html',
      '${client.baseUri}job.php?action-delete-aid-479474.html',
      'https://foreign.example/$_url',
      'http://user:password@127.0.0.1:${server.port}/$_url',
      'http://127.0.0.1:${server.port + 1}/$_url',
    ]) {
      expect(client.isAttachmentUrl(url), isFalse,
          reason: 'ATTACHMENT: reject nonattachment or foreign origin');
      await expectLater(client.downloadAttachment(url, directory: directory),
          throwsA(isA<AttachmentDownloadException>()));
    }
    expect(requests, isEmpty,
        reason: 'ATTACHMENT: rejected URLs never make requests');
  });

  test(
      'same-origin redirect refreshes cookies; foreign redirect is never requested',
      () async {
    final foreign = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var foreignRequests = 0;
    foreign.listen((request) {
      foreignRequests++;
      request.response.add(_archive);
      request.response.close();
    });
    var foreignRedirect = false;
    serve = (request) {
      if (request.uri.path == '/job.php') {
        request.response.statusCode = HttpStatus.found;
        request.response.cookies.add(Cookie('winduser', 'refreshed-session'));
        request.response.headers.set(
            HttpHeaders.locationHeader,
            foreignRedirect
                ? 'http://127.0.0.1:${foreign.port}/archive'
                : '/archive');
      } else {
        request.response.add(_archive);
      }
      request.response.close();
    };
    try {
      final attachment = await client.downloadAttachment(_url,
          directory: directory, suggestedName: ' Record.7z');
      expect(await attachment.file.readAsBytes(), _archive);
      expect(attachment.fileName, 'Record.7z');
      expect(requests.last.headers.value(HttpHeaders.cookieHeader),
          'winduser=refreshed-session',
          reason: 'ATTACHMENT: redirected download uses refreshed app session');
      foreignRedirect = true;
      await expectLater(client.downloadAttachment(_url, directory: directory),
          throwsA(isA<AttachmentDownloadException>()),
          reason:
              'ATTACHMENT: foreign-origin redirects must fail before transfer');
      expect(foreignRequests, 0,
          reason:
              'ATTACHMENT: foreign redirect must receive neither request nor cookie');
    } finally {
      await foreign.close(force: true);
    }
  });

  test('HTML, denied, empty and redirect-loop responses leave no saved files',
      () async {
    for (final scenario in [
      'html',
      'mislabelledHtml',
      'bomHtml',
      'denied',
      'empty',
      'loop'
    ]) {
      serve = (request) {
        if (scenario == 'html')
          request.response.headers.contentType = ContentType.html;
        if (scenario == 'denied')
          request.response.statusCode = HttpStatus.forbidden;
        if (scenario == 'loop') {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(HttpHeaders.locationHeader, '/$_url');
        } else if (scenario != 'empty') {
          if (scenario == 'bomHtml') request.response.add([0xef, 0xbb, 0xbf]);
          request.response.write(
              '  <!DOCTYPE html><html><body>Login or permission denied</body></html>');
        }
        request.response.close();
      };
      await expectLater(client.downloadAttachment(_url, directory: directory),
          throwsA(isA<AttachmentDownloadException>()),
          reason: 'ATTACHMENT: $scenario is not downloadable data');
      expect(await directory.list().toList(), isEmpty,
          reason: 'ATTACHMENT: $scenario cleans temporary files');
    }
  });

  test(
      'native export receives only a temporary file and cleanup covers success, cancel and errors',
      () async {
    const saver = MethodChannel('south_plus_rewrite/attachment_saver');
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    serve = (request) {
      request.response.add(_archive);
      request.response.close();
    };
    final repository = ForumRepository(client: client);
    try {
      for (final result in ['saved', 'cancelled', 'error']) {
        String? sourcePath;
        messenger.setMockMethodCallHandler(saver, (call) async {
          expect(call.method, 'saveAttachment');
          final args = Map<String, dynamic>.from(call.arguments as Map);
          expect(args.keys.toSet(), {'path', 'fileName', 'mimeType'},
              reason:
                  'ATTACHMENT: native boundary never receives URL or cookies');
          expect(args['fileName'], 'Record.7z');
          sourcePath = args['path'] as String;
          expect(await File(sourcePath!).readAsBytes(), _archive,
              reason: 'ATTACHMENT: authenticated bytes reach export boundary');
          if (result == 'error')
            throw PlatformException(
                code: 'save_failed', message: 'Write failed');
          return result == 'saved';
        });
        final export =
            AttachmentSaver.save(repository, _url, suggestedName: ' Record.7z');
        if (result == 'error') {
          await expectLater(export, throwsA(isA<AttachmentSaveException>()));
        } else {
          expect(await export, result == 'saved');
        }
        expect(sourcePath, isNotNull);
        expect(await File(sourcePath!).exists(), isFalse,
            reason:
                'ATTACHMENT: $result always removes private temporary data');
        expect(await directory.list().toList(), isEmpty);
      }
      var exports = 0;
      messenger.setMockMethodCallHandler(saver, (_) async {
        exports++;
        return true;
      });
      serve = (request) {
        request.response.headers.contentType = ContentType.html;
        request.response.write('<html>Login</html>');
        request.response.close();
      };
      await expectLater(AttachmentSaver.save(repository, _url),
          throwsA(isA<AttachmentDownloadException>()));
      expect(exports, 0,
          reason: 'ATTACHMENT: authentication HTML never reaches file saver');
      expect(await directory.list().toList(), isEmpty);
    } finally {
      messenger.setMockMethodCallHandler(saver, null);
      messenger.setMockMethodCallHandler(paths, null);
    }
  });

  test('disposition filename is decoded and cannot escape save target',
      () async {
    serve = (request) {
      request.response.headers.set('content-disposition',
          "attachment; filename*=UTF-8''..%2F..%5CRecord.7z");
      request.response.add(_archive);
      request.response.close();
    };
    final attachment =
        await client.downloadAttachment(_url, directory: directory);
    expect(attachment.fileName, '_.._Record.7z',
        reason: 'ATTACHMENT: filename has no traversal separators');
    expect(attachment.file.parent.parent.path, directory.path);
    expect(await attachment.file.readAsBytes(), _archive);
  });
}
