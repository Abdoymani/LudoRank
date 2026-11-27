import 'package:flutter/material.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_player.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/available_rolls.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/turn_state.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/match_die_face.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/match_ui_colors.dart';

/// Current player: active card with dice actions. Other players: name only.
///
/// The active card has one action row: the roll button while the player
/// has to roll, the dice to choose from while they have to move. Both
/// never show at once, so the card stays short and the board stays big.
class LudoMatchPlayerSection extends StatelessWidget {
  final LudoPlayer player;
  final bool isCurrent;
  final TurnState? turnState;
  final AvailableRolls availableRolls;
  final bool canRoll;
  final VoidCallback onRoll;
  final double height;
  final ValueChanged<int> onAvailableRollTap;
  final int? selectedRollSequence;

  /// The roll tumbling on this card (its id restarts the tumble), with the
  /// value it stops on and how long it takes.
  final ({int id, int value, Duration duration})? rollingDie;

  const LudoMatchPlayerSection({
    super.key,
    required this.player,
    required this.isCurrent,
    required this.turnState,
    required this.availableRolls,
    required this.canRoll,
    required this.onRoll,
    required this.height,
    required this.onAvailableRollTap,
    required this.selectedRollSequence,
    this.rollingDie,
  });

  /// Smallest font on the match screen.
  static const double minFontSize = 11;

  /// Roll button height (a full touch target).
  static const double actionRowHeight = 48;

  /// Dice chip size on the card.
  static const double chipSize = 40;

  static const double _nameFontSize = 13;
  static const double _activeBorder = 2.1;
  static const double _verticalPadding = 5;
  static const double _rowGap = 4;

  /// Height of one text line of [fontSize] under [scaler]. Generous on
  /// purpose: Arabic fallback fonts on phones are much taller than the
  /// em box.
  static double lineHeight(TextScaler scaler, double fontSize) {
    return scaler.scale(fontSize) * 1.5;
  }

  static double _nameRowHeight(TextScaler scaler) {
    final name = lineHeight(scaler, _nameFontSize);
    final badge = lineHeight(scaler, minFontSize) + 4;
    return name > badge ? name : badge;
  }

  /// Height the active card needs for [scaler].
  static double activeHeightFor(TextScaler scaler) {
    return (_activeBorder * 2 +
            _verticalPadding * 2 +
            _nameRowHeight(scaler) +
            _rowGap +
            actionRowHeight)
        .ceilToDouble();
  }

  /// Height a waiting player's card needs for [scaler].
  static double inactiveHeightFor(TextScaler scaler) {
    final needed = lineHeight(scaler, _nameFontSize) + 12;
    return (needed > 36 ? needed : 36).ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final color = matchUiColorFor(player.color);
    if (!isCurrent) {
      return Container(
        height: height,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF211B2A),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withValues(alpha: .40), width: 1),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x44000000),
              blurRadius: 5,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          player.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: _nameFontSize,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    final scaler = MediaQuery.textScalerOf(context);
    final foreground = player.color == LudoPlayerColor.yellow
        ? const Color(0xFF21182B)
        : Colors.white;
    final isPlaying = turnState?.isPlaying == true;

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: _verticalPadding,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            color.withValues(alpha: .34),
            color.withValues(alpha: .18),
            const Color(0xFF201A29),
          ],
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color, width: _activeBorder),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color.withValues(alpha: .25),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            height: _nameRowHeight(scaler),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    player.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: _nameFontSize,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'دورك',
                    maxLines: 1,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w900,
                      fontSize: minFontSize,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: _rowGap),
          SizedBox(
            height: actionRowHeight,
            child: isPlaying && availableRolls.isNotEmpty
                ? _buildDiceChoices(color)
                : _buildRollRow(color, foreground),
          ),
        ],
      ),
    );
  }

  Widget _buildRollRow(Color color, Color foreground) {
    return Row(
      children: <Widget>[
        AnimatedMatchDieFace(
          value: rollingDie?.value ?? turnState?.lastRoll,
          size: chipSize,
          rollId: rollingDie?.id,
          duration: rollingDie?.duration ?? Duration.zero,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: FilledButton.icon(
            key: const ValueKey<String>('roll-button'),
            onPressed: canRoll ? onRoll : null,
            style: FilledButton.styleFrom(
              backgroundColor: color,
              disabledBackgroundColor: color.withValues(alpha: .35),
              foregroundColor: foreground,
              disabledForegroundColor: foreground.withValues(alpha: .72),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, actionRowHeight),
              maximumSize: const Size(double.infinity, actionRowHeight),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.casino_rounded, size: 18),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                canRoll ? 'رمي النرد' : 'انتظر',
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDiceChoices(Color color) {
    final rolls = availableRolls.rolls;
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: rolls.length + 1,
      separatorBuilder: (_, _) => const SizedBox(width: 4),
      itemBuilder: (context, index) {
        if (index == rolls.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                'اختر حجرًا',
                maxLines: 1,
                style: TextStyle(color: Colors.white70, fontSize: minFontSize),
              ),
            ),
          );
        }

        final roll = rolls[index];
        final isSelected = selectedRollSequence == roll.sequence;

        return Center(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey<String>('card-die-${roll.sequence}'),
              borderRadius: BorderRadius.circular(9),
              onTap: () => onAvailableRollTap(roll.sequence),
              child: Container(
                width: chipSize,
                height: chipSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withValues(alpha: .35)
                      : const Color(0xFF181321),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFFFD166)
                        : color.withValues(alpha: .72),
                    width: isSelected ? 2.4 : 1.2,
                  ),
                ),
                child: MatchDieFace(value: roll.value, size: chipSize * .72),
              ),
            ),
          ),
        );
      },
    );
  }
}
