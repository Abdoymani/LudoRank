import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';

import 'package:ludo_rank/core/database/tables/match_players_table.dart';
import 'package:ludo_rank/core/database/tables/matches_table.dart';
import 'package:ludo_rank/core/database/tables/players_table.dart';
import 'package:ludo_rank/core/database/tables/tournament_players_table.dart';
import 'package:ludo_rank/core/database/tables/tournaments_table.dart';

import 'package:ludo_rank/features/match_players/data/data_sources/local/match_player_dao.dart';
import 'package:ludo_rank/features/matches/data/data_sources/local/match_dao.dart';
import 'package:ludo_rank/features/players/data/data_sources/local/player_dao.dart';
import 'package:ludo_rank/features/tournament_players/data/data_sources/local/tournament_player_dao.dart';
import 'package:ludo_rank/features/tournaments/data/data_sources/local/tournament_dao.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [Players, Tournaments, TournamentPlayers, Matches, MatchPlayers],
  daos: [
    PlayerDao,
    TournamentDao,
    TournamentPlayerDao,
    MatchDao,
    MatchPlayerDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Constructor used by database migration tests.
  AppDatabase.forTesting(super.executor);
  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },

    onUpgrade: (Migrator m, int from, int to) async {
      // Migration 1 -> 2:
      // Add playersCount and populate it from MatchPlayers.
      if (from < 2) {
        await m.addColumn(matches, matches.playersCount);

        await customStatement('''
          UPDATE matches
          SET players_count = (
            SELECT COUNT(*)
            FROM match_players
            WHERE match_players.match_id = matches.id
          )
        ''');
      }

      // Migration 2 -> 3:
      // Add nullable JSON snapshot for the Ludo game state.
      if (from < 3) {
        await m.addColumn(matches, matches.gameStateJson);
      }

      // Migration 3 -> 4:
      // - tournament_players gets a primary key and a unique
      //   (tournament_id, player_id) index, so the same player cannot
      //   join the same tournament twice.
      // - matches get a real match_number (1, 2, 3, ... per tournament).
      // - The indexes that were declared before but never created.
      if (from < 4) {
        await _migrateTo4(m);
      }

      // Migration 4 -> 5:
      // Tournaments created before the status lifecycle existed stayed
      // draft/ready even after their matches were played, so they could
      // never be finished. Any tournament that already has a match is
      // running (the same rule as creating the first match today).
      if (from < 5) {
        await _markStartedTournamentsRunning();
      }
    },

    beforeOpen: (details) async {
      // SQLite leaves foreign keys OFF unless each connection enables them.
      // This runs after migrations, so table rebuilds above are unaffected.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _markStartedTournamentsRunning() async {
    await customStatement('''
      UPDATE tournaments
      SET status = 'running'
      WHERE status IN ('draft', 'ready')
        AND EXISTS (
          SELECT 1 FROM matches WHERE matches.tournament_id = tournaments.id
        )
    ''');
  }

  Future<void> _migrateTo4(Migrator m) async {
    // 1. Remove duplicated rows that the old schema allowed.
    //    Keep the earliest row for each (tournament, player) pair,
    //    then the earliest row for each id.
    await customStatement('''
      DELETE FROM tournament_players
      WHERE rowid NOT IN (
        SELECT MIN(rowid) FROM tournament_players
        GROUP BY tournament_id, player_id
      )
    ''');
    await customStatement('''
      DELETE FROM tournament_players
      WHERE rowid NOT IN (
        SELECT MIN(rowid) FROM tournament_players GROUP BY id
      )
    ''');

    // 2. Rebuild the table so it gets PRIMARY KEY (id).
    await m.alterTable(TableMigration(tournamentPlayers));

    // 3. Number existing matches per tournament by creation order.
    await customStatement('''
      UPDATE matches
      SET match_number = (
        SELECT COUNT(*) FROM matches AS other
        WHERE other.tournament_id = matches.tournament_id
          AND (other.created_at < matches.created_at
               OR (other.created_at = matches.created_at
                   AND other.rowid <= matches.rowid))
      )
    ''');

    // 4. Create every declared index. Drop first in case an old
    //    hand-made index with the same name exists.
    for (final index in allSchemaEntities.whereType<Index>()) {
      await customStatement('DROP INDEX IF EXISTS "${index.entityName}"');
      await m.createIndex(index);
    }
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();

    debugPrint('Database Path = ${dir.path}');

    final file = File(p.join(dir.path, 'ludorank.db'));

    debugPrint(file.path);

    return NativeDatabase(file);
  });
}
