import 'package:flutter/material.dart';

import 'package:ludo_rank/features/tournament_players/domain/entities/tournament_player.dart';
import 'package:ludo_rank/features/tournament_players/domain/repositories/tournament_player_repository.dart';

class TournamentPlayerProvider extends ChangeNotifier {
  final TournamentPlayerRepository repository;

  TournamentPlayerProvider(this.repository);

  final List<TournamentPlayer> _players = [];

  bool _isLoading = false;

  String? _error;

  List<TournamentPlayer> get players => _players;

  bool get isLoading => _isLoading;

  String? get error => _error;

  Future<void> loadPlayers(String tournamentId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _players
        ..clear()
        ..addAll(await repository.getTournamentPlayers(tournamentId));
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addPlayer(TournamentPlayer player) async {
    final alreadyExists = _players.any(
      (existingPlayer) => existingPlayer.playerId == player.playerId,
    );

    if (alreadyExists) {
      _error = 'اللاعب موجود بالفعل في هذه البطولة';
      notifyListeners();
      return;
    }

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await repository.addPlayer(player);

      await loadPlayers(player.tournamentId);
    } catch (e) {
      _error = _isDuplicateError(e)
          ? 'اللاعب موجود بالفعل في هذه البطولة'
          : e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Adds several players at once: all of them are saved or none.
  Future<void> addPlayers(List<TournamentPlayer> players) async {
    final existing = _players.map((player) => player.playerId).toSet();
    final newPlayers = players
        .where((player) => !existing.contains(player.playerId))
        .toList(growable: false);

    if (newPlayers.isEmpty) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await repository.addPlayers(newPlayers);

      await loadPlayers(newPlayers.first.tournamentId);
    } catch (e) {
      _error = _isDuplicateError(e)
          ? 'اللاعب موجود بالفعل في هذه البطولة'
          : e is StateError
          ? e.message
          : e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> removePlayer(TournamentPlayer player) async {
    await repository.removePlayer(player.id);

    await loadPlayers(player.tournamentId);
  }

  /// قاعدة البيانات ترفض تكرار (البطولة، اللاعب) بفهرس فريد.
  static bool _isDuplicateError(Object error) {
    final message = error.toString();
    return message.contains('UNIQUE constraint failed') &&
        message.contains('tournament_players');
  }
}
