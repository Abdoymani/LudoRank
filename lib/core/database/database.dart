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
import 'package:ludo_rank/features/players/domain/services/player_name_normalizer.dart';
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
  int get schemaVersion => 6;

  /// Writes every committed change from the WAL file into the main file
  /// and empties the WAL (see DatabaseCheckpointer).
  Future<void> checkpointWal() async {
    await customSelect('PRAGMA wal_checkpoint(TRUNCATE)').get();
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },

    onUpgrade: (Migrator m, int from, int to) async {
      // The whole upgrade is one transaction: a crash mid-way rolls every
      // step back. Drift writes user_version only after this returns, so
      // each step is also idempotent in case the app dies between the
      // commit and that write (the next open runs the same steps again).
      await transaction(() => _upgrade(m, from));
    },

    beforeOpen: (details) async {
      // SQLite leaves foreign keys OFF unless each connection enables them.
      // This runs after migrations, so table rebuilds above are unaffected.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _upgrade(Migrator m, int from) async {
    // Migration 1 -> 2:
    // Add playersCount and populate it from MatchPlayers.
    if (from < 2) {
      await _addColumnIfMissing(m, matches, matches.playersCount);

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
      await _addColumnIfMissing(m, matches, matches.gameStateJson);
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

    // Migration 5 -> 6: constraints the old schemas never had.
    if (from < 6) {
      await _migrateTo6(m);
    }
  }

  /// Indexes added in schema 6. They must not be created by the 3 -> 4
  /// step, because duplicates are only removed by the 5 -> 6 step.
  static const _schema6Indexes = {
    'ux_match_players_match_seat',
    'ux_match_players_match_player',
  };

  Future<void> _migrateTo6(Migrator m) async {
    // 1. Rows whose parent was deleted by old versions (before foreign
    //    keys were enforced). Matches first, so their players follow.
    await _deleteOrphanRows();

    // 2. Duplicate match players: one row per (match, seat), then per
    //    (match, player), then per id. The earliest row is kept.
    await _deleteDuplicateMatchPlayers();

    // 3. Player names that clash once normalised get " (2)", " (3)", ...
    //    Nobody is deleted.
    final normalized = await _renameDuplicatePlayers();

    // 4. Rebuild every table from its current definition, so databases
    //    created by the first versions get the same NOT NULL, UNIQUE and
    //    REFERENCES clauses as a fresh install. Foreign keys are off
    //    during migrations (they are turned on in beforeOpen).
    for (final table in <TableInfo>[
      players,
      tournaments,
      tournamentPlayers,
      matches,
      matchPlayers,
    ]) {
      await _rebuildTable(m, table);
    }

    // 5. Store the normalised names (the rebuild filled a placeholder).
    for (final entry in normalized.entries) {
      await customUpdate(
        'UPDATE players SET normalized_name = ?1 '
        'WHERE id = ?2 AND normalized_name IS NOT ?1',
        variables: [Variable<String>(entry.value), Variable<String>(entry.key)],
        updates: {players},
      );
    }

    // 6. A finished match is read from match_players; its board snapshot
    //    is no longer needed (completeMatch clears it for new matches).
    await customStatement(
      "UPDATE matches SET game_state_json = NULL "
      "WHERE status = 'finished' AND game_state_json IS NOT NULL",
    );

    // 7. Every declared index, including the new unique ones.
    await _createDeclaredIndexes(m);
  }

  Future<void> _deleteOrphanRows() async {
    await customStatement('''
      DELETE FROM matches
      WHERE tournament_id NOT IN (SELECT id FROM tournaments)
    ''');
    final orphanPlayers = await customSelect('''
      SELECT DISTINCT match_id FROM match_players
      WHERE player_id NOT IN (SELECT id FROM players)
        AND match_id IN (SELECT id FROM matches)
    ''').get();
    await customStatement('''
      DELETE FROM match_players
      WHERE match_id NOT IN (SELECT id FROM matches)
         OR player_id NOT IN (SELECT id FROM players)
    ''');
    await customStatement('''
      DELETE FROM tournament_players
      WHERE tournament_id NOT IN (SELECT id FROM tournaments)
         OR player_id NOT IN (SELECT id FROM players)
    ''');
    await _recountMatchPlayers(
      orphanPlayers.map((row) => row.read<String>('match_id')),
    );
  }

  Future<void> _deleteDuplicateMatchPlayers() async {
    final affected = await customSelect('''
      SELECT DISTINCT match_id FROM match_players
      WHERE rowid NOT IN (
        SELECT MIN(rowid) FROM match_players GROUP BY match_id, seat
      )
      OR rowid NOT IN (
        SELECT MIN(rowid) FROM match_players GROUP BY match_id, player_id
      )
      OR rowid NOT IN (SELECT MIN(rowid) FROM match_players GROUP BY id)
    ''').get();
    if (affected.isEmpty) return;

    for (final columns in ['match_id, seat', 'match_id, player_id', 'id']) {
      await customStatement('''
        DELETE FROM match_players
        WHERE rowid NOT IN (
          SELECT MIN(rowid) FROM match_players GROUP BY $columns
        )
      ''');
    }
    await _recountMatchPlayers(
      affected.map((row) => row.read<String>('match_id')),
    );
  }

  /// players_count of a match whose player rows were removed.
  Future<void> _recountMatchPlayers(Iterable<String> matchIds) async {
    for (final matchId in matchIds.toSet()) {
      await customUpdate(
        'UPDATE matches SET players_count = ('
        'SELECT COUNT(*) FROM match_players WHERE match_id = ?) '
        'WHERE id = ?',
        variables: [Variable<String>(matchId), Variable<String>(matchId)],
        updates: {matches},
      );
    }
  }

  /// Renames players whose normalised name is already taken, oldest
  /// player first, and returns the normalised name of every player by id.
  ///
  /// A player keeps their name when nobody older has the same normalised
  /// name, so names that were already unique never change.
  Future<Map<String, String>> _renameDuplicatePlayers() async {
    final rows = await customSelect(
      'SELECT id, name FROM players ORDER BY created_at, rowid',
    ).get();

    final taken = <String>{};
    final renames = <String, String>{};
    final normalizedById = <String, String>{};

    for (final row in rows) {
      final normalized = normalizePlayerName(row.read<String>('name'));
      if (taken.add(normalized)) {
        normalizedById[row.read<String>('id')] = normalized;
      }
    }

    for (final row in rows) {
      final id = row.read<String>('id');
      if (normalizedById.containsKey(id)) continue;

      final name = row.read<String>('name').trim();
      for (var suffix = 2; ; suffix++) {
        final candidate = '$name ($suffix)';
        final normalized = normalizePlayerName(candidate);
        if (taken.add(normalized)) {
          renames[id] = candidate;
          normalizedById[id] = normalized;
          break;
        }
      }
    }

    for (final entry in renames.entries) {
      await customUpdate(
        'UPDATE players SET name = ? WHERE id = ?',
        variables: [Variable<String>(entry.value), Variable<String>(entry.key)],
        updates: {players},
      );
    }

    return normalizedById;
  }

  /// Recreates [table] from its current Drift definition and copies its
  /// rows. Columns the old table lacks are left to their defaults, except
  /// players.normalized_name, which gets the (already unique) name until
  /// step 5 of the 5 -> 6 upgrade stores the real value.
  Future<void> _rebuildTable(Migrator m, TableInfo table) async {
    final missing = <GeneratedColumn>{};
    for (final column in table.$columns) {
      if (!await _hasColumn(table.actualTableName, column.name)) {
        missing.add(column);
      }
    }

    await m.alterTable(
      TableMigration(
        table,
        newColumns: missing.toList(),
        columnTransformer: {
          if (table == players && missing.contains(players.normalizedName))
            players.normalizedName: players.name,
        },
      ),
    );
  }

  Future<void> _createDeclaredIndexes(
    Migrator m, {
    Set<String> skip = const {},
  }) async {
    // Drop first in case an old hand-made index with the same name exists.
    for (final index in allSchemaEntities.whereType<Index>()) {
      if (skip.contains(index.entityName)) continue;
      await customStatement('DROP INDEX IF EXISTS "${index.entityName}"');
      await m.createIndex(index);
    }
  }

  Future<bool> _hasColumn(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info("$table")').get();
    return rows.any((row) => row.read<String>('name') == column);
  }

  /// addColumn that does nothing when the column already exists.
  Future<void> _addColumnIfMissing(
    Migrator m,
    TableInfo table,
    GeneratedColumn column,
  ) async {
    if (await _hasColumn(table.actualTableName, column.name)) return;
    await m.addColumn(table, column);
  }

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

    // 4. Create the declared indexes of schema 4.
    await _createDeclaredIndexes(m, skip: _schema6Indexes);
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();

    debugPrint('Database Path = ${dir.path}');

    final file = File(p.join(dir.path, 'ludorank.db'));

    debugPrint(file.path);

    // SQLite runs on its own isolate so saving the board after every roll
    // and move never blocks animation frames. WAL + synchronous=NORMAL keeps
    // each save to one sequential write instead of a full journal fsync.
    return NativeDatabase.createInBackground(
      file,
      setup: (database) {
        database.execute('PRAGMA journal_mode = WAL');
        database.execute('PRAGMA synchronous = NORMAL');
      },
    );
  });
}
