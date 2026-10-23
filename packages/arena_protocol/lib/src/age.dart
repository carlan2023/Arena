/// Calendar age in UTC. A person is old enough on the day they turn [minAge].
///
/// A birthday of 29 February is treated as 1 March in a year that is not a
/// leap year, which is how Dart normalises that date.
bool isOldEnough(DateTime dateOfBirth, DateTime now, int minAge) {
  final birth = utcDate(dateOfBirth);
  final today = utcDate(now);
  final turns = DateTime.utc(birth.year + minAge, birth.month, birth.day);
  return !today.isBefore(turns);
}

/// The UTC calendar day of [date], with the time dropped.
DateTime utcDate(DateTime date) {
  final utc = date.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

/// A real calendar date as `yyyy-mm-dd`, or null when [raw] is not one.
DateTime? parseDateOfBirth(String raw) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
  if (match == null) return null;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

/// `yyyy-mm-dd` for the UTC calendar day of [date].
String formatDateOfBirth(DateTime date) {
  final day = utcDate(date);
  final y = day.year.toString().padLeft(4, '0');
  final m = day.month.toString().padLeft(2, '0');
  final d = day.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
