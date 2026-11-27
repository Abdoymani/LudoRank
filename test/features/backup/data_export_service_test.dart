import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_rank/core/database/database.dart';
import 'package:ludo_rank/features/backup/data/data_export_service.dart';

final _now = DateTime.utc(2026, 11, 27, 10, 30, 5);

Future<void> _seed(AppDatabase db) async {
  for (final (id, name) in [('p1', 'أحمد'), ('p2', 'Ali'), ('p3', 'منى')]) {
    await db
        .into(db.players)
        .insert(
          PlayersCompanion.insert(
            id: id,
            name: name,
            normalizedName: name.toLowerCase().replaceAll('أ', 'ا'),
            createdAt: _now,
            updatedAt: _now,
          ),
        );
  }
  await db
      .into(db.tournaments)
      .insert(
        TournamentsCompanion.insert(
          id: 't1',
          name: 'بطولة',
          rounds: 3,
          status: 'running',
          createdAt: _now,
          updatedAt: _now,
        ),
      );
  for (final player in ['p1', 'p2', 'p3']) {
    await db
        .into(db.tournamentPlayers)
        .insert(
          TournamentPlayersCompanion.insert(
            id: 'tp-$player',
            tournamentId: 't1',
            playerId: player,
            joinedAt: Value(_now),
          ),
        );
  }
  await db.matchDao.insertMatch(
    MatchesCompanion.insert(
      id: 'm1',
      tournamentId: 't1',
      matchNumber: 0,
      status: 'finished',
      playersCount: const Value(2),
      createdAt: Value(_now),
      updatedAt: Value(_now),
    ),
  );
  await db.matchDao.insertMatch(
    MatchesCompanion.insert(
      id: 'm2',
      tournamentId: 't1',
      matchNumber: 0,
      status: 'playing',
      playersCount: const Value(2),
      gameStateJson: const Value('{"board":"saved"}'),
      createdAt: Value(_now),
      updatedAt: Value(_now),
    ),
  );
  for (final (id, match, player, seat, rank, points) in [
    ('mp1', 'm1', 'p1', 1, 1, 2),
    ('mp2', 'm1', 'p2', 2, 2, 1),
    ('mp3', 'm2', 'p2', 1, null, 0),
    ('mp4', 'm2', 'p3', 2, null, 0),
  ]) {
    await db
        .into(db.matchPlayers)
        .insert(
          MatchPlayersCompanion.insert(
            id: id,
            matchId: match,
            playerId: player,
            seat: seat,
            rank: Value(rank),
            points: Value(points),
            finished: Value(rank != null),
          ),
        );
  }
}

Future<Map<String, List<Map<String, Object?>>>> _dump(AppDatabase db) async {
  return {
    for (final table in [
      'players',
      'tournaments',
      'tournament_players',
      'matches',
      'match_players',
    ])
      table: (await db.customSelect('SELECT * FROM $table ORDER BY id').get())
          .map((row) => row.data)
          .toList(),
  };
}

void main() {
  late Directory dir;
  late AppDatabase db;
  late List<String> events;
  late Completer<void> pendingSave;
  late DataExportService service;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ludorank_export_');
    db = AppDatabase.forTesting(
      NativeDatabase(
        File('${dir.path}/ludorank.db'),
        setup: (raw) => raw.execute('PRAGMA journal_mode = WAL'),
      ),
    );
    await _seed(db);

    events = [];
    pendingSave = Completer<void>()..complete();
    service = DataExportService(
      database: db,
      waitForPendingSaves: () async {
        await pendingSave.future;
        events.add('saves done');
      },
      outputDirectory: () async => Directory('${dir.path}/cache'),
      now: () => _now,
    );
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('waits for pending saves before copying', () async {
    pendingSave = Completer<void>();
    final done = service.export();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(events, isEmpty);
    expect(Directory('${dir.path}/cache/export').existsSync(), isFalse);

    pendingSave.complete();
    final export = await done;
    expect(events, ['saves done']);
    expect(export.databaseFile.existsSync(), isTrue);
    expect(export.jsonFile.existsSync(), isTrue);
  });

  test('the JSON holds every row, consistent with each other', () async {
    final export = await service.export();
    expect(export.jsonFile.path, endsWith('ludorank-20261127-103005.json'));

    final json =
        jsonDecode(await export.jsonFile.readAsString())
            as Map<String, dynamic>;

    expect(json['format'], 'ludorank-export');
    expect(json['schemaVersion'], db.schemaVersion);
    expect(json['exportedAt'], '2026-11-27T10:30:05.000Z');

    List<Map<String, dynamic>> list(String key) =>
        (json[key] as List).cast<Map<String, dynamic>>();

    final players = list('players');
    final tournaments = list('tournaments');
    final tournamentPlayers = list('tournamentPlayers');
    final matches = list('matches');
    final matchPlayers = list('matchPlayers');

    expect(json['counts'], {
      'players': 3,
      'tournaments': 1,
      'tournamentPlayers': 3,
      'matches': 2,
      'matchPlayers': 4,
    });
    expect(players.map((p) => p['id']), ['p1', 'p2', 'p3']);
    expect(players.first['name'], 'أحمد');
    expect(players.first['normalizedName'], 'احمد');
    expect(players.first['createdAt'], '2026-11-27T10:30:05.000Z');
    expect(tournaments.single['name'], 'بطولة');
    expect(matches.map((m) => m['matchNumber']), [1, 2]);
    expect(matches.last['gameStateJson'], '{"board":"saved"}');
    expect(
      matchPlayers.firstWhere((m) => m['id'] == 'mp1'),
      containsPair('points', 2),
    );

    // Every reference points to a row of the same export.
    final playerIds = players.map((p) => p['id']).toSet();
    final tournamentIds = tournaments.map((t) => t['id']).toSet();
    final matchIds = matches.map((m) => m['id']).toSet();
    for (final row in tournamentPlayers) {
      expect(tournamentIds, contains(row['tournamentId']));
      expect(playerIds, contains(row['playerId']));
    }
    for (final row in matches) {
      expect(tournamentIds, contains(row['tournamentId']));
    }
    for (final row in matchPlayers) {
      expect(matchIds, contains(row['matchId']));
      expect(playerIds, contains(row['playerId']));
    }

    // Every column of every table is there.
    for (final (key, table) in <(String, TableInfo)>[
      ('players', db.players),
      ('tournaments', db.tournaments),
      ('tournamentPlayers', db.tournamentPlayers),
      ('matches', db.matches),
      ('matchPlayers', db.matchPlayers),
    ]) {
      expect(list(key).first.keys, hasLength(table.$columns.length));
    }
  });

  test('the .db copy opens with the same data and no WAL', () async {
    final export = await service.export();
    expect(File('${export.databaseFile.path}-wal').existsSync(), isFalse);

    final copy = AppDatabase.forTesting(NativeDatabase(export.databaseFile));
    addTearDown(copy.close);

    final version = await copy.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), db.schemaVersion);
    expect(await _dump(copy), await _dump(db));
    expect(await copy.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });

  test('a new export replaces the previous files', () async {
    final first = await service.export();
    var later = _now;
    service = DataExportService(
      database: db,
      waitForPendingSaves: () async {},
      outputDirectory: () async => Directory('${dir.path}/cache'),
      now: () => later = later.add(const Duration(minutes: 1)),
    );
    final second = await service.export();

    expect(first.databaseFile.existsSync(), isFalse);
    expect(second.files.every((file) => file.existsSync()), isTrue);
    expect(Directory('${dir.path}/cache/export').listSync(), hasLength(2));
  });
}
