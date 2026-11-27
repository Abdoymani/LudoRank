import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_rank/core/database/database.dart';

final _now = DateTime(2026, 11, 1);

void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ludorank_v4_');
    file = File('${dir.path}/v4.db');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  /// Builds a real schema-4 database: create it with the current schema,
  /// fill it, then mark it as version 4 so the next open migrates 4 -> 5.
  Future<void> createVersion4Database() async {
    final db = AppDatabase.forTesting(NativeDatabase(file));

    Future<void> tournament(String id, String status) {
      return db
          .into(db.tournaments)
          .insert(
            TournamentsCompanion.insert(
              id: id,
              name: id,
              rounds: 3,
              status: status,
              createdAt: _now,
              updatedAt: _now,
            ),
          );
    }

    Future<void> match(String id, String tournamentId, String status) {
      return db.matchDao.insertMatch(
        MatchesCompanion.insert(
          id: id,
          tournamentId: tournamentId,
          matchNumber: 0,
          status: status,
        ),
      );
    }

    await tournament('draft-with-matches', 'draft');
    await tournament('ready-with-match', 'ready');
    await tournament('draft-empty', 'draft');
    await tournament('finished', 'finished');
    await tournament('cancelled', 'cancelled');

    await match('m1', 'draft-with-matches', 'finished');
    await match('m2', 'draft-with-matches', 'pending');
    await match('m3', 'ready-with-match', 'cancelled');
    await match('m4', 'finished', 'finished');
    await match('m5', 'cancelled', 'cancelled');

    await db.customStatement('PRAGMA user_version = 4');
    await db.close();
  }

  test('4 -> 5: started draft/ready tournaments become running', () async {
    await createVersion4Database();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    final rows = await db.select(db.tournaments).get();
    final status = {for (final row in rows) row.id: row.status};

    expect(status, {
      'draft-with-matches': 'running',
      'ready-with-match': 'running',
      'draft-empty': 'draft',
      'finished': 'finished',
      'cancelled': 'cancelled',
    });

    // Nothing else is lost.
    expect(await db.select(db.matches).get(), hasLength(5));

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), db.schemaVersion);
  });
}
