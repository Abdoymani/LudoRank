import 'package:ludo_rank/core/audio/game_sound.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_token.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/ludo_game_state.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/move_option.dart';

/// Decides which sound effects a game event should play, by comparing the
/// game state before and after it. Pure functions: no audio, easy to test.
class GameSoundEvents {
  const GameSoundEvents._();

  /// Sounds for a dice roll.
  ///
  /// The engine moves straight to the next player when the third six
  /// cancels the turn, so that case is detected from the state change:
  /// the player had two sixes and the turn passed to someone else.
  static List<GameSound> forRoll(LudoGameState before, LudoGameState after) {
    final turnPassed = after.currentPlayerIndex != before.currentPlayerIndex;

    if (turnPassed && before.turnState.sixRollCount >= 2) {
      return const [GameSound.dice, GameSound.cancelled];
    }

    if (!turnPassed && after.turnState.lastRoll == 6) {
      return const [GameSound.dice, GameSound.six];
    }

    return const [GameSound.dice];
  }

  /// The single most important sound for an executed move
  /// (step sounds are played by the board animation itself).
  ///
  /// Priority: match/player finished > capture > token home > token entered.
  static GameSound? forMove(
    LudoGameState before,
    LudoGameState after,
    MoveOption move,
  ) {
    if (after.isFinished ||
        after.finishedPlayerIds.length > before.finishedPlayerIds.length) {
      return GameSound.win;
    }

    final movingTokenId = switch (move) {
      MoveToken(:final tokenId) => tokenId,
      ExitToken(:final tokenId) => tokenId,
    };

    final beforeTokens = {
      for (final player in before.players)
        for (final token in player.tokens) token.id: token,
    };

    var captured = false;
    var reachedHome = false;

    for (final player in after.players) {
      for (final token in player.tokens) {
        final previous = beforeTokens[token.id];
        if (previous == null) continue;

        if (token.id == movingTokenId) {
          if (token.state == LudoTokenState.finished &&
              previous.state != LudoTokenState.finished) {
            reachedHome = true;
          }
        } else if (token.state == LudoTokenState.initial &&
            previous.state != LudoTokenState.initial) {
          captured = true;
        }
      }
    }

    if (captured) return GameSound.capture;
    if (reachedHome) return GameSound.home;
    if (move is ExitToken) return GameSound.enter;
    return null;
  }
}
