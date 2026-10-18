import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Calls [onLeft] when the screen stops showing this widget: an opaque page
/// covers its route, through any sheets or dialogs between, or its tab is put
/// away (the home shell turns a hidden tab's tickers off). Sheets and dialogs
/// alone leave it on screen.
mixin LeaveWatch<T extends StatefulWidget> on State<T> {
  ValueListenable<bool>? _onstage;

  void onLeft();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final onstage = TickerMode.getNotifier(context);
    if (identical(onstage, _onstage)) return;
    _onstage?.removeListener(_changed);
    _onstage = onstage..addListener(_changed);
  }

  // Raised while the overlay or the shell builds.
  void _changed() => scheduleMicrotask(() {
        if (mounted && _onstage?.value == false) onLeft();
      });

  @override
  void dispose() {
    _onstage?.removeListener(_changed);
    super.dispose();
  }
}
