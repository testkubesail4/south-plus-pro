import '../models/forum_models.dart';
import 'forum_url_resolver.dart';

List<ForumSearchBoard> mergeSearchBoardHierarchy(
  List<ForumSearchBoard> searchOptions,
  List<ForumSection> homeSections, {
  Uri? baseUri,
}) {
  final urls = ForumUrlResolver(baseUri: baseUri);
  final result = <ForumSearchBoard>[];
  bool isHeading(ForumSearchBoard board) => board.name.trim().startsWith('>>');
  String label(String name) => name
      .replaceFirst(RegExp(r'^\s*>>\s*'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  for (var start = 0; start < searchOptions.length;) {
    final heading = searchOptions[start];
    if (!isHeading(heading)) {
      result.add(heading);
      start++;
      continue;
    }
    var end = start + 1;
    while (end < searchOptions.length && !isHeading(searchOptions[end])) {
      end++;
    }
    final section = homeSections
        .where((section) => label(section.title) == label(heading.name))
        .firstOrNull;
    final group = searchOptions.sublist(start + 1, end);
    result.add(heading);
    if (section == null) {
      result.addAll(group);
      start = end;
      continue;
    }

    final available = group.map((board) => board.id).toSet();
    final parents = <String, String>{};
    for (final board in section.items) {
      final parent = urls.fidFromUrl(board.url);
      if (parent == null || !available.contains(parent)) continue;
      for (final child in board.children) {
        final id = urls.fidFromUrl(child.url);
        if (id != null && id != parent && available.contains(id)) {
          parents[id] = parent;
        }
      }
    }

    final emitted = <ForumSearchBoard>{};
    void append(ForumSearchBoard board, int depth) {
      if (!emitted.add(board)) return;
      result.add(ForumSearchBoard(
          id: board.id,
          name: board.name,
          depth: depth,
          selectable: board.selectable));
      for (final child
          in group.where((child) => parents[child.id] == board.id)) {
        append(child, depth + 1);
      }
    }

    for (final board in group) {
      if (!parents.containsKey(board.id)) append(board, board.depth);
    }
    for (final board in group) {
      if (!emitted.contains(board)) append(board, board.depth);
    }
    start = end;
  }
  return result;
}
