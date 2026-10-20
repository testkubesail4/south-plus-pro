import 'package:flutter/material.dart';

import '../../services/forum_url_resolver.dart';
import '../../services/parsers/thread_content_parser.dart';
import '../../theme/app_theme.dart';
import '../thread/thread_rich_content.dart';

/// Shows [source] as the site will render it: WindCode through the same
/// segments and renderer as a thread floor. Links and sale boxes are inert,
/// and media is private: the draft is not published yet.
///
/// The draft belongs to the signed-in account: when [closeOn] (its session
/// signals) notifies, the sheet empties and closes at once.
Future<void> showWindCodePreview(
  BuildContext context, {
  String? title,
  required String source,
  Uri? baseUri,
  Listenable? closeOn,
}) {
  final segments = source.trim().isEmpty
      ? null
      : ThreadContentParser(
          urls: ForumUrlResolver(baseUri: baseUri),
        ).parseWindCode(source);
  final closed = ValueNotifier(false);
  BuildContext? sheet;
  void close() {
    closed.value = true;
    final route =
        sheet != null && sheet!.mounted ? ModalRoute.of(sheet!) : null;
    if (route != null && route.isActive)
      Navigator.of(sheet!).removeRoute(route);
  }

  closeOn?.addListener(close);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      // Closed before its first frame: it goes once that frame is built.
      if (sheet == null && closed.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) => close());
      }
      sheet = context;
      final theme = Theme.of(context);
      return ValueListenableBuilder<bool>(
        valueListenable: closed,
        builder: (context, gone, child) =>
            gone ? const SizedBox.shrink() : child!,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (context, scroll) => ListView(
            controller: scroll,
            padding: EdgeInsets.fromLTRB(
              AppSpace.lg,
              0,
              AppSpace.lg,
              AppSpace.xl + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              Text('预览', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpace.md),
              if (title case final title? when title.trim().isNotEmpty) ...[
                Text(title.trim(), style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpace.md),
              ],
              if (segments == null)
                Text('暂无正文', style: theme.textTheme.bodySmall)
              else
                ThreadRichContent(
                  segments: segments,
                  // A draft: images stay memory-only, links stay with us.
                  privateMedia: true,
                  // Null would fall back to opening the browser.
                  onOpenLink: (_, __) async {},
                ),
            ],
          ),
        ),
      );
    },
  ).whenComplete(() {
    closeOn?.removeListener(close);
    closed.dispose();
  });
}
