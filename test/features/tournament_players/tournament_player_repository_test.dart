import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_rank/core/database/database.dart' as db;
import 'package:ludo_rank/features/tournament_players/data/repositories/tournament_player_repository_impl.dart';
import 'package:ludo_rank/features/tournament_players/domain/entities/tournament_player.dart';
import 'package:ludo_rank/features/tournament_players/presentation/providers/tournament_player_provider.dart';

final _now = DateTime(2026, 11, 27);

void main() {
  late db.AppDatabase database;
  late TournamentPlayerRepositoryImpl repository;

  Future<void> addTournament(String id, String status) {
    return database
        .into(database.tournaments)
        .insert(
          db.TournamentsCompanion.insert(
            id: id,
            name: id,
            rounds: 1,
            status: status,
            createdAt: _now,
            updatedAt: _now,
          ),
        );
  }

  TournamentPlayer member(String tournamentId, String playerId) {
    return TournamentPlayer(
      id: '$tournamentId-$playerId',
      tournamentId: tournamentId,
      playerId: playerId,
      joinedAt: _now,
    );
  }

  setUp(() async {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
    repository = TournamentPlayerRepositoryImpl(database.tournamentPlayerDao);
    for (final id in ['p1', 'p2', 'p3']) {
      await database
          .into(database.players)
          .insert(
            db.PlayersCompanion.insert(
              id: id,
              name: id,
              createdAt: _now,
              updatedAt: _now,
            ),
          );
    }
  });

  tearDown(() => database.close());

  test('a finished tournament refuses new players (audit probe P7)', () async {
    await addTournament('t1', 'finished');

    await expectLater(
      repository.addPlayer(member('t1', 'p1')),
      throwsStateError,
    );
    await expectLater(
      repository.addPlayers([member('t1', 'p1'), member('t1', 'p2')]),
      throwsStateError,
    );
    expect(await repository.getTournamentPlayers('t1'), isEmpty);
  });

  test('draft and running tournaments accept players', () async {
    await addTournament('draft', 'draft');
    await addTournament('running', 'running');

    await repository.addPlayer(member('draft', 'p1'));
    await repository.addPlayers([
      member('running', 'p1'),
      member('running', 'p2'),
    ]);

    expect(await repository.getTournamentPlayers('draft'), hasLength(1));
    expect(await repository.getTournamentPlayers('running'), hasLength(2));
  });

  test('adding several players is all or nothing', () async {
    await addTournament('t1', 'running');
    await repository.addPlayer(member('t1', 'p2'));

    // p2 is already a member, so the unique index fails the second row.
    await expectLater(
      repository.addPlayers([
        member('t1', 'p1'),
        TournamentPlayer(
          id: 'dup',
          tournamentId: 't1',
          playerId: 'p2',
          joinedAt: _now,
        ),
        member('t1', 'p3'),
      ]),
      throwsA(anything),
    );

    final members = await repository.getTournamentPlayers('t1');
    expect(members.map((m) => m.playerId), ['p2']);
  });

  test('provider.addPlayers reports a closed tournament', () async {
    await addTournament('t1', 'finished');
    final provider = TournamentPlayerProvider(repository);

    await provider.addPlayers([member('t1', 'p1')]);

    expect(provider.error, contains('منتهية'));
    expect(provider.players, isEmpty);
  });
}
