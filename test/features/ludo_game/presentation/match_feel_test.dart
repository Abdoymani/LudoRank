import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_rank/core/dependency_injection/injection_container.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_player.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/ludo_match_player_section.dart';

import 'match_screen_harness.dart';

/// Phase 4 "feel": the dice tumble, the captured token going home, the
/// result reveal.
void main() {
  tearDown(() => sl.reset());

  Finder cardOf(String playerId) {
    return find.byWidgetPredicate(
      (widget) =>
          widget is LudoMatchPlayerSection &&
          widget.player.playerId == playerId,
    );
  }

  bool isActive(WidgetTester tester, String playerId) {
    return tester.widget<LudoMatchPlayerSection>(cardOf(playerId)).isCurrent;
  }

  testWidgets('the die tumbles on the roller\'s card even when the roll '
      'passed the turn', (tester) async {
    final harness = MatchScreenHarness(
      diceAnimationDuration: const Duration(milliseconds: 400),
    );
    await harness.setUp(
      players: [
        ludoPlayer('a', 1, LudoPlayerColor.green),
        ludoPlayer('b', 2, LudoPlayerColor.red),
      ],
      dice: [3],
    );
    await harness.pump(tester, pulse: true);

    await harness.roll(tester);
    await tester.pump(const Duration(milliseconds: 200));

    expect(harness.engine.state.currentPlayer.playerId, 'b');
    expect(isActive(tester, 'a'), isTrue);
    expect(isActive(tester, 'b'), isFalse);
    final die = tester.widget<LudoMatchPlayerSection>(cardOf('a')).rollingDie;
    expect(die?.value, 3);
    expect(find.text('مفيش حركة متاحة'), findsNothing);

    await tester.pump(const Duration(milliseconds: 250));
    expect(isActive(tester, 'a'), isFalse);
    expect(isActive(tester, 'b'), isTrue);
    expect(find.text('مفيش حركة متاحة'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
