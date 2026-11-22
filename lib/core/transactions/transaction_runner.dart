import 'package:ludo_rank/core/database/database.dart';

/// Runs several repository calls as one unit: either all of them are
/// saved, or none of them.
///
/// The domain layer depends on this interface only, so use cases do not
/// need to know about Drift.
abstract interface class TransactionRunner {
  Future<T> run<T>(Future<T> Function() action);
}

/// Runs the action without a transaction (for unit tests with fakes).
class NoTransactionRunner implements TransactionRunner {
  const NoTransactionRunner();

  @override
  Future<T> run<T>(Future<T> Function() action) => action();
}

/// Drift implementation. Every DAO call made inside [action] (from any
/// repository that uses the same [AppDatabase]) joins this transaction,
/// and nested `transaction()` calls become savepoints.
class DriftTransactionRunner implements TransactionRunner {
  final AppDatabase database;

  const DriftTransactionRunner(this.database);

  @override
  Future<T> run<T>(Future<T> Function() action) {
    return database.transaction(action);
  }
}
