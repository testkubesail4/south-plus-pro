import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'forum_connection_race.dart';
import 'forum_network_config.dart';

/// A transport instance owns one configuration and its shared DNS lifetime.
class ForumOptimizedTransport {
  ForumOptimizedTransport(this.config, {this.context}) {
    final custom = config.normalizedCustomDohUri;
    _resolvers = [
      if (custom != null)
        DohResolver.custom(
          endpoint: Uri.parse(custom),
          bootstrapAddresses: config.dohBootstrapAddresses,
          ipv6Enabled: config.ipv6Enabled,
          context: context,
        ),
      for (final provider in [
        config.dohProvider,
        ...DohProvider.values.where((p) => p != config.dohProvider),
      ])
        if (provider != DohProvider.doh090227Sb)
          DohResolver(
            provider: provider,
            ipv6Enabled: config.ipv6Enabled,
            context: context,
          ),
    ];
  }
  final ForumNetworkConfig config;
  final SecurityContext? context;
  late final List<DohResolver> _resolvers;
  final _connections = <ForumConnectionRace>{};
  final _cooldown = <String, DateTime>{};
  final _resolverCooldown = <(String, DohResolver), DateTime>{};
  bool _closed = false;

  Future<ConnectionTask<Socket>> connect(
    Uri uri, {
    required Duration timeout,
  }) async {
    if (_closed) throw StateError('Transport is closed');
    final race = ForumConnectionRace(
      uri,
      timeout: timeout,
      context: context,
      onFailure: (address) {
        if (_cooldown.length >= 256) _cooldown.remove(_cooldown.keys.first);
        _cooldown['${uri.host}/${address.address}'] = DateTime.now().add(
          const Duration(seconds: 5),
        );
      },
    );
    _connections.add(race);
    final literal = InternetAddress.tryParse(uri.host);
    if (literal != null) {
      race.add(_eligible(uri.host, [literal]));
      race.finishAdding();
    } else {
      var sources = 3;
      void done() {
        if (--sources == 0) race.finishAdding();
      }

      final user = <String>[
        ...?config.hostAddresses[uri.host],
        if (uri.host == config.site.host && config.fixedAddress != null)
          config.fixedAddress!,
      ];
      final userTimer = Timer(const Duration(milliseconds: 450), () {
        race.add(_eligible(uri.host, user.map(InternetAddress.new)));
        done();
      });
      // Reserve rescue opportunities instead of truncating the builtin tail.
      final builtinTimer = Timer(
        Duration(milliseconds: user.isEmpty ? 450 : 800),
        () {
          race.add(
            _eligible(
              uri.host,
              ForumNetworkConfig.builtInHostAddresses(
                uri.host,
              ).map(InternetAddress.new),
            ),
            priority: true,
          );
          done();
        },
      );
      final subscription = _resolve(uri.host).listen((addresses) {
        race.add(_eligible(uri.host, addresses), priority: true);
      }, onDone: done);
      unawaited(
        race.socket.then((_) {}, onError: (Object _) {}).whenComplete(() async {
          userTimer.cancel();
          builtinTimer.cancel();
          await subscription.cancel();
        }),
      );
    }
    unawaited(
      race.socket
          .then((_) {}, onError: (Object _) {})
          .whenComplete(() => _connections.remove(race)),
    );
    return ConnectionTask.fromSocket(race.socket, race.cancel);
  }

  List<InternetAddress> _eligible(
    String host,
    Iterable<InternetAddress> addresses,
  ) {
    final seen = <String>{};
    final values = addresses
        .where(
          (a) =>
              seen.add(a.address) &&
              !(_cooldown['$host/${a.address}']?.isAfter(DateTime.now()) ??
                  false),
        )
        .toList();
    final v4 = values.where((a) => a.type == InternetAddressType.IPv4).toList();
    final v6 = config.ipv6Enabled
        ? values.where((a) => a.type == InternetAddressType.IPv6).toList()
        : <InternetAddress>[];
    return [
      for (var i = 0; i < math.max(v4.length, v6.length); i++) ...[
        if (i < v6.length) v6[i],
        if (i < v4.length) v4[i],
      ],
    ];
  }

  Stream<List<InternetAddress>> _resolve(String host) {
    final subscriptions = <StreamSubscription<List<InternetAddress>>>[];
    final timers = <Timer>[];
    var next = 0;
    var active = 0;
    var cancelled = false;
    late StreamController<List<InternetAddress>> controller;
    void launch() {
      if (cancelled) return;
      while (next < _resolvers.length &&
          (_resolverCooldown[(host, _resolvers[next])]?.isAfter(DateTime.now()) ??
              false)) {
        next++;
      }
      if (next == _resolvers.length) {
        if (active == 0) unawaited(controller.close());
        return;
      }
      final resolver = _resolvers[next++];
      active++;
      var received = false;
      subscriptions.add(
        resolver.lookupCandidates(host).listen(
              (addresses) {
                received = true;
                if (!cancelled) controller.add(addresses);
              },
              onError: (Object _) {},
              onDone: () {
                active--;
                if (!received) {
                  if (_resolverCooldown.length >= 256) {
                    _resolverCooldown.remove(_resolverCooldown.keys.first);
                  }
                  _resolverCooldown[(host, resolver)] = DateTime.now().add(
                    const Duration(seconds: 5),
                  );
                }
                if (!cancelled) launch();
              },
            ),
      );
      if (active < 2 && next < _resolvers.length) {
        timers.add(
          Timer(const Duration(milliseconds: 200), () {
            if (active < 2) launch();
          }),
        );
      }
    }

    controller = StreamController<List<InternetAddress>>(
      onListen: launch,
      onCancel: () async {
        cancelled = true;
        for (final timer in timers) {
          timer.cancel();
        }
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  void close({bool force = true}) {
    _closed = true;
    void closeResolvers() {
      for (final resolver in _resolvers) {
        resolver.close();
      }
      _cooldown.clear();
    }

    if (force) {
      for (final connection in _connections.toList()) {
        connection.cancel();
      }
      closeResolvers();
    } else {
      unawaited(
        Future.wait(
          _connections.map(
            (c) => c.socket.then((_) {}, onError: (Object _) {}),
          ),
        ).then((_) => closeResolvers()),
      );
    }
  }
}
