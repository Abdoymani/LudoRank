import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';
import 'package:ludo_rank/features/matches/domain/repositories/match_repository.dart';
import 'package:ludo_rank/features/tournaments/domain/entities/tournament.dart';
import 'package:ludo_rank/features/tournaments/domain/repositories/tournament_repository.dart';

/// Allowed tournament status transitions.
///
/// draft / ready  -> running    (first match is created)
/// running        -> finished   (organizer ends the tournament)
/// draft / ready / running -> cancelled
///
/// finished and cancelled are final. unknown (a stored value this app
/// version cannot read) allows nothing.
abstract final class TournamentStatusTransitions {
  static const Map<TournamentStatus, Set<TournamentStatus>> _allowed = {
    TournamentStatus.draft: {
      TournamentStatus.ready,
      TournamentStatus.running,
      TournamentStatus.cancelled,
    },
    TournamentStatus.ready: {
      TournamentStatus.draft,
      TournamentStatus.running,
      TournamentStatus.cancelled,
    },
    TournamentStatus.running: {
      TournamentStatus.finished,
      TournamentStatus.cancelled,
    },
    TournamentStatus.finished: {},
    TournamentStatus.cancelled: {},
    TournamentStatus.unknown: {},
  };

  static bool canTransition(TournamentStatus from, TournamentStatus to) {
    return _allowed[from]!.contains(to);
  }

  /// New matches (and new players) are only allowed while the
  /// tournament is still open.
  static bool isOpen(TournamentStatus status) {
    return status != TournamentStatus.finished &&
        status != TournamentStatus.cancelled &&
        status != TournamentStatus.unknown;
  }
}

/// Why a tournament cannot be finished yet.
enum TournamentFinishBlocker {
  notRunning,
  noFinishedMatches,
  unfinishedMatches,
}

/// Moves a tournament through its statuses based on what happens
/// to its matches.
class TournamentLifecycleService {
  final TournamentRepository tournamentRepository;
  final MatchRepository matchRepository;

  const TournamentLifecycleService({
    required this.tournamentRepository,
    required this.matchRepository,
  });

  Future<Tournament> _load(String tournamentId) async {
    final tournament = await tournamentRepository.getTournamentById(
      tournamentId,
    );

    if (tournament == null) {
      throw StateError('البطولة $tournamentId غير موجودة.');
    }

    return tournament;
  }

  /// Throws when the tournament no longer accepts new matches.
  Future<void> ensureCanCreateMatch(String tournamentId) async {
    final tournament = await _load(tournamentId);

    if (!TournamentStatusTransitions.isOpen(tournament.status)) {
      throw StateError(switch (tournament.status) {
        TournamentStatus.finished =>
          'البطولة منتهية، لا يمكن إضافة مباريات جديدة.',
        TournamentStatus.cancelled =>
          'البطولة ملغاة، لا يمكن إضافة مباريات جديدة.',
        _ => 'حالة البطولة غير معروفة، لا يمكن إضافة مباريات جديدة.',
      });
    }
  }

  /// Called after a match is created: draft/ready -> running.
  Future<Tournament> markRunning(String tournamentId) async {
    final tournament = await _load(tournamentId);

    if (tournament.status == TournamentStatus.running) {
      return tournament;
    }

    return _transition(tournament, TournamentStatus.running);
  }

  /// Returns null when the tournament can be finished now.
  Future<TournamentFinishBlocker?> finishBlocker(String tournamentId) async {
    final tournament = await _load(tournamentId);

    if (tournament.status != TournamentStatus.running) {
      return TournamentFinishBlocker.notRunning;
    }

    final matches = await matchRepository.getTournamentMatches(tournamentId);

    final hasUnfinished = matches.any(
      (match) =>
          match.status == MatchStatus.pending ||
          match.status == MatchStatus.playing,
    );

    if (hasUnfinished) {
      return TournamentFinishBlocker.unfinishedMatches;
    }

    if (!matches.any((match) => match.status == MatchStatus.finished)) {
      return TournamentFinishBlocker.noFinishedMatches;
    }

    return null;
  }

  /// running -> finished.
  ///
  /// Requires at least one finished match and no pending/playing ones.
  Future<Tournament> finish(String tournamentId) async {
    final blocker = await finishBlocker(tournamentId);

    switch (blocker) {
      case null:
        break;
      case TournamentFinishBlocker.notRunning:
        throw StateError('لا يمكن إنهاء بطولة غير جارية.');
      case TournamentFinishBlocker.noFinishedMatches:
        throw StateError(
          'لا يمكن إنهاء البطولة قبل انتهاء مباراة واحدة على الأقل.',
        );
      case TournamentFinishBlocker.unfinishedMatches:
        throw StateError('توجد مباريات لم تنته بعد. أنهِها أو ألغِها أولاً.');
    }

    return _transition(await _load(tournamentId), TournamentStatus.finished);
  }

  Future<Tournament> _transition(
    Tournament tournament,
    TournamentStatus to,
  ) async {
    if (!TournamentStatusTransitions.canTransition(tournament.status, to)) {
      throw StateError(
        'لا يمكن تغيير حالة البطولة من ${tournament.status.name} '
        'إلى ${to.name}.',
      );
    }

    final updated = tournament.copyWith(status: to, updatedAt: DateTime.now());

    await tournamentRepository.updateTournament(updated);

    return updated;
  }
}
