import '../constants/ludo_paths.dart';
import '../constants/safe_cells.dart';
import '../entities/ludo_player.dart';
import '../entities/ludo_token.dart';
import '../models/ludo_game_state.dart';

/// Recomputes the fields of a saved state that follow from token positions,
/// so a restored match never stops on a value it can derive itself.
///
/// Run on load, before validation. Real engine states come back unchanged;
/// only snapshots written by older versions (or edited by hand) change:
/// - a token on the board is `safe` on a safe cell or in its home lane,
///   otherwise `normal` (this also replaces the old `safeInPair`);
/// - `homeEntryPending` only stays on a main-loop token of a player who
///   has captured (the only case where the engine sets it);
/// - token ids follow `playerId-token-index`.
///
/// Contradictions that cannot be derived (two colours on one plain cell,
/// a third own token on a block, ...) are left for the validator to reject.
abstract final class LudoGameStateNormalizer {
  static LudoGameState normalize(LudoGameState state) {
    var changed = false;

    final players = state.players
        .map((player) {
          final normalized = _normalizePlayer(player);
          if (!identical(normalized, player)) changed = true;
          return normalized;
        })
        .toList(growable: false);

    return changed ? state.copyWith(players: players) : state;
  }

  static LudoPlayer _normalizePlayer(LudoPlayer player) {
    final path = LudoPaths.forColor(player.color);
    var changed = false;

    final tokens = player.tokens
        .map((token) {
          final normalized = _normalizeToken(player, path, token);
          if (normalized != token) changed = true;
          return normalized;
        })
        .toList(growable: false);

    return changed ? player.copyWith(tokens: tokens) : player;
  }

  static LudoToken _normalizeToken(
    LudoPlayer player,
    LudoPath path,
    LudoToken token,
  ) {
    final id = '${player.playerId}-token-${token.tokenIndex}';

    if (token.isInitial || token.isFinished) {
      return token.copyWith(id: id, homeEntryPending: false);
    }

    final inHomeLane = _isHomeLane(path, token);
    final state = inHomeLane || SafeCells.contains(token.position)
        ? LudoTokenState.safe
        : LudoTokenState.normal;

    return token.copyWith(
      id: id,
      state: state,
      homeEntryPending:
          token.homeEntryPending && !inHomeLane && player.hasCaptured,
    );
  }

  static bool _isHomeLane(LudoPath path, LudoToken token) {
    final step = token.positionInPath;
    return step >= LudoPath.homeLaneStartStep &&
        step < LudoPath.finishStep &&
        token.position == path.positionAt(step: step, useHomeLane: true);
  }
}
