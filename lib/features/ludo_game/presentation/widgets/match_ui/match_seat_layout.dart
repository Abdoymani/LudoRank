import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_player.dart';

/// Where each colour's player card sits around the board on the match
/// screen. The cards follow the physical homes: green and yellow above the
/// board, red and blue below it, so the players sit around one phone.
///
/// Everything that belongs to a player in the top row (the card, a dice
/// chip next to their token, a notice about their roll) is turned 180° so
/// that player reads it from their own side of the table. The turn is
/// decided by the row, never by a colour check of its own.
abstract final class MatchSeatLayout {
  /// Left and right slots of the row above the board.
  static const List<LudoPlayerColor> topRow = <LudoPlayerColor>[
    LudoPlayerColor.green,
    LudoPlayerColor.yellow,
  ];

  /// Left and right slots of the row below the board.
  static const List<LudoPlayerColor> bottomRow = <LudoPlayerColor>[
    LudoPlayerColor.red,
    LudoPlayerColor.blue,
  ];

  /// True when [color]'s card is in the row above the board, so everything
  /// for that player is shown upside down (facing the far side).
  static bool facesFarSide(LudoPlayerColor color) => topRow.contains(color);
}
