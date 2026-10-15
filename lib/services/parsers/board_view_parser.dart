// Redirect-only board entries name a view, not another board.
String? pictureWallBoardName(String name) {
  if (name == '图墙模式') return '';
  return RegExp(
    r'^(.*?)\s*[（(]\s*图墙模式\s*[）)]$',
  ).firstMatch(name)?.group(1)?.trim();
}
