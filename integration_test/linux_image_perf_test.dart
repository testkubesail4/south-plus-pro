import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_rich_content.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/image_loading_settings.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

class _FixtureSite extends ForumSite {
  const _FixtureSite() : super('127.0.0.1');

  @override
  Uri get baseUri => Uri.parse('http://127.0.0.1:8765/');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment('PERF_PHASE', defaultValue: 'first');
  const noImages = bool.fromEnvironment('PERF_NO_IMAGES');

  testWidgets('synthetic image scroll measurement ($phase)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await ImageLoadingSettings.saveMode(
        noImages ? ImageLoadMode.noImages : ImageLoadMode.automatic);
    final repository = ForumRepository(
      config: const ForumNetworkConfig(
        site: _FixtureSite(),
        dohEnabled: false,
        dohProvider: ForumNetworkConfig.defaultProvider,
      ),
    );
    final statsClient = HttpClient();
    addTearDown(() => statsClient.close(force: true));

    Future<Map<String, dynamic>> stats() async {
      final request = await statsClient
          .getUrl(Uri.parse('http://127.0.0.1:8765/perf/stats'));
      final response = await request.close();
      expect(response.statusCode, 200);
      return jsonDecode(await response.transform(utf8.decoder).join())
          as Map<String, dynamic>;
    }

    Future<void> waitForPage(int page) async {
      final finder = find.textContaining('Fixture performance page $page',
          findRichText: true);
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(finder, findsWidgets);
      await tester.pumpAndSettle();
    }

    final samples = <String, Map<String, Object>>{};
    void sampleImages() {
      for (final element in find.byType(ThreadInlineImage).evaluate()) {
        final inline = element.widget as ThreadInlineImage;
        if (samples.containsKey(inline.image.url)) continue;
        final index = int.parse(Uri.parse(inline.image.url)
            .pathSegments
            .last
            .replaceAll('.png', ''));
        final group =
            index < 10 ? 'portrait' : (index < 30 ? 'landscape' : 'small');
        final quota = group == 'small' ? 1 : 2;
        if (samples.values.where((sample) => sample['group'] == group).length >=
            quota) continue;
        final decoded = find.descendant(
          of: find.byWidget(inline),
          matching: find.byWidgetPredicate(
              (widget) => widget is RawImage && widget.image != null),
        );
        if (decoded.evaluate().isEmpty) continue;
        final raw = tester.widget<RawImage>(decoded.first);
        final rect = tester.getRect(decoded.first);
        if (rect.bottom <= 0 || rect.top >= tester.view.physicalSize.height) {
          continue;
        }
        samples[inline.image.url] = {
          'group': group,
          'decodedWidth': raw.image!.width,
          'decodedHeight': raw.image!.height,
          'screenWidth': rect.width,
          'screenHeight': rect.height,
          'devicePixelRatio': tester.view.devicePixelRatio,
        };
      }
    }

    Map<String, Object> summary(List<double> values) {
      values.sort();
      double percentile(double fraction) =>
          values[(fraction * (values.length - 1)).round()];
      return {
        'count': values.length,
        'p50Ms': percentile(0.5),
        'p90Ms': percentile(0.9),
        'maxMs': values.last,
        'over16Ms': values.where((value) => value > 16).length,
      };
    }

    Future<void> measure(String name) async {
      samples.clear();
      final before = await stats();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: ThreadDetailScreen(
          repository: repository,
          thread: const ForumThread(
            title: 'Fixture performance thread',
            replies: 49,
            section: 'Fixture board',
            url: 'http://127.0.0.1:8765/read.php?tid-900004.html',
          ),
        ),
      ));
      await waitForPage(1);
      // Flush timings from launch; capture only the scripted scrolling interval.
      await Future<void>.delayed(const Duration(seconds: 2));
      final frames = <FrameTiming>[];
      void record(List<FrameTiming> timings) => frames.addAll(timings);
      SchedulerBinding.instance.addTimingsCallback(record);
      try {
        await binding.traceAction(() async {
          for (var page = 1; page <= 3; page++) {
            final scrollable = find.byType(Scrollable).first;
            final position = tester.state<ScrollableState>(scrollable).position;
            // Eight flings total, each followed by a full stepped sweep so every
            // post is visited even when a long image changes the scroll extent.
            final passes = page == 1 ? 4 : 2;
            for (var pass = 0; pass < passes; pass++) {
              final down = pass.isEven;
              await tester.fling(
                  scrollable, Offset(0, down ? -550 : 550), 1500);
              await tester.pumpAndSettle();
              var steps = 0;
              while (down
                  ? position.pixels < position.maxScrollExtent
                  : position.pixels > 0) {
                expect(++steps, lessThan(200), reason: 'bounded scroll sweep');
                final target = (position.pixels + (down ? 500 : -500))
                    .clamp(0.0, position.maxScrollExtent);
                position.jumpTo(target);
                await tester.pump(const Duration(milliseconds: 50));
                sampleImages();
              }
              await tester.pumpAndSettle();
              sampleImages();
            }
            if (page < 3) {
              position.jumpTo(0);
              await tester.pumpAndSettle();
              await tester.tap(find.byTooltip('下一页').first);
              await waitForPage(page + 1);
            }
          }
        }, streams: ['Dart']);
        // Engine batches FrameTiming notifications once per second.
        await Future<void>.delayed(const Duration(seconds: 2));
      } finally {
        SchedulerBinding.instance.removeTimingsCallback(record);
      }
      expect(frames, isNotEmpty);
      final after = await stats();
      final requests = <String, Object>{};
      for (final url in after.keys) {
        final old = before[url] as Map<String, dynamic>? ?? {};
        final current = after[url] as Map<String, dynamic>;
        final count = (current['count'] as int) - ((old['count'] as int?) ?? 0);
        if (count > 0) {
          requests[url] = {
            'count': count,
            'bytes': (current['bytes'] as int) - ((old['bytes'] as int?) ?? 0),
          };
        }
      }
      final timeline = binding.reportData!['timeline'] as Map<String, dynamic>;
      final builds = <String, int>{
        'ThreadInlineImage.build': 0,
        'ThreadRichContent.build': 0,
      };
      for (final event in timeline['traceEvents'] as List<dynamic>) {
        final data = event as Map<String, dynamic>;
        final eventName = data['name'];
        if (builds.containsKey(eventName) &&
            (data['ph'] == 'B' || data['ph'] == 'X')) {
          builds[eventName as String] = builds[eventName]! + 1;
        }
      }
      final cache = PaintingBinding.instance.imageCache;
      final result = {
        'phase': name,
        'mode': noImages ? 'no-images' : 'automatic',
        'environment': 'Flutter3.38.4 debug Linux Xvfb software rendering',
        'fixture': '40 distinct solid-color PNGs; 10 repeated URLs; 3 pages',
        'script':
            '8 flings plus 500px down/up sweeps and 2 page transitions; 50ms pumps',
        'requests': requests,
        'buildFrames': summary(frames
            .map((frame) => frame.buildDuration.inMicroseconds / 1000)
            .toList()),
        'rasterFrames': summary(frames
            .map((frame) => frame.rasterDuration.inMicroseconds / 1000)
            .toList()),
        'imageCache': {
          'currentSize': cache.currentSize,
          'currentSizeBytes': cache.currentSizeBytes,
          'liveImageCount': cache.liveImageCount,
        },
        'decodeSamples': samples,
        'scrollBuilds': builds,
      };
      if (noImages) {
        expect(samples, isEmpty);
        expect(requests, isEmpty);
      } else {
        expect(samples.length, 5);
        expect(builds.values, everyElement(greaterThan(0)));
        if (name == 'first') {
          expect(requests.length, 40);
          expect((requests['/perf/image/0.png'] as Map)['count'], 1);
        } else {
          expect(requests, isEmpty);
        }
      }
      final output = Directory('/output/perf-4');
      await output.create(recursive: true);
      await File('${output.path}/$name.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(result));
      await File('${output.path}/$name-timeline.json')
          .writeAsString(jsonEncode(timeline));
    }

    await measure(phase);
    if (phase == 'first') await measure('revisit');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
