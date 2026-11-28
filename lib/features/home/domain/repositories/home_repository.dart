import '../entities/dashboard_summary.dart';

abstract interface class HomeRepository {
  Future<DashboardSummary> getDashboardSummary();

  /// Every match of every tournament: started-but-unfinished ones first,
  /// then not-started ones, then the rest; most recently updated first
  /// within each.
  Future<List<MatchOverview>> getAllMatches();

  /// Names of a match's players keyed by player id (one query), as the
  /// game page needs them.
  Future<Map<String, String>> getMatchPlayerNames(String matchId);
}
