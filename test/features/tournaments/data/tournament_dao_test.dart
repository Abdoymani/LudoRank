import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_rank/core/database/database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test('getAllTournaments lists the newest tournament first', () async {
    Future<void> add(String id, DateTime createdAt) {
      return database.tournamentDao.insertTournament(
        TournamentsCompanion.insert(
          id: id,
          name: id,
          rounds: 1,
          status: 'draft',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
    }

    await add('middle', DateTime(2026, 6, 1));
    await add('oldest', DateTime(2026, 1, 1));
    await add('newest', DateTime(2026, 11, 1));
    await add('same-time-later-row', DateTime(2026, 11, 1));

    final ids = (await database.tournamentDao.getAllTournaments())
        .map((t) => t.id)
        .toList();

    expect(ids, ['same-time-later-row', 'newest', 'middle', 'oldest']);
  });
}
