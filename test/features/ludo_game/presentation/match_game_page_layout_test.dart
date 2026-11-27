import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_rank/core/dependency_injection/injection_container.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_player.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/ludo_match_board.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/ludo_match_player_section.dart';

import 'match_screen_harness.dart';

void main() {
  late MatchScreenHarness harness;

  setUp(() => harness = MatchScreenHarness());
  tearDown(() => sl.reset());

  Finder cardOf(String playerId) {
    return find.byWidgetPredicate(
      (widget) =>
          widget is LudoMatchPlayerSection &&
          widget.player.playerId == playerId,
    );
  }

  int turnsAbove(WidgetTester tester, Finder finder) {
    final rotated = find.ancestor(
      of: finder,
      matching: find.byType(RotatedBox),
    );
    return tester
        .widgetList<RotatedBox>(rotated)
        .fold<int>(0, (sum, box) => sum + box.quarterTurns);
  }

  testWidgets('top-row cards are turned to face the far side, by row', (
    tester,
  ) async {
    await harness.setUp(
      players: [
        ludoPlayer('a', 1, LudoPlayerColor.green),
        ludoPlayer('b', 2, LudoPlayerColor.yellow),
        ludoPlayer('c', 3, LudoPlayerColor.red),
        ludoPlayer('d', 4, LudoPlayerColor.blue),
      ],
    );
    await harness.pump(tester);

    expect(turnsAbove(tester, cardOf('a')) % 4, 2);
    expect(turnsAbove(tester, cardOf('b')) % 4, 2);
    expect(turnsAbove(tester, cardOf('c')) % 4, 0);
    expect(turnsAbove(tester, cardOf('d')) % 4, 0);

    // Cards sit against the board: the short (waiting) top card hangs at
    // the bottom of its row, next to the board.
    final board = tester.getRect(find.byType(LudoMatchBoard));
    final active = tester.getRect(cardOf('a'));
    final waiting = tester.getRect(cardOf('b'));
    expect(waiting.height, lessThan(active.height));
    expect(waiting.bottom, moreOrLessEquals(active.bottom, epsilon: .5));
    expect(waiting.bottom, lessThanOrEqualTo(board.top));

    final waitingBottom = tester.getRect(cardOf('d'));
    final activeBottomRowTop = tester.getRect(cardOf('c')).top;
    expect(waitingBottom.top, moreOrLessEquals(activeBottomRowTop));
    expect(waitingBottom.top, greaterThanOrEqualTo(board.bottom));
  });

  testWidgets('board dice chips of a top-row player face that player', (
    tester,
  ) async {
    await harness.setUp(
      players: [
        ludoPlayer('a', 1, LudoPlayerColor.green, onLoop: {0: 5}),
        ludoPlayer('b', 2, LudoPlayerColor.red, onLoop: {0: 5}),
      ],
      dice: [6, 3],
    );
    await harness.pump(tester);
    await harness.roll(tester);
    await harness.roll(tester);
    await harness.tapToken(tester, 'a-token-0');

    final chip = find.byKey(const ValueKey<String>('board-die-1'));
    expect(chip, findsOneWidget);
    expect(turnsAbove(tester, chip) % 4, 2);
    final tokenCenter = harness.tokenCenter(tester, harness.token('a-token-0'));
    expect(tester.getCenter(chip).dy, greaterThan(tokenCenter.dy));
  });

  testWidgets('board dice chips of a bottom-row player stay upright', (
    tester,
  ) async {
    await harness.setUp(
      players: [
        ludoPlayer('b', 1, LudoPlayerColor.red, onLoop: {0: 5}),
        ludoPlayer('a', 2, LudoPlayerColor.green, onLoop: {0: 5}),
      ],
      dice: [6, 3],
    );
    await harness.pump(tester);
    await harness.roll(tester);
    await harness.roll(tester);
    await harness.tapToken(tester, 'b-token-0');

    final chip = find.byKey(const ValueKey<String>('board-die-1'));
    expect(turnsAbove(tester, chip) % 4, 0);
    final tokenCenter = harness.tokenCenter(tester, harness.token('b-token-0'));
    expect(tester.getCenter(chip).dy, lessThan(tokenCenter.dy));
  });
}
