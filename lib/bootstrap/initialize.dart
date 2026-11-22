import 'package:ludo_rank/core/dependency_injection/injection_container.dart';

Future<void> initialize() async {
  // Initialize application dependencies (settings, database, services).
  await initDependencies();
}
