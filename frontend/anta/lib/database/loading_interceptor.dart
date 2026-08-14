import 'package:drift/drift.dart';
import '../services/loading_service.dart';

/// Query interceptor that shows a loading indicator during database operations.
/// Integrates with LoadingService to provide visual feedback.
class LoadingQueryInterceptor extends QueryInterceptor {
  final LoadingService _loadingService = LoadingService();

  /// The "don't flash for quick queries" delay lives on [LoadingService] as
  /// `showDelay`, because it has to be decided where the notifier is flipped.
  /// This class previously declared a `thresholdMs` that nothing read, so
  /// every sub-millisecond statement toggled the indicator.
  LoadingQueryInterceptor();

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    _loadingService.startLoading();
    final executor = super.beginTransaction(parent);
    return _LoadingTransactionExecutor(executor, _loadingService);
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) async {
    try {
      await super.commitTransaction(inner);
    } finally {
      _loadingService.stopLoading();
    }
  }

  @override
  Future<void> rollbackTransaction(TransactionExecutor inner) async {
    try {
      await super.rollbackTransaction(inner);
    } finally {
      _loadingService.stopLoading();
    }
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    return _withLoading(() => super.runInsert(executor, statement, args));
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    return _withLoading(() => super.runUpdate(executor, statement, args));
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    return _withLoading(() => super.runDelete(executor, statement, args));
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    return _withLoading(() => super.runCustom(executor, statement, args));
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    return _withLoading(() => super.runSelect(executor, statement, args));
  }

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) async {
    return _withLoading(() => super.runBatched(executor, statements));
  }

  Future<T> _withLoading<T>(Future<T> Function() operation) async {
    _loadingService.startLoading();
    try {
      return await operation();
    } finally {
      _loadingService.stopLoading();
    }
  }
}

/// Wrapper for transaction executor that tracks loading state
class _LoadingTransactionExecutor implements TransactionExecutor {
  final TransactionExecutor _inner;
  final LoadingService _loadingService;

  _LoadingTransactionExecutor(this._inner, this._loadingService);

  @override
  SqlDialect get dialect => _inner.dialect;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) => _inner.ensureOpen(user);

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) =>
      _inner.runCustom(statement, args);

  @override
  Future<int> runDelete(String statement, List<Object?> args) =>
      _inner.runDelete(statement, args);

  @override
  Future<int> runInsert(String statement, List<Object?> args) =>
      _inner.runInsert(statement, args);

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) => _inner.runSelect(statement, args);

  @override
  Future<int> runUpdate(String statement, List<Object?> args) =>
      _inner.runUpdate(statement, args);

  @override
  Future<void> close() => _inner.close();

  @override
  Future<void> runBatched(BatchedStatements statements) =>
      _inner.runBatched(statements);

  @override
  Future<void> send() async {
    try {
      await _inner.send();
    } finally {
      _loadingService.stopLoading();
    }
  }

  @override
  bool get supportsNestedTransactions => _inner.supportsNestedTransactions;

  @override
  TransactionExecutor beginTransaction() => _inner.beginTransaction();

  @override
  QueryExecutor beginExclusive() => _inner.beginExclusive();

  @override
  Future<void> rollback() => _inner.rollback();
}
