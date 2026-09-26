// Internal helpers for value equality and JSON parsing. Not exported.

bool listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Runs [parse] and turns any type or range error into a [FormatException],
/// so callers parsing untrusted input only need to catch one error type.
T parseJson<T>(String what, T Function() parse) {
  try {
    return parse();
  } on FormatException {
    rethrow;
  } catch (e) {
    throw FormatException('Invalid $what JSON: $e');
  }
}

List<int> intList(Object? value) =>
    List<int>.unmodifiable((value as List).map((e) => e as int));

T enumByName<T extends Enum>(List<T> values, Object? name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  throw FormatException('Unknown value "$name"');
}
