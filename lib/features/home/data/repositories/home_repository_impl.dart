import 'package:ludo_rank/core/database/database.dart' as db;
import 'package:ludo_rank/features/home/data/data_sources/local/home_dao.dart';
import 'package:ludo_rank/features/home/data/models/dashboard_summary_model.dart';
import 'package:ludo_rank/features/home/domain/entities/dashboard_summary.dart';
import 'package:ludo_rank/features/home/domain/repositories/home_repository.dart';
import 'package:ludo_rank/features/matches/data/models/match_model.dart';
import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';
import 'package:ludo_rank/features/tournaments/data/models/tournament_model.dart';
import 'package:ludo_rank/features/tournaments/domain/entities/tournament.dart';

class HomeRepositoryImpl implements HomeRepository {
  final HomeDao dao;

  HomeRepositoryImpl(this.dao);

  @override
  Future<DashboardSummary> getDashboardSummary() async {
    final playersCount = await dao.getPlayersCount();

    final tournamentsCount = await dao.getTournamentsCount();

    final matchesCount = await dao.getMatchesCount();

    final finishedCount = await dao.getFinishedTournamentsCount();

    return DashboardSummaryModel(
      playersCount: playersCount,
      tournamentsCount: tournamentsCount,
      matchesCount: matchesCount,
      finishedTournamentsCount: finishedCount,
      lastTournament: await _lastTournament(),
      resumableMatch: await _resumableMatch(),
    );
  }

  Future<LastTournamentSummary?> _lastTournament() async {
    final row = await dao.getLastTournament();
    if (row == null) return null;

    final counts = await dao.getTournamentCounts(row.id);

    return LastTournamentSummary(
      tournament: TournamentModel.fromDrift(row),
      counts: TournamentCounts(
        players: counts.players,
        matches: counts.matches,
      ),
    );
  }

  Future<MatchOverview?> _resumableMatch() async {
    final rows = await dao.getMatchesWithTournament(
      status: MatchStatus.playing.name,
      limit: 1,
    );
    return rows.isEmpty ? null : _overview(rows.single);
  }

  @override
  Future<List<MatchOverview>> getAllMatches() async {
    final rows = await dao.getMatchesWithTournament();
    final overviews = rows.map(_overview).toList();

    int group(MatchStatus status) => switch (status) {
      MatchStatus.playing => 0,
      MatchStatus.pending => 1,
      _ => 2,
    };

    // Stable: keeps the DAO's newest-first order inside each group.
    final indexed = overviews.indexed.toList()
      ..sort((a, b) {
        final byGroup = group(a.$2.status).compareTo(group(b.$2.status));
        return byGroup != 0 ? byGroup : a.$1.compareTo(b.$1);
      });

    return [for (final entry in indexed) entry.$2];
  }

  @override
  Future<Map<String, String>> getMatchPlayerNames(String matchId) {
    return dao.getMatchPlayerNames(matchId);
  }

  MatchOverview _overview((db.MatchData, db.Tournament) row) {
    final (match, tournament) = row;

    return MatchOverview(
      matchId: match.id,
      matchNumber: match.matchNumber,
      tournamentId: tournament.id,
      tournamentName: tournament.name,
      status: MatchModel.parseStatus(match.status),
      playersCount: match.playersCount,
      createdAt: match.createdAt,
    );
  }
}
