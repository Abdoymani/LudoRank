import '../entities/tournament.dart';

abstract interface class TournamentRepository {
  Future<List<Tournament>> getAllTournaments();

  Future<Tournament?> getTournamentById(String id);

  /// Player and match counts of every tournament, keyed by its id.
  Future<Map<String, TournamentCounts>> getTournamentCounts();

  Future<void> addTournament(Tournament tournament);

  Future<void> updateTournament(Tournament tournament);

  Future<void> deleteTournament(String id);
}
