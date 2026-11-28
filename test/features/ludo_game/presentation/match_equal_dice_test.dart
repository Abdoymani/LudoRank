import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_rank/core/dependency_injection/injection_container.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_player.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/turn_state.dart';

import 'match_screen_harness.dart';

/// Two dice of the same value are the same move for one token: the player
/// is never asked to choose between 6 and 6.
void main() {
  late MatchScreenHarness harness;

  setUp(() => harness = MatchScreenHarness());
  tearDown(() => sl.reset());

  Future<void> rollSixSixFour(WidgetTester tester) async {
    await harness.roll(tester);
    await harness.roll(tester);
    await harness.roll(tester);
    expect(harness.engine.state.turnState.phase, TurnPhase.playing);
    expect(harness.engine.state.turnState.availableRolls.values, [6, 6, 4]);
  }

  testWidgets('6, 6, 4: tapping a token in its base brings it out at once', (
    tester,
  ) async {
    await harness.setUp(
      players: [
        ludoPlayer('a', 1, LudoPlayerColor.green, onLoop: {1: 10}),
        ludoPlayer('b', 2, LudoPlayerColor.red),
      ],
      dice: [6, 6, 4],
    );
    await harness.pump(tester);
    await rollSixSixFour(tester);

    await harness.tapToken(tester, 'a-token-0');
    await tester.pumpAndSettle();

    expect(harness.token('a-token-0').positionInPath, 0, reason: 'exited');
    expect(harness.provider!.selectedTokenId, isNull);
    expect(harness.engine.state.turnState.availableRolls.values, [6, 4]);
  });

  testWidgets('6, 6, 4: a token on the track offers one 6 and one 4', (
    tester,
  ) async {
    await harness.setUp(
      players: [
        ludoPlayer('a', 1, LudoPlayerColor.green, onLoop: {0: 5}),
        ludoPlayer('b', 2, LudoPlayerColor.red),
      ],
      dice: [6, 6, 4],
    );
    await harness.pump(tester);
    await rollSixSixFour(tester);

    await harness.tapToken(tester, 'a-token-0');
    expect(harness.provider!.selectedTokenId, 'a-token-0');
    expect(harness.provider!.selectableRolls.values, [6, 4]);
    expect(find.byKey(const ValueKey<String>('board-die-1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('board-die-2')), findsNothing);
    expect(find.byKey(const ValueKey<String>('board-die-3')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('board-die-1')));
    await tester.pumpAndSettle();
    expect(harness.token('a-token-0').positionInPath, 11);
    expect(harness.engine.state.turnState.availableRolls.values, [6, 4]);
  });
}
