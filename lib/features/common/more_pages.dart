import 'package:flutter/widgets.dart';

import '../../services/loading_preferences.dart';

/// The pages a list appends after its first under 自动接续 (the [domain]'s
/// 加载与分页 mode), each the one the page before it named as next; never a
/// guessed page.
///
/// A row repeats only by its native id: rows without one always show.
class MorePages<P> {
  MorePages({
    required this.fetch,
    required this.nextOf,
    required this.idsOf,
    required this.changed,
    required this.domain,
  });

  /// Reads the page [nextOf] named.
  final Future<P> Function(String path) fetch;
  final String? Function(P page) nextOf;
  final Iterable<String?> Function(P page) idsOf;
  final VoidCallback changed;
  final LoadingDomain domain;

  final pages = <P>[];
  bool loading = false;
  Object? error;
  // Pages in a row that added no row; two pause 自动接续.
  int emptyRun = 0;
  int _generation = 0;

  bool get continuous =>
      LoadingPreferences.modeFor(domain) == LoadingMode.continuous;

  bool get paused => emptyRun >= 2;

  /// Drops every appended page; an answer still on its way is dropped too.
  void reset() {
    _generation++;
    pages.clear();
    loading = false;
    error = null;
    emptyRun = 0;
  }

  /// Drops a page still on its way, keeping those shown: a write began.
  void cancelPending() {
    _generation++;
    loading = false;
  }

  String? nextAfter(P first) => nextOf(pages.isEmpty ? first : pages.last);

  /// Whether [id] was already shown on an earlier page; marks it shown.
  static bool repeats(Set<String> seen, String? id) =>
      id != null && !seen.add(id);

  /// Appends the page after the last one shown, if 自动接续 and the list
  /// end is near.
  void maybeLoad(P? first, ScrollController scroll) {
    if (first == null ||
        !continuous ||
        loading ||
        error != null ||
        paused ||
        // One list: not while an outgoing one still fades.
        scroll.positions.length != 1 ||
        nextAfter(first) == null) {
      return;
    }
    final position = scroll.position;
    if (position.extentAfter < position.viewportDimension * 1.5) {
      load(first, scroll);
    }
  }

  Future<void> load(P first, ScrollController scroll) async {
    final path = nextAfter(first);
    if (path == null || loading) return;
    final generation = _generation;
    loading = true;
    error = null;
    changed();
    try {
      final page = await fetch(path);
      if (generation != _generation) return;
      final seen = <String>{
        for (final shown in [first, ...pages])
          for (final id in idsOf(shown))
            if (id != null) id,
      };
      final added = idsOf(page).any((id) => id == null || !seen.contains(id));
      loading = false;
      pages.add(page);
      emptyRun = added ? 0 : emptyRun + 1;
      changed();
      // A page that shows nothing adds no height to scroll through.
      if (!added) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => maybeLoad(first, scroll));
      }
    } catch (e) {
      if (generation != _generation) return;
      loading = false;
      error = e;
      changed();
    }
  }

  /// The footer's 重试 or 继续加载.
  void retry(P first, ScrollController scroll) {
    error = null;
    emptyRun = 0;
    load(first, scroll);
  }
}
