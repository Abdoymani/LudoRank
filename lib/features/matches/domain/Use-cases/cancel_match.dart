import '../entities/match.dart';
import '../entities/match_status.dart';
import '../repositories/match_game_state_repository.dart';
import '../repositories/match_repository.dart';

/// Cancels a match that has not finished yet.
///
/// - Only pending or playing matches can be cancelled.
/// - The saved board snapshot is removed.
/// - Cancelled matches do not count in standings (only finished ones do).
class CancelMatch {
  final MatchRepository matchRepository;
  final MatchGameStateRepository gameStateRepository;

  const CancelMatch({
    required this.matchRepository,
    required this.gameStateRepository,
  });

  static bool canCancel(MatchStatus status) {
    return status == MatchStatus.pending || status == MatchStatus.playing;
  }

  Future<Match> call(String matchId) async {
    final match = await matchRepository.getById(matchId);

    if (match == null) {
      throw StateError('المباراة $matchId غير موجودة.');
    }

    if (!canCancel(match.status)) {
      throw StateError(
        match.status == MatchStatus.finished
            ? 'لا يمكن إلغاء مباراة منتهية.'
            : 'المباراة ملغاة بالفعل.',
      );
    }

    final cancelled = match.copyWith(
      status: MatchStatus.cancelled,
      updatedAt: DateTime.now(),
    );

    await matchRepository.update(cancelled);
    await gameStateRepository.clearGameState(matchId);

    return cancelled;
  }
}
