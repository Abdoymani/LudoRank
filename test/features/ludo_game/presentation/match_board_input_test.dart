import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_rank/core/dependency_injection/injection_container.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_player.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/ludo_match_board.dart';

import 'match_screen_harness.dart';

/// The board is one hit test: dice chip > destination > nearest movable
/// token, with targets far bigger than the 20–29dp tokens.
void main() {
  late MatchScreenHarness harness;

  setUp(() => harness = MatchScreenHarness());
  tearDown(() => sl.reset());

  const smallPhone = Size(320, 568);

  Future<void> rollSixThenThree(WidgetTester tester) async {
    await harness.roll(tester);
    await harness.roll(tester);
  }

  testWidgets('a tap 20dp away from a small token still selects it', (
    tester,
  ) async {
    await harness.setUp(
      players: [
        ludoPlayer('a', 1, LudoPlayerColor.green, onLoop: {0: 5}),
        ludoPlayer('b', 2, LudoPlayerColor.red),
      ],
      dice: [6, 3],
    );
    await harness.pump(tester, size: smallPhone);
    await rollSixThenThree(tester);

    final cell = harness.cellSize(tester);
    expect(cell, lessThan(22), reason: 'cells are tiny on this phone');
    expect(LudoMatchBoard.tokenHitRadius(cell) * 2, greaterThanOrEqualTo(48));

    await harness.tapToken(tester, 'a-token-0', offset: const Offset(0, 20));
    expect(harness.provider!.selectedTokenId, 'a-token-0');
  });

  testWidgets('between two movable tokens the nearer one wins', (tester) async {
    await harness.setUp(
      players: [
        ludoPlayer('a', 1, LudoPlayerColor.green, onLoop: {0: 5, 1: 6}),
        ludoPlayer('b', 2, LudoPlayerColor.red),
      ],
      dice: [6, 3],
    );
    await harness.pump(tester, size: smallPhone);
    await rollSixThenThree(tester);

    final at5 = harness.tokenCenter(tester, harness.token('a-token-0'));
    final at6 = harness.tokenCenter(tester, harness.token('a-token-1'));

    await tester.tapAt(Offset.lerp(at5, at6, .6)!);
    await tester.pump();
    expect(harness.provider!.selectedTokenId, 'a-token-1');

    await tester.tapAt(Offset.lerp(at5, at6, .4)!);
    await tester.pump();
    expect(harness.provider!.selectedTokenId, 'a-token-0');
  });

  testWidgets('an opponent token under the finger does not hide a movable '
      'one next to it', (tester) async {
    final next = pathFor(
      LudoPlayerColor.green,
    ).positionAt(step: 6, useHomeLane: false);
    final redStep = pathFor(LudoPlayerColor.red).mainLoopPath.indexOf(next);
    await harness.setUp(
      players: [
        ludoPlayer('a', 1, LudoPlayerColor.green, onLoop: {0: 5}),
        // A red token one square ahead of green's token.
        ludoPlayer('b', 2, LudoPlayerColor.red, onLoop: {0: redStep}),
      ],
      dice: [6, 3],
    );
    await harness.pump(tester, size: smallPhone);
    await rollSixThenThree(tester);
    expect(harness.token('b-token-0').position, next);

    await tester.tapAt(harness.cellCenter(tester, next));
    await tester.pump();
    expect(harness.provider!.selectedTokenId, 'a-token-0');
  });

  testWidgets('with a token selected, its destination beats the token next '
      'to it and accepts a tap off the cell centre', (tester) async {
    await harness.setUp(
      players: [
        ludoPlayer('a', 1, LudoPlayerColor.green, onLoop: {0: 5, 1: 9}),
        ludoPlayer('b', 2, LudoPlayerColor.red),
      ],
      dice: [6, 3],
    );
    await harness.pump(tester, size: smallPhone);
    await rollSixThenThree(tester);

    await harness.tapToken(tester, 'a-token-0');
    expect(harness.provider!.selectedTokenId, 'a-token-0');

    // 5 + 3 = 8: right next to the other movable token on 9.
    final destination = pathFor(
      LudoPlayerColor.green,
    ).positionAt(step: 8, useHomeLane: false);
    final cell = harness.cellSize(tester);
    await tester.tapAt(
      harness.cellCenter(tester, destination) + Offset(cell * .6, 0),
    );
    await tester.pumpAndSettle();

    expect(harness.token('a-token-0').positionInPath, 8);
    expect(harness.token('a-token-1').positionInPath, 9);
  });

  testWidgets('dice chips on the board are at least 40dp and win over the '
      'tokens under them', (tester) async {
    await harness.setUp(
      players: [
        ludoPlayer('a', 1, LudoPlayerColor.red, onLoop: {0: 5}),
        ludoPlayer('b', 2, LudoPlayerColor.green),
      ],
      dice: [6, 3],
    );
    await harness.pump(tester, size: smallPhone);
    await rollSixThenThree(tester);
    await harness.tapToken(tester, 'a-token-0');

    for (final sequence in [1, 2]) {
      final chip = find.byKey(ValueKey<String>('board-die-$sequence'));
      final size = tester.getSize(chip);
      expect(size.width, greaterThanOrEqualTo(40));
      expect(size.height, greaterThanOrEqualTo(40));
    }

    await tester.tap(find.byKey(const ValueKey<String>('board-die-2')));
    await tester.pumpAndSettle();
    expect(harness.token('a-token-0').positionInPath, 8);
  });
}
