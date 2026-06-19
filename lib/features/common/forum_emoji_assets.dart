String? forumEmojiAssetNameForUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final path = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
  if (!path.startsWith('images/post/smile/')) return null;
  return 'assets/forum_emoji/$path';
}

String forumEmojiAssetNameFromPath(String path) {
  return 'assets/forum_emoji/$path';
}
