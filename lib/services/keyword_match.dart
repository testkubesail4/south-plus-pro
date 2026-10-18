bool? matchKeyword(String query, Iterable<String?> fields,
    {bool truncated = false}) {
  final words = query.trim().toLowerCase().split(RegExp(r'\s+'));
  final text = fields.whereType<String>().join('\n').toLowerCase();
  if (words.every(text.contains)) return true;
  return truncated ? null : false;
}
