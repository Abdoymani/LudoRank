import 'package:flutter/material.dart';

import 'package:ludo_rank/features/players/domain/services/player_name_normalizer.dart';
import 'package:ludo_rank/features/tournaments/domain/entities/tournament.dart';
import 'package:ludo_rank/features/tournaments/domain/repositories/tournament_repository.dart';

/// Status filter of the tournaments list.
enum TournamentFilter {
  all,
  running,
  draft,
  finished;

  bool matches(TournamentStatus status) {
    return switch (this) {
      TournamentFilter.all => true,
      TournamentFilter.running => status == TournamentStatus.running,
      TournamentFilter.draft =>
        status == TournamentStatus.draft || status == TournamentStatus.ready,
      TournamentFilter.finished => status == TournamentStatus.finished,
    };
  }

  /// Reads a filter from a route query value (`?status=finished`).
  static TournamentFilter fromName(String? name) {
    return TournamentFilter.values.firstWhere(
      (filter) => filter.name == name,
      orElse: () => TournamentFilter.all,
    );
  }
}

class TournamentProvider extends ChangeNotifier {
  final TournamentRepository repository;

  TournamentProvider(this.repository);

  final List<Tournament> _tournaments = [];

  /// Newest first (the DAO's order).
  List<Tournament> get tournaments => List.unmodifiable(_tournaments);

  Map<String, TournamentCounts> _counts = const {};

  TournamentCounts countsFor(String tournamentId) {
    return _counts[tournamentId] ?? TournamentCounts.zero;
  }

  Tournament? _currentTournament;

  Tournament? get currentTournament => _currentTournament;

  bool _isLoading = false;

  bool get isLoading => _isLoading;

  String? _error;

  String? get error => _error;

  /// The tournaments that pass [filter] and whose name contains [query]
  /// (compared the way player names are: case, alef/yaa/taa marbuta
  /// forms and spaces do not matter).
  List<Tournament> filtered(TournamentFilter filter, String query) {
    final needle = normalizePlayerName(query);

    return _tournaments.where((tournament) {
      if (!filter.matches(tournament.status)) return false;
      if (needle.isEmpty) return true;
      return normalizePlayerName(tournament.name).contains(needle);
    }).toList();
  }

  Future<void> loadTournaments() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final result = await repository.getAllTournaments();
      final counts = await repository.getTournamentCounts();

      _tournaments
        ..clear()
        ..addAll(result);
      _counts = counts;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadTournament(String id) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _currentTournament = await repository.getTournamentById(id);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Saves [tournament] and reloads the list. Returns false (and sets
  /// [error]) when it could not be saved.
  Future<bool> addTournament(Tournament tournament) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await repository.addTournament(tournament);
    } catch (e) {
      _error = e.toString();

      _isLoading = false;
      notifyListeners();
      return false;
    }

    await loadTournaments();
    return true;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
