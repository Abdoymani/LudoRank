import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';
import 'package:ludo_rank/features/tournaments/domain/entities/tournament.dart';

class DashboardSummary {
  final int playersCount;
  final int tournamentsCount;
  final int matchesCount;
  final int finishedTournamentsCount;

  /// The newest tournament, or null when there is none.
  final LastTournamentSummary? lastTournament;

  /// The most recently updated match that was started and not finished
  /// (left with "pause" or interrupted), or null.
  final MatchOverview? resumableMatch;

  const DashboardSummary({
    required this.playersCount,
    required this.tournamentsCount,
    required this.matchesCount,
    required this.finishedTournamentsCount,
    this.lastTournament,
    this.resumableMatch,
  });
}

class LastTournamentSummary {
  final Tournament tournament;
  final TournamentCounts counts;

  const LastTournamentSummary({required this.tournament, required this.counts});
}

/// A match with the name of its tournament, for lists outside a
/// tournament.
class MatchOverview {
  final String matchId;
  final int matchNumber;
  final String tournamentId;
  final String tournamentName;
  final MatchStatus status;
  final int playersCount;
  final DateTime createdAt;

  const MatchOverview({
    required this.matchId,
    required this.matchNumber,
    required this.tournamentId,
    required this.tournamentName,
    required this.status,
    required this.playersCount,
    required this.createdAt,
  });

  String get title => matchNumber > 0 ? 'مباراة رقم $matchNumber' : 'مباراة';
}
