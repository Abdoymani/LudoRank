import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_rank/core/dependency_injection/injection_container.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_player.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/available_rolls.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/dice_roll.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/ludo_game_state.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/turn_state.dart';
import 'package:ludo_rank/features/ludo_game/presentation/pages/match_game_page.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/ludo_match_board.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/ludo_match_player_section.dart';

import 'match_screen_harness.dart';

/// Every phone size x system font size: nothing overflows, every target
/// is big enough, no text under 11. Runs in the normal `flutter test`.
void main() {
  const sizes = <Size>[Size(320, 568), Size(360, 640), Size(411, 891)];
  const textScales = <double>[1.0, 1.3, 1.5, 2.0];

  late MatchScreenHarness harness;

  setUp(() => harness = MatchScreenHarness());
  tearDown(() => sl.reset());

  List<LudoPlayer> fourPlayers() => [
    ludoPlayer('a', 1, LudoPlayerColor.green, onLoop: {0: 5}),
    ludoPlayer('b', 2, LudoPlayerColor.yellow),
    ludoPlayer('c', 3, LudoPlayerColor.red, onLoop: {0: 5}),
    ludoPlayer('d', 4, LudoPlayerColor.blue),
  ];

  /// Red ('c', bottom row) has rolled 6 and 3 and has to move.
  LudoGameState redToMove(List<LudoPlayer> players) {
    return LudoGameState.initial(players: players).copyWith(
      isStarted: true,
      currentPlayerIndex: 2,
      turnState: const TurnState(
        playerId: 'c',
        rolls: [
          DiceRoll(value: 6, sequence: 1),
          DiceRoll(value: 3, sequence: 2),
        ],
        availableRolls: AvailableRolls(
          rolls: [
            DiceRoll(value: 6, sequence: 1),
            DiceRoll(value: 3, sequence: 2),
          ],
        ),
        sixRollCount: 1,
        phase: TurnPhase.playing,
      ),
    );
  }

  void expectNoTextBelow11(WidgetTester tester) {
    final texts = find.descendant(
      of: find.byType(MatchGamePage),
      matching: find.byType(Text),
    );
    for (final element in texts.evaluate()) {
      final text = element.widget as Text;
      final style = DefaultTextStyle.of(element).style.merge(text.style);
      expect(
        style.fontSize ?? 14,
        greaterThanOrEqualTo(LudoMatchPlayerSection.minFontSize),
        reason: '"${text.data}" is too small',
      );
    }
  }

  void expectAtLeast(WidgetTester tester, Finder finder, double min) {
    expect(finder, findsWidgets);
    for (final element in finder.evaluate()) {
      final size = (element.renderObject! as RenderBox).size;
      expect(size.width, greaterThanOrEqualTo(min - .01));
      expect(size.height, greaterThanOrEqualTo(min - .01));
    }
  }

  for (final size in sizes) {
    for (final scale in textScales) {
      final label = '${size.width.toInt()}x${size.height.toInt()} @${scale}x';

      testWidgets('$label: rolling, nothing overflows', (tester) async {
        await harness.setUp(players: fourPlayers());
        await harness.pump(tester, size: size, textScale: scale);

        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(harness.rollButton).height,
          greaterThanOrEqualTo(48),
        );
        expectNoTextBelow11(tester);

        final cell = harness.cellSize(tester);
        expect(
          LudoMatchBoard.tokenHitRadius(cell) * 2,
          greaterThanOrEqualTo(48),
        );
        expect(LudoMatchBoard.destinationHitSide(cell), greaterThan(cell));
      });

      testWidgets('$label: choosing a die, nothing overflows', (tester) async {
        final players = fourPlayers();
        await harness.setUp(players: players, state: redToMove(players));
        await harness.pump(tester, size: size, textScale: scale);

        expectAtLeast(
          tester,
          find.byKey(const ValueKey<String>('card-die-1')),
          LudoMatchPlayerSection.chipSize,
        );

        await harness.tapToken(tester, 'c-token-0');
        expect(harness.provider!.selectedTokenId, 'c-token-0');
        for (final sequence in [1, 2]) {
          expectAtLeast(
            tester,
            find.byKey(ValueKey<String>('board-die-$sequence')),
            LudoMatchBoard.boardDieSize,
          );
        }

        expect(tester.takeException(), isNull);
        expectNoTextBelow11(tester);
      });
    }
  }
}
