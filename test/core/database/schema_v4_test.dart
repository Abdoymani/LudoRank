import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_rank/core/database/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

final _now = DateTime(2026, 11, 21);

Future<void> _seed(AppDatabase db) async {
  for (final id in ['t1', 't2']) {
    await db
        .into(db.tournaments)
        .insert(
          TournamentsCompanion.insert(
            id: id,
            name: id,
            rounds: 3,
            status: 'draft',
            createdAt: _now,
            updatedAt: _now,
          ),
        );
  }
  for (final id in ['p1', 'p2']) {
    await db
        .into(db.players)
        .insert(
          PlayersCompanion.insert(
            id: id,
            name: id,
            createdAt: _now,
            updatedAt: _now,
          ),
        );
  }
}

MatchesCompanion _match(String id, String tournamentId) {
  return MatchesCompanion.insert(
    id: id,
    tournamentId: tournamentId,
    matchNumber: 0,
    status: 'pending',
    playersCount: const Value(2),
    createdAt: Value(_now),
    updatedAt: Value(_now),
  );
}

Future<Set<String>> _indexNames(AppDatabase db) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND name NOT LIKE 'sqlite_%'",
      )
      .get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

const _expectedIndexes = {
  'idx_tournament_players_player',
  'ux_tournament_players_tournament_player',
  'idx_matches_tournament',
  'ux_matches_tournament_number',
  'idx_match_players_match',
  'idx_match_players_player',
};

void main() {
  group('fresh database', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await _seed(db);
    });

    tearDown(() => db.close());

    test('creates all declared indexes', () async {
      expect(await _indexNames(db), containsAll(_expectedIndexes));
    });

    test('enables foreign keys', () async {
      final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(row.read<int>('foreign_keys'), 1);
    });

    test('rejects the same player joining a tournament twice', () async {
      await db
          .into(db.tournamentPlayers)
          .insert(
            TournamentPlayersCompanion.insert(
              id: 'a',
              tournamentId: 't1',
              playerId: 'p1',
            ),
          );

      await expectLater(
        db
            .into(db.tournamentPlayers)
            .insert(
              TournamentPlayersCompanion.insert(
                id: 'b',
                tournamentId: 't1',
                playerId: 'p1',
              ),
            ),
        throwsA(isA<SqliteException>()),
      );

      // Same player in another tournament is fine.
      await db
          .into(db.tournamentPlayers)
          .insert(
            TournamentPlayersCompanion.insert(
              id: 'c',
              tournamentId: 't2',
              playerId: 'p1',
            ),
          );
    });

    test('rejects rows that point to missing parents', () async {
      await expectLater(
        db
            .into(db.matchPlayers)
            .insert(
              MatchPlayersCompanion.insert(
                id: 'mp',
                matchId: 'missing',
                playerId: 'ghost',
                seat: 1,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('numbers matches 1, 2, 3 per tournament', () async {
      await db.matchDao.insertMatch(_match('m1', 't1'));
      await db.matchDao.insertMatch(_match('m2', 't1'));
      await db.matchDao.insertMatch(_match('x1', 't2'));
      await db.matchDao.insertMatch(_match('m3', 't1'));

      final t1 = await db.matchDao.getTournamentMatches('t1');
      expect(t1.map((m) => m.id), ['m1', 'm2', 'm3']);
      expect(t1.map((m) => m.matchNumber), [1, 2, 3]);

      final t2 = await db.matchDao.getTournamentMatches('t2');
      expect(t2.single.matchNumber, 1);
    });

    test('deleting a match also deletes its players', () async {
      await db.matchDao.insertMatch(_match('m1', 't1'));
      await db
          .into(db.matchPlayers)
          .insert(
            MatchPlayersCompanion.insert(
              id: 'mp1',
              matchId: 'm1',
              playerId: 'p1',
              seat: 1,
            ),
          );

      await db.matchDao.deleteMatch('m1');

      expect(await db.select(db.matches).get(), isEmpty);
      expect(await db.select(db.matchPlayers).get(), isEmpty);
    });

    test('deleting a tournament removes its matches and players', () async {
      await db
          .into(db.tournamentPlayers)
          .insert(
            TournamentPlayersCompanion.insert(
              id: 'tp1',
              tournamentId: 't1',
              playerId: 'p1',
            ),
          );
      await db.matchDao.insertMatch(_match('m1', 't1'));
      await db.matchDao.insertMatch(_match('x1', 't2'));
      await db
          .into(db.matchPlayers)
          .insert(
            MatchPlayersCompanion.insert(
              id: 'mp1',
              matchId: 'm1',
              playerId: 'p1',
              seat: 1,
            ),
          );

      await db.tournamentDao.deleteTournament('t1');

      expect((await db.select(db.tournaments).get()).map((t) => t.id), ['t2']);
      expect((await db.select(db.matches).get()).map((m) => m.id), ['x1']);
      expect(await db.select(db.tournamentPlayers).get(), isEmpty);
      expect(await db.select(db.matchPlayers).get(), isEmpty);
    });
  });

  group('migration 3 -> 4', () {
    late Directory dir;
    late AppDatabase db;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('ludorank_v3_');
      final path = '${dir.path}/v3.db';
      _createVersion3Database(path);
      db = AppDatabase.forTesting(NativeDatabase(File(path)));
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test(
      'removes duplicate tournament players and adds the unique key',
      () async {
        final rows = await db.select(db.tournamentPlayers).get();
        expect(rows.map((r) => r.id).toList()..sort(), ['tp-a', 'tp-c']);

        await expectLater(
          db
              .into(db.tournamentPlayers)
              .insert(
                TournamentPlayersCompanion.insert(
                  id: 'tp-new',
                  tournamentId: 't1',
                  playerId: 'p1',
                ),
              ),
          throwsA(isA<SqliteException>()),
        );

        final ddl = await db
            .customSelect(
              "SELECT sql FROM sqlite_master WHERE name = 'tournament_players'",
            )
            .getSingle();
        expect(ddl.read<String>('sql'), contains('PRIMARY KEY'));
      },
    );

    test('numbers old matches by creation order per tournament', () async {
      final t1 = await db.matchDao.getTournamentMatches('t1');
      expect(t1.map((m) => m.id), ['m-old', 'm-mid', 'm-new']);
      expect(t1.map((m) => m.matchNumber), [1, 2, 3]);

      final t2 = await db.matchDao.getTournamentMatches('t2');
      expect(t2.single.matchNumber, 1);

      // New matches continue the sequence.
      await db.matchDao.insertMatch(_match('m-next', 't1'));
      final next = await db.matchDao.getMatchById('m-next');
      expect(next!.matchNumber, 4);
    });

    test('creates indexes, enables foreign keys, bumps version', () async {
      expect(await _indexNames(db), containsAll(_expectedIndexes));

      final fk = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(fk.read<int>('foreign_keys'), 1);

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), db.schemaVersion);
    });
  });
}

/// A schema-3 database as the previous app version created it:
/// no indexes, no primary key on tournament_players, match_number = 0.
void _createVersion3Database(String path) {
  final old = sqlite.sqlite3.open(path);
  try {
    old.execute('''
      CREATE TABLE players (
        id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL UNIQUE,
        nickname TEXT, avatar TEXT, notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)
    ''');
    old.execute('''
      CREATE TABLE tournaments (
        id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL,
        rounds INTEGER NOT NULL, status TEXT NOT NULL,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)
    ''');
    old.execute('''
      CREATE TABLE tournament_players (
        id TEXT NOT NULL,
        tournament_id TEXT NOT NULL REFERENCES tournaments (id),
        player_id TEXT NOT NULL REFERENCES players (id),
        joined_at INTEGER NOT NULL)
    ''');
    old.execute('''
      CREATE TABLE matches (
        id TEXT NOT NULL PRIMARY KEY,
        tournament_id TEXT NOT NULL REFERENCES tournaments (id),
        match_number INTEGER NOT NULL, status TEXT NOT NULL,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
        players_count INTEGER NOT NULL DEFAULT 0, game_state_json TEXT)
    ''');
    old.execute('''
      CREATE TABLE match_players (
        id TEXT NOT NULL PRIMARY KEY,
        match_id TEXT NOT NULL REFERENCES matches (id),
        player_id TEXT NOT NULL REFERENCES players (id),
        seat INTEGER NOT NULL, rank INTEGER,
        points INTEGER NOT NULL DEFAULT 0,
        finished INTEGER NOT NULL DEFAULT 0)
    ''');

    old.execute('''
      INSERT INTO tournaments VALUES
        ('t1', 'T1', 3, 'draft', 1760000000, 1760000000),
        ('t2', 'T2', 3, 'draft', 1760000000, 1760000000)
    ''');
    old.execute('''
      INSERT INTO players (id, name, created_at, updated_at) VALUES
        ('p1', 'P1', 1760000000, 1760000000),
        ('p2', 'P2', 1760000000, 1760000000)
    ''');
    // tp-b duplicates (t1, p1); a second 'tp-a' row duplicates the id.
    old.execute('''
      INSERT INTO tournament_players VALUES
        ('tp-a', 't1', 'p1', 1760000000),
        ('tp-b', 't1', 'p1', 1760000001),
        ('tp-a', 't1', 'p2', 1760000002),
        ('tp-c', 't2', 'p1', 1760000003)
    ''');
    old.execute('''
      INSERT INTO matches (id, tournament_id, match_number, status,
                           created_at, updated_at, players_count) VALUES
        ('m-new', 't1', 0, 'pending', 1760000300, 1760000300, 2),
        ('m-old', 't1', 0, 'finished', 1760000100, 1760000100, 2),
        ('m-mid', 't1', 0, 'playing', 1760000200, 1760000200, 2),
        ('x-1', 't2', 0, 'pending', 1760000100, 1760000100, 2)
    ''');
    old.execute('PRAGMA user_version = 3');
  } finally {
    old.close();
  }
}
