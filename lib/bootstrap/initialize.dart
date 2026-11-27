import 'package:flutter/widgets.dart';

import 'package:ludo_rank/core/database/database_checkpointer.dart';
import 'package:ludo_rank/core/dependency_injection/injection_container.dart';

// Kept for the whole app lifetime.
AppLifecycleListener? _lifecycleListener;

Future<void> initialize() async {
  // Initialize application dependencies (settings, database, services).
  await initDependencies();

  // Going to the background: fold the WAL into the database file so an
  // Android Auto Backup taken now is consistent.
  _lifecycleListener ??= AppLifecycleListener(
    onPause: () => sl<DatabaseCheckpointer>().checkpoint(),
  );
}
