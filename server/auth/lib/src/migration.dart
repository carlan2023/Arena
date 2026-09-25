/// One schema change. The server applies every package's list in order, each
/// inside its own transaction, and records [id] in `schema_migrations`.
class Migration {
  final String id;
  final String sql;

  const Migration({required this.id, required this.sql});
}
