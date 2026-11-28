import 'dart:ui';

import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_player.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/position.dart';
import 'package:ludo_rank/features/ludo_game/presentation/geometry/ludo_board_geometry.dart';

/// Where every token is drawn on a board of a given size.
///
/// The painter, the tap hit test and the movable-token glow all read the
/// same centres, so what the player sees is exactly what they can tap.
abstract final class LudoTokenLayout {
  /// Token radius as drawn by the board art (outer rim included).
  static double tokenRadius(double cell) => cell * .43 * 1.12;

  /// The cell a token stands on: its base pad while at home.
  static Position cellOf(LudoPlayer player, int tokenIndex) {
    final token = player.tokens[tokenIndex];
    return token.isInitial
        ? LudoBoardGeometry.instance.tokenHomePosition(
            color: player.color,
            tokenIndex: token.tokenIndex,
          )
        : token.position;
  }

  /// Centre of each token by id, in board coordinates of a board whose
  /// side is [boardSide]. Tokens that share a cell are spread a little so
  /// each one stays visible.
  static Map<String, Offset> centers(
    List<LudoPlayer> players,
    double boardSide,
  ) {
    final geometry = LudoBoardGeometry.instance;
    final cell = boardSide / LudoBoardGeometry.gridSize;
    final groups = <Position, List<String>>{};

    for (final player in players) {
      for (var index = 0; index < player.tokens.length; index++) {
        groups
            .putIfAbsent(cellOf(player, index), () => <String>[])
            .add(player.tokens[index].id);
      }
    }

    final result = <String, Offset>{};
    for (final entry in groups.entries) {
      final center = geometry.cellCenter(entry.key, boardSide);
      final ids = entry.value;
      for (var i = 0; i < ids.length; i++) {
        result[ids[i]] = center + stackOffset(i, ids.length, cell);
      }
    }
    return result;
  }

  /// Offset of the [index]th of [count] tokens sharing one cell.
  static Offset stackOffset(int index, int count, double cell) {
    const two = <Offset>[Offset(-.16, -.16), Offset(.16, .16)];
    const three = <Offset>[
      Offset(-.15, -.13),
      Offset(.15, -.13),
      Offset(0, .16),
    ];
    const four = <Offset>[
      Offset(-.16, -.16),
      Offset(.16, -.16),
      Offset(-.16, .16),
      Offset(.16, .16),
    ];

    if (count <= 1) return Offset.zero;
    final offsets = count == 2
        ? two
        : count == 3
        ? three
        : four;
    final safeIndex = index.clamp(0, offsets.length - 1).toInt();
    return offsets[safeIndex] * cell;
  }
}
