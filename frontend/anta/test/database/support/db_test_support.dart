import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:anta/database/database.dart';

/// Opens the real [AppDatabase] — real schema, real migrations, real DAOs —
/// over an in-memory SQLite database.
///
/// `NativeDatabase.memory()` works under `flutter test` on this project with
/// no extra setup, so these tests need no fixtures on disk and leave nothing
/// behind. Every test gets its own database.
Future<AppDatabase> openTestDatabase({QueryInterceptor? interceptor}) async {
  final executor = interceptor == null
      ? NativeDatabase.memory()
      : NativeDatabase.memory().interceptWith(interceptor);
  final db = AppDatabase.forTesting(executor);
  // Drift opens lazily; force `onCreate` (and therefore the index creation
  // this suite is largely about) to run before the test body.
  await db.customSelect('SELECT 1').get();
  return db;
}

/// Names of every index SQLite knows about, excluding the implicit
/// `sqlite_autoindex_*` entries it creates for primary keys and UNIQUE
/// constraints.
Future<Set<String>> indexNames(AppDatabase db) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND name NOT LIKE 'sqlite_autoindex_%'",
      )
      .get();
  return {for (final row in rows) row.read<String>('name')};
}

/// Names of every table, excluding SQLite's internal bookkeeping and the FTS5
/// shadow tables that back `notes_fts`.
Future<Set<String>> tableNames(AppDatabase db) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type IN ('table', 'view') "
        "AND name NOT LIKE 'sqlite_%'",
      )
      .get();
  return {for (final row in rows) row.read<String>('name')};
}

/// The `EXPLAIN QUERY PLAN` output for [sql], one line per step.
///
/// This is the deterministic half of performance testing: it asserts *how*
/// SQLite intends to answer a query, independent of the machine's speed. A
/// query that quietly stops using its index changes this output long before
/// anyone notices a slow screen.
Future<List<String>> queryPlan(
  AppDatabase db,
  String sql, [
  List<Variable> variables = const [],
]) async {
  final rows = await db
      .customSelect('EXPLAIN QUERY PLAN $sql', variables: variables)
      .get();
  return [for (final row in rows) row.read<String>('detail')];
}

/// Explains a statement captured from a DAO, re-binding its arguments.
///
/// `EXPLAIN QUERY PLAN` requires the same parameter count as the original, and
/// the bound *values* never affect index selection — only their presence does.
Future<List<String>> explainCaptured(
  AppDatabase db,
  CapturedStatement captured,
) {
  return queryPlan(db, captured.sql, [
    for (final arg in captured.args) Variable<Object>(arg ?? 0),
  ]);
}

/// One statement as the database actually received it.
class CapturedStatement {
  final String sql;
  final List<Object?> args;

  /// How many times the statement ran: one, except in a batch, where one
  /// prepared statement runs once per argument set.
  final int runs;

  const CapturedStatement(this.sql, this.args, {this.runs = 1});

  bool get isSelect => sql.trimLeft().toUpperCase().startsWith('SELECT');

  @override
  String toString() => sql;
}

/// Counts the statements a block of work issues, so a test can assert an
/// operation is O(1) in queries rather than O(rows).
///
/// Also the source of truth for the query-plan tests: explaining the SQL the
/// DAO really issued means those tests can never assert about a query the app
/// does not run.
class StatementCounter extends QueryInterceptor {
  final List<CapturedStatement> captured = [];

  /// Only the statements recorded since the last [reset], which is how a test
  /// skips the setup writes it does not care about.
  void reset() => captured.clear();

  int get count => captured.length;

  List<String> get statements => [for (final c in captured) c.sql];

  List<CapturedStatement> get selects => [
    for (final c in captured)
      if (c.isSelect) c,
  ];

  /// Statements containing [fragment], for asserting *which* query repeated.
  List<String> matching(String fragment) => [
    for (final c in captured)
      if (c.sql.contains(fragment)) c.sql,
  ];

  /// How many times statements containing [fragment] ran. A batch records
  /// each distinct statement once in [captured], so [matching] cannot see a
  /// statement a batch repeated for every row; this can.
  int executions(String fragment) {
    var runs = 0;
    for (final c in captured) {
      if (c.sql.contains(fragment)) runs += c.runs;
    }
    return runs;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    captured.add(CapturedStatement(statement, args));
    return super.runSelect(executor, statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    captured.add(CapturedStatement(statement, args));
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    captured.add(CapturedStatement(statement, args));
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    captured.add(CapturedStatement(statement, args));
    return super.runDelete(executor, statement, args);
  }

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements_,
  ) {
    final runs = List.filled(statements_.statements.length, 0);
    for (final set in statements_.arguments) {
      runs[set.statementIndex]++;
    }
    for (final (i, s) in statements_.statements.indexed) {
      captured.add(CapturedStatement(s, const [], runs: runs[i]));
    }
    return super.runBatched(executor, statements_);
  }
}
