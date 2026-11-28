import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_rank/features/matches/domain/entities/match.dart';
import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';
import 'package:ludo_rank/features/match_players/domain/entities/match_player.dart';
import 'package:ludo_rank/features/tournaments/domain/services/tournament_standings_calculator.dart';

void main() {
  const calculator = TournamentStandingsCalculator();

  final now = DateTime(2026, 1, 1);

  Match makeMatch(String id, MatchStatus status) {
    return Match(
      id: id,
      tournamentId: 'tournament-1',
      playersCount: 2,
      status: status,
      createdAt: now,
      updatedAt: now,
    );
  }

  MatchPlayer makeResult({
    required String id,
    required String matchId,
    required String playerId,
    required int points,
    int? rank,
  }) {
    return MatchPlayer(
      id: id,
      matchId: matchId,
      playerId: playerId,
      seat: 1,
      points: points,
      rank: rank,
      finished: true,
    );
  }

  group('TournamentStandingsCalculator', () {
    test('keeps participants who have not played with zero points', () {
      final standings = calculator.calculate(
        participantIds: ['p1', 'p2', 'p3'],
        matches: [makeMatch('m1', MatchStatus.finished)],
        matchPlayers: [
          makeResult(
            id: 'r1',
            matchId: 'm1',
            playerId: 'p1',
            points: 2,
            rank: 1,
          ),
          makeResult(
            id: 'r2',
            matchId: 'm1',
            playerId: 'p2',
            points: 1,
            rank: 2,
          ),
        ],
      );

      expect(standings.map((s) => s.playerId).toList(), ['p1', 'p2', 'p3']);
      expect(standings[2].points, 0);
      expect(standings[2].matchesPlayed, 0);
      expect(standings[2].wins, 0);
      expect(standings[2].bestRank, isNull);
    });

    test('ignores results from unfinished matches', () {
      final standings = calculator.calculate(
        participantIds: ['p1', 'p2'],
        matches: [
          makeMatch('m1', MatchStatus.finished),
          makeMatch('m2', MatchStatus.playing),
        ],
        matchPlayers: [
          makeResult(
            id: 'r1',
            matchId: 'm1',
            playerId: 'p1',
            points: 2,
            rank: 1,
          ),
          makeResult(
            id: 'r2',
            matchId: 'm2',
            playerId: 'p1',
            points: 100,
            rank: 2,
          ),
        ],
      );

      expect(standings.firstWhere((s) => s.playerId == 'p1').points, 2);
      expect(standings.firstWhere((s) => s.playerId == 'p1').matchesPlayed, 1);
    });

    test('calculates wins, matches played, and best rank', () {
      final standings = calculator.calculate(
        participantIds: ['p1', 'p2'],
        matches: [
          makeMatch('m1', MatchStatus.finished),
          makeMatch('m2', MatchStatus.finished),
        ],
        matchPlayers: [
          makeResult(
            id: 'r1',
            matchId: 'm1',
            playerId: 'p1',
            points: 2,
            rank: 1,
          ),
          makeResult(
            id: 'r2',
            matchId: 'm1',
            playerId: 'p2',
            points: 1,
            rank: 2,
          ),
          makeResult(
            id: 'r3',
            matchId: 'm2',
            playerId: 'p1',
            points: 1,
            rank: 2,
          ),
          makeResult(
            id: 'r4',
            matchId: 'm2',
            playerId: 'p2',
            points: 2,
            rank: 1,
          ),
        ],
      );

      final p1 = standings.firstWhere((s) => s.playerId == 'p1');
      final p2 = standings.firstWhere((s) => s.playerId == 'p2');

      expect(p1.points, 3);
      expect(p1.matchesPlayed, 2);
      expect(p1.wins, 1);
      expect(p1.bestRank, 1);

      expect(p2.points, 3);
      expect(p2.matchesPlayed, 2);
      expect(p2.wins, 1);
      expect(p2.bestRank, 1);

      expect(p1.position, 1);
      expect(p2.position, 1);
    });

    test('uses competition ranking for tied points', () {
      final standings = calculator.calculate(
        participantIds: ['p1', 'p2', 'p3'],
        matches: [makeMatch('m1', MatchStatus.finished)],
        matchPlayers: [
          makeResult(
            id: 'r1',
            matchId: 'm1',
            playerId: 'p1',
            points: 3,
            rank: 1,
          ),
          makeResult(
            id: 'r2',
            matchId: 'm1',
            playerId: 'p2',
            points: 3,
            rank: 2,
          ),
          makeResult(
            id: 'r3',
            matchId: 'm1',
            playerId: 'p3',
            points: 1,
            rank: 3,
          ),
        ],
      );

      final positions = {
        for (final standing in standings) standing.playerId: standing.position,
      };

      expect(positions['p1'], 1);
      expect(positions['p2'], 1);
      expect(positions['p3'], 3);
    });

    test('orders tied points by wins, then best rank, then name, while '
        'they keep the same position', () {
      // Every player ends on 4 points.
      final standings = calculator.calculate(
        participantIds: ['id-z', 'id-y', 'id-x', 'id-w', 'id-v'],
        playerNames: const {
          'id-z': 'Zeina',
          'id-y': 'yasser',
          'id-x': 'Adel',
          'id-w': 'Bassem',
          'id-v': 'Camilia',
        },
        matches: [
          for (var i = 1; i <= 6; i++) makeMatch('m$i', MatchStatus.finished),
        ],
        matchPlayers: [
          // Zeina: one win (4 = 4 points, rank 1).
          makeResult(
            id: 'a',
            matchId: 'm1',
            playerId: 'id-z',
            points: 4,
            rank: 1,
          ),
          // yasser: two wins (2 + 2).
          makeResult(
            id: 'b',
            matchId: 'm2',
            playerId: 'id-y',
            points: 2,
            rank: 1,
          ),
          makeResult(
            id: 'c',
            matchId: 'm3',
            playerId: 'id-y',
            points: 2,
            rank: 1,
          ),
          // Adel, Bassem: no win, best rank 2.
          makeResult(
            id: 'd',
            matchId: 'm4',
            playerId: 'id-x',
            points: 4,
            rank: 2,
          ),
          makeResult(
            id: 'e',
            matchId: 'm5',
            playerId: 'id-w',
            points: 4,
            rank: 2,
          ),
          // Camilia: no win, best rank 3.
          makeResult(
            id: 'f',
            matchId: 'm6',
            playerId: 'id-v',
            points: 4,
            rank: 3,
          ),
        ],
      );

      expect(standings.map((s) => s.playerId), [
        'id-y', // 2 wins
        'id-z', // 1 win
        'id-x', // best rank 2, "Adel"
        'id-w', // best rank 2, "Bassem"
        'id-v', // best rank 3
      ]);
      expect(standings.every((s) => s.position == 1), isTrue);
    });

    test('a player without any rank comes after ranked players on equal '
        'points', () {
      final standings = calculator.calculate(
        participantIds: ['a', 'b'],
        playerNames: const {'a': 'Aaa', 'b': 'Bbb'},
        matches: [makeMatch('m1', MatchStatus.finished)],
        matchPlayers: [
          makeResult(id: 'r', matchId: 'm1', playerId: 'b', points: 0, rank: 2),
        ],
      );
      expect(standings.map((s) => s.playerId), ['b', 'a']);
    });

    test('does not count duplicate player entries twice', () {
      final standings = calculator.calculate(
        participantIds: ['p1'],
        matches: [makeMatch('m1', MatchStatus.finished)],
        matchPlayers: [
          makeResult(
            id: 'r1',
            matchId: 'm1',
            playerId: 'p1',
            points: 2,
            rank: 1,
          ),
          makeResult(
            id: 'r1-duplicate',
            matchId: 'm1',
            playerId: 'p1',
            points: 2,
            rank: 1,
          ),
        ],
      );

      expect(standings.single.points, 2);
      expect(standings.single.matchesPlayed, 1);
      expect(standings.single.wins, 1);
    });

    test('returns no standings when there are no participants', () {
      final standings = calculator.calculate(
        participantIds: [],
        matches: [],
        matchPlayers: [],
      );

      expect(standings, isEmpty);
    });
  });
}
