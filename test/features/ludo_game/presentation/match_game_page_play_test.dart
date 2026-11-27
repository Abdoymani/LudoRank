import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_rank/core/dependency_injection/injection_container.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_player.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/turn_state.dart';

import 'match_screen_harness.dart';

/// How the match screen plays today: what a tap does, and that every move
/// the board animates ends up in the engine and in the saved snapshot.
void main() {
  late MatchScreenHarness harness;

  setUp(() => harness = MatchScreenHarness());
  tearDown(() => sl.reset());

  Future<void> rollSixThenThree(WidgetTester tester) async {
    await harness.roll(tester);
    await harness.roll(tester);
    expect(harness.engine.state.turnState.phase, TurnPhase.playing);
    expect(harness.engine.state.turnState.availableRolls.values, [6, 3]);
  }

  testWidgets('a token with one move plays it, then the rest of the turn '
      'plays itself', (tester) async {
    await harness.setUp(
      players: [
        ludoPlayer('a', 1, LudoPlayerColor.green),
        ludoPlayer('b', 2, LudoPlayerColor.red),
      ],
      dice: [6, 3],
    );
    await harness.pump(tester);
    await rollSixThenThree(tester);

    await harness.tapToken(tester, 'a-token-0');
    await tester.pumpAndSettle();

    // Exit with the 6, then the 3 was the only move left and played alone.
    expect(harness.token('a-token-0').positionInPath, 3);
    expect(harness.engine.state.currentPlayer.playerId, 'b');
    expect(harness.engine.state.turnState.phase, TurnPhase.rolling);

    final saved = harness.gameStates.snapshots['match-1']!;
    expect(
      saved.players.first.tokens.first.positionInPath,
      3,
      reason: 'the animated move is recorded and saved',
    );
  });

  testWidgets('a selected token with two moves plays the die chosen on the '
      'board', (tester) async {
    await harness.setUp(
      players: [
        ludoPlayer('a', 1, LudoPlayerColor.green, onLoop: {0: 5}),
        ludoPlayer('b', 2, LudoPlayerColor.red),
      ],
      dice: [6, 3],
    );
    await harness.pump(tester);
    await rollSixThenThree(tester);

    await harness.tapToken(tester, 'a-token-0');
    expect(harness.provider!.selectedTokenId, 'a-token-0');
    expect(harness.token('a-token-0').positionInPath, 5);

    await tester.tap(find.byKey(const ValueKey<String>('board-die-2')));
    await tester.pumpAndSettle();

    expect(harness.token('a-token-0').positionInPath, 8);
    // The 6 is left and has several moves: nothing plays by itself.
    expect(harness.engine.state.currentPlayer.playerId, 'a');
    expect(harness.engine.state.turnState.availableRolls.values, [6]);
    expect(harness.provider!.selectedTokenId, isNull);
  });

  testWidgets('a selected token moves when its destination is tapped', (
    tester,
  ) async {
    await harness.setUp(
      players: [
        ludoPlayer('a', 1, LudoPlayerColor.green, onLoop: {0: 5}),
        ludoPlayer('b', 2, LudoPlayerColor.red),
      ],
      dice: [6, 3],
    );
    await harness.pump(tester);
    await rollSixThenThree(tester);

    await harness.tapToken(tester, 'a-token-0');
    final destination = pathFor(
      LudoPlayerColor.green,
    ).positionAt(step: 11, useHomeLane: false);
    await tester.tapAt(harness.cellCenter(tester, destination));
    await tester.pumpAndSettle();

    // The 6 was played on the destination; the 3 was then the only move.
    expect(harness.token('a-token-0').positionInPath, 14);
    expect(harness.engine.state.currentPlayer.playerId, 'b');
  });

  testWidgets('a die chosen on the card first, then the token, plays that '
      'die', (tester) async {
    await harness.setUp(
      players: [
        ludoPlayer('a', 1, LudoPlayerColor.green, onLoop: {0: 5}),
        ludoPlayer('b', 2, LudoPlayerColor.red),
      ],
      dice: [6, 3],
    );
    await harness.pump(tester);
    await rollSixThenThree(tester);

    await tester.tap(find.byKey(const ValueKey<String>('card-die-2')));
    await tester.pump();
    expect(harness.provider!.selectedRollSequence, 2);

    await harness.tapToken(tester, 'a-token-0');
    await tester.pumpAndSettle();

    expect(harness.token('a-token-0').positionInPath, 8);
  });
}
