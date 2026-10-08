/// Parses timestamps returned by PostgreSQL.
///
/// Legacy `timestamp without time zone` columns are stored in UTC in this
/// project. PostgREST omits the UTC suffix for those values, so append it
/// before parsing to avoid treating UTC as the device's local time.
DateTime parseDatabaseTimestamp(String value) {
  final hasExplicitZone = RegExp(r'(?:[zZ]|[+-]\d{2}(?::?\d{2})?)$')
      .hasMatch(value);
  final parsed = DateTime.parse(hasExplicitZone ? value : '${value}Z');
  return parsed.toLocal();
}

DateTime? tryParseDatabaseTimestamp(String? value) {
  if (value == null || value.isEmpty) return null;
  try {
    return parseDatabaseTimestamp(value);
  } on FormatException {
    return null;
  }
}
