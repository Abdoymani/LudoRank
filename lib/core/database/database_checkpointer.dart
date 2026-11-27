import 'package:flutter/foundation.dart';

/// Folds the SQLite write-ahead log back into the main database file.
///
/// Run when the app goes to the background so Android Auto Backup (which
/// copies `ludorank.db` on its own schedule) sees a complete database, not
/// a main file whose latest writes still sit in `ludorank.db-wal`.
///
/// Saves still in flight (a roll or move being written) finish first;
/// each open match registers its own waiter.
class DatabaseCheckpointer {
  final Future<void> Function() _checkpoint;
  final Set<Future<void> Function()> _pendingSaveWaiters = {};

  DatabaseCheckpointer(this._checkpoint);

  void addPendingSaveWaiter(Future<void> Function() waiter) {
    _pendingSaveWaiters.add(waiter);
  }

  void removePendingSaveWaiter(Future<void> Function() waiter) {
    _pendingSaveWaiters.remove(waiter);
  }

  /// Never throws: a failed checkpoint only means SQLite does it later.
  Future<void> checkpoint() async {
    try {
      for (final waiter in List.of(_pendingSaveWaiters)) {
        await waiter();
      }
      await _checkpoint();
    } catch (e) {
      debugPrint('WAL checkpoint skipped: $e');
    }
  }
}
