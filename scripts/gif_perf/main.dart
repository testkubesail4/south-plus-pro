import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_rich_content.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/image_loading_settings.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

const origin = 'http://127.0.0.1:18765';

class FixtureSite extends ForumSite {
  const FixtureSite() : super('127.0.0.1');

  @override
  Uri get baseUri => Uri.parse(origin);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final route = PlatformDispatcher.instance.defaultRouteName;
  final args = Uri.parse(route).pathSegments;
  final tid = args.isEmpty ? '98100' : args.first;
  final manual = args.length > 1 && args[1] == 'manual';
  await (await SharedPreferences.getInstance()).setBool(
    'settings.playInlineAnimations',
    args.length > 1 && args[1] == 'play',
  );
  await ImageLoadingSettings.loadMode();
  await ImageLoadingSettings.saveMode(
    manual ? ImageLoadMode.manual : ImageLoadMode.automatic,
  );
  runApp(
    MaterialApp(
      onGenerateInitialRoutes: (_) => [
        MaterialPageRoute<void>(builder: (_) => GifBench(tid: tid)),
      ],
      theme: AppTheme.light,
      home: GifBench(tid: tid),
    ),
  );
}

final _client = HttpClient();

Future<void> record(String event, Map<String, Object?> data) async {
  final request = await _client.postUrl(Uri.parse('$origin/events'));
  final bytes = utf8.encode(jsonEncode({'event': event, ...data}));
  request.contentLength = bytes.length;
  request.add(bytes);
  final response = await request.close();
  await response.drain<void>();
  if (response.statusCode != 204) throw StateError('Event rejected: $event');
}

class GifBench extends StatefulWidget {
  const GifBench({super.key, required this.tid});

  final String tid;

  @override
  State<GifBench> createState() => _GifBenchState();
}

class _GifBenchState extends State<GifBench> {
  final page = GlobalKey();
  final timings = <FrameTiming>[];
  final repository = ForumRepository(
    config: const ForumNetworkConfig(
      site: FixtureSite(),
      mode: ForumNetworkMode.native,
      dohProvider: ForumNetworkConfig.defaultProvider,
    ),
  );
  bool visible = true;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(timings.addAll);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await measure();
      } catch (error) {
        await record('error', {'message': '$error'.split('\n').first});
      }
    });
  }

  Iterable<Element> descendants(Element parent) sync* {
    final children = <Element>[];
    parent.visitChildren(children.add);
    for (final child in children) {
      yield child;
      yield* descendants(child);
    }
  }

  ScrollPosition? get scrollPosition {
    final context = page.currentContext;
    if (context is! Element) return null;
    for (final element in descendants(context)) {
      final widget = element.widget;
      if (widget is! ListView || widget.scrollDirection != Axis.vertical) {
        continue;
      }
      final positions = widget.controller?.positions;
      if (positions != null && positions.length == 1) {
        final position = positions.single;
        if (position.hasContentDimensions) return position;
      }
    }
    return null;
  }

  Map<String, Object?> snapshot() {
    final cache = PaintingBinding.instance.imageCache;
    var mountedImages = 0;
    var decodedImages = 0;
    final dimensions = <String>{};
    final context = page.currentContext;
    if (context is Element) {
      for (final element in descendants(context)) {
        if (element.widget is! ThreadInlineImage) continue;
        mountedImages++;
        for (final child in descendants(element)) {
          final widget = child.widget;
          if (widget is RawImage && widget.image != null) {
            decodedImages++;
            final image = widget.image!;
            dimensions.add('${image.width}x${image.height}');
            break;
          }
        }
      }
    }
    return {
      'mountedImages': mountedImages,
      'decodedImages': decodedImages,
      'decodedSizes': dimensions.toList()..sort(),
      'cacheBytes': cache.currentSizeBytes,
      'cacheLimitBytes': cache.maximumSizeBytes,
      'cacheLive': cache.liveImageCount,
      'cachePending': cache.pendingImageCount,
    };
  }

  Future<void> measure() async {
    final phases = <(String, int, int)>[];
    Future<void> phase(String name, Future<void> Function() run) async {
      await record('start', {'phase': name, ...snapshot()});
      final start = Timeline.now;
      await run();
      phases.add((name, start, Timeline.now));
      await record('end', {'phase': name, ...snapshot()});
    }

    await phase('load', () async {
      final timeout = Stopwatch()..start();
      while (scrollPosition == null) {
        if (timeout.elapsed > const Duration(seconds: 20)) {
          throw StateError('Fixture thread failed to open');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await Future<void>.delayed(const Duration(seconds: 6));
    });
    await phase('top', () => Future<void>.delayed(const Duration(seconds: 4)));
    await phase('scroll', () async {
      final scroll = scrollPosition;
      if (scroll == null) throw StateError('Thread scroll view is unavailable');
      var atBottom = 0;
      var steps = 0;
      while (atBottom < 4 && steps++ < 450) {
        final target = (scroll.pixels + scroll.viewportDimension * .55).clamp(
          0.0,
          scroll.maxScrollExtent,
        );
        if (target - scroll.pixels > 1) {
          atBottom = 0;
          await scroll.animateTo(
            target,
            duration: const Duration(milliseconds: 280),
            curve: Curves.linear,
          );
        } else {
          atBottom++;
        }
        await Future<void>.delayed(const Duration(milliseconds: 90));
        if (steps % 10 == 0) {
          await record('checkpoint', {'step': steps, ...snapshot()});
        }
      }
      if (atBottom < 4 || scroll.pixels < scroll.viewportDimension) {
        throw StateError('Scroll did not cover the fixture thread');
      }
      await record(
          'sweep', {'steps': steps, 'logicalPixels': scroll.pixels.round()});
    });
    await phase(
      'bottom',
      () => Future<void>.delayed(const Duration(seconds: 4)),
    );
    await phase('exited', () async {
      setState(() => visible = false);
      await Future<void>.delayed(const Duration(seconds: 6));
    });
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    for (final (name, start, end) in phases) {
      final frames = timings.where((frame) {
        final vsync = frame.timestampInMicroseconds(FramePhase.vsyncStart);
        return vsync >= start && vsync < end;
      }).toList();
      final vsyncs = frames
          .map((frame) => frame.timestampInMicroseconds(FramePhase.vsyncStart))
          .toList();
      await record('timings', {
        'phase': name,
        'seconds': (end - start) / 1000000,
        'frames': frames.length,
        'build': frameStats(frames.map((frame) => frame.buildDuration)),
        'raster': frameStats(frames.map((frame) => frame.rasterDuration)),
        'total': frameStats(frames.map((frame) => frame.totalSpan)),
        'vsyncGap': frameStats([
          for (var i = 1; i < vsyncs.length; i++)
            Duration(microseconds: vsyncs[i] - vsyncs[i - 1]),
        ]),
      });
      if (name == 'scroll' && frames.isEmpty) {
        throw StateError('No frame timings during scroll');
      }
    }
    await record('done', {'tid': widget.tid});
  }

  Map<String, num> frameStats(Iterable<Duration> durations) {
    final times = durations.map((time) => time.inMicroseconds / 1000).toList()
      ..sort();
    if (times.isEmpty) return {};
    return {
      'p50Ms': times[((times.length - 1) * .5).round()],
      'p95Ms': times[((times.length - 1) * .95).round()],
      'maxMs': times.last,
      'overBudget': times.where((time) => time > 1000 / 60).length,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!visible) return const Scaffold();
    return ThreadDetailScreen(
      key: page,
      repository: repository,
      thread: ForumThread(
        title: 'GIF scroll',
        replies: 99,
        section: 'GIF scroll',
        url: '$origin/read.php?tid-${widget.tid}-page-1.html',
      ),
    );
  }
}
