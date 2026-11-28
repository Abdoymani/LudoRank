import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ludo_rank/app/app_provider.dart';
import 'package:ludo_rank/app/app_router.dart';
import 'package:ludo_rank/app/app_routes.dart';
import 'package:ludo_rank/core/database/database.dart' show AppDatabase;
import 'package:ludo_rank/core/dependency_injection/injection_container.dart';
import 'package:ludo_rank/features/match_players/domain/entities/match_player.dart';
import 'package:ludo_rank/features/match_players/domain/repositories/match_player_repository.dart';
import 'package:ludo_rank/features/matches/domain/entities/match.dart';
import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';
import 'package:ludo_rank/features/matches/domain/repositories/match_repository.dart';
import 'package:ludo_rank/features/players/domain/entities/player.dart';
import 'package:ludo_rank/features/players/domain/repositories/player_repository.dart';
import 'package:ludo_rank/features/tournament_players/domain/entities/tournament_player.dart';
import 'package:ludo_rank/features/tournament_players/domain/repositories/tournament_player_repository.dart';
import 'package:ludo_rank/features/tournaments/domain/entities/tournament.dart';
import 'package:ludo_rank/features/tournaments/domain/repositories/tournament_repository.dart';

/// The real app (DI, providers, routes) on an in-memory database, for
/// widget tests of whole screens.
class TestApp {
  late AppDatabase database;

  var _ids = 0;

  String _nextId(String prefix) => '$prefix${++_ids}';

  Future<void> setUp() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await sl.reset();
    SharedPreferences.setMockInitialValues({'sound_enabled': false});
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await initDependencies(database: database, preloadSounds: false);
  }

  Future<void> tearDown() async {
    await database.close();
    await sl.reset();
  }

  /// Pumps the app at [location] with a phone-sized screen.
  Future<void> pump(WidgetTester tester, {String location = AppRoutes.home}) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final router = createAppRouter(initialLocation: location);
    addTearDown(router.dispose);

    return tester.pumpWidget(
      MultiProvider(
        providers: AppProviders.providers,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  /// Pumps a single [page] with the app's providers (for pages that are
  /// not routes, or need constructor arguments).
  Future<void> pumpPage(WidgetTester tester, Widget page) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    return tester.pumpWidget(
      MultiProvider(
        providers: AppProviders.providers,
        child: MaterialApp(home: page),
      ),
    );
  }

  Future<String> addPlayer(String name) async {
    final id = _nextId('p');
    final now = DateTime(2026, 1, 1);
    await sl<PlayerRepository>().addPlayer(
      Player(id: id, name: name, createdAt: now, updatedAt: now),
    );
    return id;
  }

  Future<String> addTournament(
    String name, {
    TournamentStatus status = TournamentStatus.draft,
    required DateTime createdAt,
    List<String> playerIds = const [],
  }) async {
    final id = _nextId('t');
    await sl<TournamentRepository>().addTournament(
      Tournament(
        id: id,
        name: name,
        // Players can only join an open tournament; the real status is
        // set afterwards.
        status: TournamentStatus.draft,
        rounds: 1,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    if (playerIds.isNotEmpty) {
      await sl<TournamentPlayerRepository>().addPlayers([
        for (final playerId in playerIds)
          TournamentPlayer(
            id: _nextId('tp'),
            tournamentId: id,
            playerId: playerId,
            joinedAt: createdAt,
          ),
      ]);
    }
    await setRawTournamentStatus(id, status.name);
    return id;
  }

  /// Stores a match directly (no lifecycle rules), numbered in order.
  Future<String> addMatch(
    String tournamentId, {
    required List<String> playerIds,
    MatchStatus status = MatchStatus.pending,
    DateTime? updatedAt,
  }) async {
    final id = _nextId('m');
    final time = updatedAt ?? DateTime(2026, 1, 2);
    await sl<MatchRepository>().create(
      Match(
        id: id,
        tournamentId: tournamentId,
        playersCount: playerIds.length,
        status: status,
        createdAt: time,
        updatedAt: time,
      ),
    );
    await sl<MatchPlayerRepository>().addPlayers([
      for (var i = 0; i < playerIds.length; i++)
        MatchPlayer(
          id: _nextId('mp'),
          matchId: id,
          playerId: playerIds[i],
          seat: i + 1,
          rank: status == MatchStatus.finished ? i + 1 : null,
          points: status == MatchStatus.finished ? playerIds.length - i : 0,
          finished: status == MatchStatus.finished,
        ),
    ]);
    return id;
  }

  /// Stores a raw status string the app does not know.
  Future<void> setRawTournamentStatus(String id, String status) {
    return database.customStatement(
      'UPDATE tournaments SET status = ? WHERE id = ?',
      [status, id],
    );
  }
}
