// Omitted month/day options use calendar bounds; supplied native lists also apply.
String? validateNativeDate({
  required String? year,
  required String? month,
  required String? day,
  required Iterable<String> yearOptions,
  Iterable<String>? monthOptions,
  Iterable<String>? dayOptions,
}) {
  const incomplete = '不完整的日期，请选择年、月、日或清空';
  const invalid = '日期不存在，请重新选择';
  final parts = [year ?? '', month ?? '', day ?? ''];
  if (parts.every((part) => part.isEmpty)) return null;
  if (parts.any((part) => part.isEmpty)) return incomplete;
  final digits = RegExp(r'^[0-9]+$');
  if (parts.any((part) => !digits.hasMatch(part)) ||
      !yearOptions.contains(parts[0]) ||
      (monthOptions != null && !monthOptions.contains(parts[1])) ||
      (dayOptions != null && !dayOptions.contains(parts[2]))) {
    return invalid;
  }
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null ||
      y < 1 ||
      m == null ||
      m < 1 ||
      m > 12 ||
      d == null ||
      d < 1 ||
      d > 31) {
    return invalid;
  }
  // Native options can have holes, but cannot make an impossible date valid.
  try {
    final date = DateTime.utc(y, m, d);
    return date.year == y && date.month == m && date.day == d ? null : invalid;
  } on ArgumentError {
    return invalid;
  }
}
