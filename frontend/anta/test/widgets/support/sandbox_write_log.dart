import 'package:drift/drift.dart'
    show BatchedStatements, QueryExecutor, QueryInterceptor;

/// Records every write statement the calendar's services send, so a guide
/// suite can say its page saved nothing whatever path it took.
class SandboxWriteLog extends QueryInterceptor {
  final List<String> statements = [];

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements.add(statement);
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements.add(statement);
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements.add(statement);
    return super.runDelete(executor, statement, args);
  }

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) {
    this.statements.addAll(statements.statements);
    return super.runBatched(executor, statements);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements.add(statement);
    return super.runCustom(executor, statement, args);
  }
}
