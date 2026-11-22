import 'package:ludo_rank/core/transactions/transaction_runner.dart';
import 'package:ludo_rank/features/match_players/domain/repositories/match_player_repository.dart';
import 'package:ludo_rank/features/match_players/domain/entities/match_player.dart';
import 'package:ludo_rank/features/tournaments/domain/services/tournament_lifecycle_service.dart';
import '../entities/match.dart';

import '../repositories/match_repository.dart';

class CreateMatch {
  final MatchRepository matchRepository;
  final MatchPlayerRepository matchPlayerRepository;

  /// Optional so the use case can be tested without tournaments.
  /// When given, closed tournaments reject new matches and the first
  /// match moves the tournament to Running.
  final TournamentLifecycleService? tournamentLifecycle;

  /// Saves the match, its players and the tournament status together.
  /// If any step fails (or the app is killed mid-way) nothing is saved,
  /// so there is never a match without players.
  final TransactionRunner transactionRunner;

  CreateMatch({
    required this.matchRepository,
    required this.matchPlayerRepository,
    this.tournamentLifecycle,
    this.transactionRunner = const NoTransactionRunner(),
  });

  Future<void> call({
    required Match match,
    required List<MatchPlayer> players,
  }) async {
    _validateMatch(match);
    _validatePlayers(match, players);

    await transactionRunner.run(() async {
      await tournamentLifecycle?.ensureCanCreateMatch(match.tournamentId);

      await matchRepository.create(match);
      await matchPlayerRepository.addPlayers(players);

      await tournamentLifecycle?.markRunning(match.tournamentId);
    });
  }

  void _validateMatch(Match match) {
    const allowedPlayersCount = {2, 3, 4};

    if (!allowedPlayersCount.contains(match.playersCount)) {
      throw ArgumentError('عدد اللاعبين في المباراة يجب أن يكون 2 أو 3 أو 4.');
    }
  }

  void _validatePlayers(Match match, List<MatchPlayer> players) {
    if (players.length != match.playersCount) {
      throw ArgumentError(
        'عدد اللاعبين المختارين (${players.length}) '
        'لا يطابق عدد لاعبي المباراة (${match.playersCount}).',
      );
    }

    final playerIds = players.map((player) => player.playerId).toSet();

    if (playerIds.length != players.length) {
      throw ArgumentError('لا يمكن تكرار نفس اللاعب داخل المباراة.');
    }

    final matchIds = players.map((player) => player.matchId).toSet();

    if (matchIds.length != 1 || matchIds.first != match.id) {
      throw ArgumentError(
        'جميع لاعبي المباراة يجب أن يكونوا مرتبطين بنفس المباراة.',
      );
    }

    final seats = players.map((player) => player.seat).toSet();

    if (seats.length != players.length) {
      throw ArgumentError('لا يمكن تكرار رقم المقعد داخل المباراة.');
    }

    for (final player in players) {
      if (player.seat < 1 || player.seat > match.playersCount) {
        throw ArgumentError(
          'رقم المقعد ${player.seat} غير صالح لهذه المباراة.',
        );
      }
    }
  }
}
