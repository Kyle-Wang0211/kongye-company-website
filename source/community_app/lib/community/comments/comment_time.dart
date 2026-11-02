/// Display only: the source timestamp remains unchanged. Recent timestamps use
/// elapsed time first, then local calendar days (not rounded 24-hour periods).
String formatCommunityCommentTime(Object? value, {DateTime? now}) {
  final parsed = value is DateTime
      ? value
      : value is String
      ? DateTime.tryParse(value)
      : null;
  if (parsed == null) return '';
  final date = parsed.toLocal();
  final current = (now ?? DateTime.now()).toLocal();
  final age = current.difference(date);
  final calendarLabel = '${date.month}月${date.day}日';
  if (age.isNegative) return calendarLabel;
  if (age <= const Duration(hours: 24)) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
  final days = DateTime.utc(
    current.year,
    current.month,
    current.day,
  ).difference(DateTime.utc(date.year, date.month, date.day)).inDays;
  if (days == 1) return '昨天';
  if (days == 2) return '前天';
  return calendarLabel;
}
