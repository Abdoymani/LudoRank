import 'package:flutter/foundation.dart';

import 'package:ludo_rank/features/tournament_players/domain/entities/tournament_player.dart';
import 'package:ludo_rank/features/tournaments/domain/services/tournament_standings_service.dart';

class TournamentStandingsProvider extends ChangeNotifier {
  final TournamentStandingsService service;

  TournamentStandingsProvider(this.service);

  TournamentStandingsSnapshot? _snapshot;
  TournamentStandingsSnapshot? get snapshot => _snapshot;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  Future<void> load({
    required String tournamentId,
    required List<TournamentPlayer> participants,
    Map<String, String> playerNames = const {},
  }) async {
    _isLoading = true;
    _error = null;
    _snapshot = null;
    notifyListeners();

    try {
      _snapshot = await service.load(
        tournamentId: tournamentId,
        participants: participants,
        playerNames: playerNames,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
