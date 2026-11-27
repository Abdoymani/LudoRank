import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_rank/core/database/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Schema 6 upgrade from every older version, with the bad data the old
/// schemas allowed: duplicate names, duplicate seats and players in a
/// match, and rows whose parent was deleted.
void main() {
  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ludorank_v6_');
    path = '${dir.path}/old.db';
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<AppDatabase> open() async {
    final db = AppDatabase.forTesting(NativeDatabase(File(path)));
    // Opening runs the migration.
    await db.customSelect('SELECT 1').get();
    return db;
  }

  for (var version = 1; version <= 5; version++) {
    group('$version -> 6', () {
      setUp(() => _createOldDatabase(path, version));

      test('keeps every player and suffixes clashing names', () async {
        final db = await open();
        addTearDown(db.close);

        final rows = await db.select(db.players).get();
        final names = {for (final row in rows) row.id: row.name};
        final normalized = {for (final row in rows) row.id: row.normalizedName};

        expect(names, {
          'p0': 'احمد (2)',
          'p1': 'أحمد',
          'p2': 'إحْمَد (3)',
          'p3': 'Ali',
          'p4': 'ali (2)',
          'p-free': 'Free',
          if (version == 1) 'p5': 'Ali (3)',
        });
        expect(normalized['p1'], 'احمد');
        expect(normalized['p0'], 'احمد (2)');
        expect(normalized['p2'], 'احمد (3)');
        expect(normalized['p4'], 'ali (2)');
        expect(normalized.values.toSet(), hasLength(normalized.length));
      });

      test('removes orphan rows and duplicate match players', () async {
        final db = await open();
        addTearDown(db.close);

        final matches = await db.select(db.matches).get();
        expect(matches.map((m) => m.id).toSet(), {'m1', 'm2'});

        final matchPlayers = await db.select(db.matchPlayers).get();
        expect(
          {for (final row in matchPlayers) row.id: row.matchId},
          {'mp1': 'm1', 'mp2': 'm1', 'mp3': 'm2', 'mp4': 'm2'},
        );

        // The finished result is untouched.
        final mp1 = matchPlayers.firstWhere((row) => row.id == 'mp1');
        expect(mp1.rank, 1);
        expect(mp1.points, 2);
        expect(mp1.playerId, 'p1');

        final byId = {for (final m in matches) m.id: m};
        expect(byId['m1']!.playersCount, 2);
        // m2 lost a duplicate seat, a duplicate player and a ghost.
        expect(byId['m2']!.playersCount, 2);

        final tournamentPlayers = await db.select(db.tournamentPlayers).get();
        expect(tournamentPlayers.map((row) => row.id).toSet(), {
          'tp1',
          'tp2',
          'tp3',
        });

        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        final integrity = await db
            .customSelect('PRAGMA integrity_check')
            .getSingle();
        expect(integrity.data.values.single, 'ok');
      });

      test('clears the snapshot of finished matches only', () async {
        final db = await open();
        addTearDown(db.close);

        final matches = await db.select(db.matches).get();
        final json = {for (final m in matches) m.id: m.gameStateJson};
        expect(json['m1'], isNull);
        expect(json['m2'], version >= 3 ? '{"playing":true}' : isNull);
      });

      test('ends with the same schema as a fresh install', () async {
        final db = await open();
        addTearDown(db.close);

        final version = await db
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.read<int>('user_version'), 6);

        final fresh = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(fresh.close);

        expect(await _schemaOf(db), await _schemaOf(fresh));
      });

      test('the new constraints hold after the upgrade', () async {
        final db = await open();
        addTearDown(db.close);

        Future<void> insertMatchPlayer(String id, String player, int seat) {
          return db
              .into(db.matchPlayers)
              .insert(
                MatchPlayersCompanion.insert(
                  id: id,
                  matchId: 'm2',
                  playerId: player,
                  seat: seat,
                ),
              );
        }

        // Seat 1 is taken; p1 already plays.
        await expectLater(
          insertMatchPlayer('x1', 'p-free', 1),
          throwsA(isA<SqliteException>()),
        );
        await expectLater(
          insertMatchPlayer('x2', 'p1', 3),
          throwsA(isA<SqliteException>()),
        );
        await insertMatchPlayer('x3', 'p-free', 3);

        // A clash by normalised name is refused by the database too.
        await expectLater(
          db.customStatement(
            'INSERT INTO players (id, name, normalized_name, '
            "created_at, updated_at) VALUES ('n', 'free!', 'free', 0, 0)",
          ),
          throwsA(isA<SqliteException>()),
        );
      });

      test('running the upgrade twice changes nothing', () async {
        var db = await open();
        final before = await _dump(db);
        await db.customStatement('PRAGMA user_version = $version');
        await db.close();

        db = await open();
        addTearDown(db.close);
        expect(await _dump(db), before);
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      });
    });
  }
}

Future<Map<String, Object?>> _schemaOf(AppDatabase db) async {
  final result = <String, Object?>{};
  final tables = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .get();
  for (final table in tables.map((row) => row.read<String>('name'))) {
    final columns = await db.customSelect('PRAGMA table_info("$table")').get();
    final keys = await db
        .customSelect('PRAGMA foreign_key_list("$table")')
        .get();
    final indexes = await db.customSelect('PRAGMA index_list("$table")').get();
    final indexColumns = <String>[];
    for (final index in indexes) {
      final name = index.read<String>('name');
      final info = await db.customSelect('PRAGMA index_info("$name")').get();
      final key = name.startsWith('sqlite_autoindex') ? 'auto' : name;
      indexColumns.add(
        '$key unique=${index.read<int>('unique')} '
        '${info.map((row) => row.read<String>('name')).join(',')}',
      );
    }
    result[table] = {
      'columns': [
        for (final column in columns)
          [
            column.read<String>('name'),
            column.read<String>('type'),
            column.read<int>('notnull'),
            column.readNullable<String>('dflt_value'),
            column.read<int>('pk'),
          ],
      ],
      'foreignKeys': [
        for (final key in keys)
          '${key.read<String>('from')} -> '
              '${key.read<String>('table')}.${key.read<String>('to')}',
      ]..sort(),
      'indexes': indexColumns..sort(),
    };
  }
  return result;
}

Future<Map<String, List<Map<String, Object?>>>> _dump(AppDatabase db) async {
  final result = <String, List<Map<String, Object?>>>{};
  for (final table in [
    'players',
    'tournaments',
    'tournament_players',
    'matches',
    'match_players',
  ]) {
    final rows = await db
        .customSelect('SELECT * FROM $table ORDER BY id')
        .get();
    result[table] = rows.map((row) => row.data).toList();
  }
  return result;
}

/// A database as the app version with schema [version] left it, filled
/// with the bad data that schema allowed.
void _createOldDatabase(String path, int version) {
  final db = sqlite.sqlite3.open(path);
  try {
    // Schema 1 had no UNIQUE on the player name.
    db.execute('''
      CREATE TABLE players (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL ${version >= 2 ? 'UNIQUE' : ''},
        nickname TEXT, avatar TEXT, notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)
    ''');
    db.execute('''
      CREATE TABLE tournaments (
        id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL,
        rounds INTEGER NOT NULL, status TEXT NOT NULL,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)
    ''');
    db.execute('''
      CREATE TABLE tournament_players (
        id TEXT NOT NULL ${version >= 4 ? 'PRIMARY KEY' : ''},
        tournament_id TEXT NOT NULL REFERENCES tournaments (id),
        player_id TEXT NOT NULL REFERENCES players (id),
        joined_at INTEGER NOT NULL)
    ''');
    db.execute('''
      CREATE TABLE matches (
        id TEXT NOT NULL PRIMARY KEY,
        tournament_id TEXT NOT NULL REFERENCES tournaments (id),
        match_number INTEGER NOT NULL, status TEXT NOT NULL,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
        ${version >= 2 ? ', players_count INTEGER NOT NULL DEFAULT 0' : ''}
        ${version >= 3 ? ', game_state_json TEXT' : ''})
    ''');
    // Schema 1 had no foreign keys (and no primary key) on match_players.
    db.execute(
      version == 1
          ? '''
      CREATE TABLE match_players (
        id TEXT NOT NULL, match_id TEXT NOT NULL, player_id TEXT NOT NULL,
        seat INTEGER NOT NULL, rank INTEGER,
        points INTEGER NOT NULL DEFAULT 0,
        finished INTEGER NOT NULL DEFAULT 0)
    '''
          : '''
      CREATE TABLE match_players (
        id TEXT NOT NULL PRIMARY KEY,
        match_id TEXT NOT NULL REFERENCES matches (id),
        player_id TEXT NOT NULL REFERENCES players (id),
        seat INTEGER NOT NULL, rank INTEGER,
        points INTEGER NOT NULL DEFAULT 0,
        finished INTEGER NOT NULL DEFAULT 0)
    ''',
    );
    if (version >= 4) {
      db.execute('''
        CREATE INDEX idx_tournament_players_player
          ON tournament_players (player_id);
        CREATE UNIQUE INDEX ux_tournament_players_tournament_player
          ON tournament_players (tournament_id, player_id);
        CREATE INDEX idx_matches_tournament ON matches (tournament_id);
        CREATE UNIQUE INDEX ux_matches_tournament_number
          ON matches (tournament_id, match_number);
        CREATE INDEX idx_match_players_match ON match_players (match_id);
        CREATE INDEX idx_match_players_player ON match_players (player_id);
      ''');
    }

    db.execute('''
      INSERT INTO tournaments VALUES
        ('t1', 'T1', 3, 'running', 1760000000, 1760000000)
    ''');

    // p0 is older than p2 and already holds "احمد (2)", so p2 gets (3).
    db.execute('''
      INSERT INTO players (id, name, created_at, updated_at) VALUES
        ('p0', 'احمد (2)', 50, 50),
        ('p1', 'أحمد', 100, 100),
        ('p2', 'إحْمَد', 200, 200),
        ('p3', 'Ali', 300, 300),
        ('p4', 'ali ', 400, 400),
        ('p-free', 'Free', 600, 600)
    ''');
    if (version == 1) {
      db.execute(
        "INSERT INTO players (id, name, created_at, updated_at) "
        "VALUES ('p5', 'Ali', 500, 500)",
      );
    }

    db.execute('''
      INSERT INTO tournament_players VALUES
        ('tp1', 't1', 'p1', 1),
        ('tp2', 't1', 'p2', 2),
        ('tp3', 't1', 'p3', 3),
        ('tp-ghost-player', 't1', 'ghost', 4),
        ('tp-ghost-tournament', 'gone', 'p1', 5)
    ''');

    final number = version >= 4;
    final extra = [
      if (version >= 2) 'players_count',
      if (version >= 3) 'game_state_json',
    ];
    String values(
      String id,
      String tournament,
      int n,
      String status,
      int count,
      String? json,
    ) {
      return [
        "'$id'",
        "'$tournament'",
        '${number ? n : 0}',
        "'$status'",
        '$n',
        '$n',
        if (version >= 2) '$count',
        if (version >= 3) json == null ? 'NULL' : "'$json'",
      ].join(', ');
    }

    final columns = [
      'id',
      'tournament_id',
      'match_number',
      'status',
      'created_at',
      'updated_at',
      ...extra,
    ].join(', ');
    db.execute('''
      INSERT INTO matches ($columns) VALUES
        (${values('m1', 't1', 1, 'finished', 2, '{"finished":true}')}),
        (${values('m2', 't1', 2, 'playing', 4, '{"playing":true}')}),
        (${values('m-orphan', 'gone', 1, 'pending', 2, null)})
    ''');

    db.execute('''
      INSERT INTO match_players
        (id, match_id, player_id, seat, rank, points, finished) VALUES
        ('mp1', 'm1', 'p1', 1, 1, 2, 1),
        ('mp2', 'm1', 'p3', 2, 2, 1, 1),
        ('mp3', 'm2', 'p1', 1, NULL, 0, 0),
        ('mp4', 'm2', 'p3', 2, NULL, 0, 0),
        ('mp-dup-seat', 'm2', 'p4', 2, NULL, 0, 0),
        ('mp-dup-player', 'm2', 'p1', 3, NULL, 0, 0),
        ('mp-ghost', 'm2', 'ghost', 4, NULL, 0, 0),
        ('mp-orphan-match', 'm-orphan', 'p1', 1, NULL, 0, 0),
        ('mp-no-match', 'nowhere', 'p2', 1, NULL, 0, 0)
    ''');
    if (version == 1) {
      // Schema 1 had no primary key here either.
      db.execute('''
        INSERT INTO match_players
          (id, match_id, player_id, seat, rank, points, finished) VALUES
          ('mp1', 'm1', 'p2', 3, NULL, 0, 0)
      ''');
    }

    db.execute('PRAGMA user_version = $version');
  } finally {
    db.close();
  }
}
