import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_rank/core/database/database.dart' hide Player;
import 'package:ludo_rank/features/players/data/data_sources/local/player_dao.dart';
import 'package:ludo_rank/features/players/data/repositories/player_repository_impl.dart';
import 'package:ludo_rank/features/players/domain/entities/player.dart';
import 'package:ludo_rank/features/players/domain/exceptions/duplicate_player_name_exception.dart';
import 'package:ludo_rank/features/players/domain/services/player_name_normalizer.dart';

final _now = DateTime(2026, 11, 27);

Player _player(String id, String name) {
  return Player(id: id, name: name, createdAt: _now, updatedAt: _now);
}

void main() {
  group('normalizePlayerName', () {
    test('ignores case, hamza, alef maqsura, taa marbuta and spacing', () {
      expect(normalizePlayerName('  Ali   Hassan '), 'ali hassan');
      expect(normalizePlayerName('أحمد'), 'احمد');
      expect(normalizePlayerName('إسلام'), 'اسلام');
      expect(normalizePlayerName('آمال'), 'امال');
      expect(normalizePlayerName('مصطفى'), 'مصطفي');
      expect(normalizePlayerName('فاطمة'), 'فاطمه');
    });

    test('strips tashkeel and tatweel', () {
      expect(normalizePlayerName('مُحَمَّدٌ'), 'محمد');
      expect(normalizePlayerName('محـــمد'), 'محمد');
    });

    test('is idempotent', () {
      for (final name in ['أحمد  (2)', ' Ali ', 'مُحَمَّـد', 'فاطمة']) {
        final once = normalizePlayerName(name);
        expect(normalizePlayerName(once), once);
      }
    });
  });

  group('PlayerRepositoryImpl', () {
    late AppDatabase db;
    late PlayerRepositoryImpl repository;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repository = PlayerRepositoryImpl(db.playerDao);
    });

    tearDown(() => db.close());

    test('stores the normalised name', () async {
      await repository.addPlayer(_player('p1', ' أحمد '));
      final row = await db.playerDao.getPlayerById('p1');
      expect(row!.name, 'أحمد');
      expect(row.normalizedName, 'احمد');
    });

    test('refuses a name that only differs by hamza, case or spaces', () async {
      await repository.addPlayer(_player('p1', 'أحمد'));
      await repository.addPlayer(_player('p2', 'Ali'));

      for (final name in ['احمد', 'إحْمَد ', 'ALI', ' ali']) {
        await expectLater(
          repository.addPlayer(_player('x-$name', name)),
          throwsA(isA<DuplicatePlayerNameException>()),
        );
      }
      expect(await repository.getAllPlayers(), hasLength(2));
    });

    test('rename: refuses another player name, allows its own', () async {
      await repository.addPlayer(_player('p1', 'أحمد'));
      await repository.addPlayer(_player('p2', 'Ali'));

      await expectLater(
        repository.updatePlayer(_player('p2', 'احمد')),
        throwsA(isA<DuplicatePlayerNameException>()),
      );

      await repository.updatePlayer(_player('p1', 'احمد'));
      final row = await db.playerDao.getPlayerById('p1');
      expect(row!.name, 'احمد');
    });

    test('a clash that slips past the check is still reported', () async {
      await repository.addPlayer(_player('p1', 'Ali'));
      // As if another write got in between the check and the insert.
      final racing = PlayerRepositoryImpl(_NoCheckPlayerDao(db));

      await expectLater(
        racing.addPlayer(_player('p2', 'ALI')),
        throwsA(isA<DuplicatePlayerNameException>()),
      );
      await expectLater(
        racing.addPlayer(_player('p1', 'Other')),
        throwsA(isA<SqliteException>()),
      );
    });

    test('the error message is in Arabic', () {
      expect(const DuplicatePlayerNameException().message, contains('الاسم'));
    });
  });
}

class _NoCheckPlayerDao extends PlayerDao {
  _NoCheckPlayerDao(super.db);

  @override
  Future<bool> playerNameExists(String name, {String? exceptId}) async {
    return false;
  }
}
