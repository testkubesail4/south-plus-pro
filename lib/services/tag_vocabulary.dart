class TagVocabularyEntry {
  const TagVocabularyEntry({required this.label, required this.userCount});

  final String label;
  final int userCount;
}

List<TagVocabularyEntry> tagVocabulary(
  Map<String, List<String>> byUid, {
  String? query,
  Iterable<String> exclude = const [],
}) {
  final labels = <String, String>{};
  final users = <String, Set<String>>{};
  // First spelling in stable store map iteration order wins, not UID order or history.
  for (final entry in byUid.entries) {
    for (final raw in entry.value) {
      final label = raw.trim();
      if (label.isEmpty) continue;
      final key = label.toLowerCase();
      labels.putIfAbsent(key, () => label);
      (users[key] ??= <String>{}).add(entry.key);
    }
  }
  final search = query?.trim().toLowerCase() ?? '';
  final excluded = exclude.map((label) => label.trim().toLowerCase()).toSet();
  final entries = [
    for (final entry in labels.entries)
      if (!excluded.contains(entry.key) && entry.key.contains(search))
        TagVocabularyEntry(
            label: entry.value, userCount: users[entry.key]!.length),
  ];
  entries.sort((a, b) {
    final aKey = a.label.toLowerCase();
    final bKey = b.label.toLowerCase();
    final prefix = (aKey.startsWith(search) ? 0 : 1)
        .compareTo(bKey.startsWith(search) ? 0 : 1);
    if (prefix != 0) return prefix;
    final count = b.userCount.compareTo(a.userCount);
    return count != 0 ? count : aKey.compareTo(bKey);
  });
  // Empty queries return the whole derived vocabulary in the same ranking.
  return List.unmodifiable(entries);
}
