import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_rank/core/dependency_injection/injection_container.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_player.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/ludo_match_board.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/ludo_match_board_art.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/ludo_match_player_section.dart';

import 'match_screen_harness.dart';

void main() {
  late MatchScreenHarness harness;

  setUp(() => harness = MatchScreenHarness());
  tearDown(() => sl.reset());

  List<GlowRing> rings(WidgetTester tester) {
    final glow = find.byType(MovableTokenGlow);
    if (glow.evaluate().isEmpty) return const <GlowRing>[];
    return tester.widget<MovableTokenGlow>(glow).rings;
  }

  testWidgets('after the roll every token that can move glows, the '
      'selected one more', (tester) async {
    await harness.setUp(
      players: [
        ludoPlayer('a', 1, LudoPlayerColor.green, onLoop: {0: 5}),
        ludoPlayer('b', 2, LudoPlayerColor.red, onLoop: {0: 5}),
      ],
      dice: [6, 3],
    );
    await harness.pump(tester);
    expect(rings(tester), isEmpty, reason: 'nothing glows before the roll');

    await harness.roll(tester);
    await harness.roll(tester);
    expect(rings(tester).map((ring) => ring.tokenId), [
      'a-token-0',
      'a-token-1',
      'a-token-2',
      'a-token-3',
    ]);
    expect(rings(tester).where((ring) => ring.selected), isEmpty);

    await harness.tapToken(tester, 'a-token-0');
    expect(
      rings(tester).singleWhere((ring) => ring.selected).tokenId,
      'a-token-0',
    );

    // With only the 6 left (3 played), the home tokens and a-token-0 glow.
    await tester.tap(find.byKey(const ValueKey<String>('board-die-2')));
    await tester.pumpAndSettle();
    expect(rings(tester), hasLength(4));
  });

  testWidgets('the pulse never rebuilds the board, its art or the cards', (
    tester,
  ) async {
    await harness.setUp(
      players: [
        ludoPlayer('a', 1, LudoPlayerColor.green),
        ludoPlayer('b', 2, LudoPlayerColor.red),
      ],
      dice: [6, 3],
    );
    await harness.pump(tester, pulse: true);
    await harness.roll(tester);
    await harness.roll(tester);
    await tester.pump();
    expect(rings(tester), hasLength(4));

    final rebuilt = <Type, int>{};
    debugOnRebuildDirtyWidget = (element, _) {
      final type = element.widget.runtimeType;
      rebuilt[type] = (rebuilt[type] ?? 0) + 1;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(tester.hasRunningAnimations, isTrue, reason: 'it pulses');
    expect(rebuilt[LudoMatchBoard], isNull);
    expect(rebuilt[LudoMatchBoardArt], isNull);
    expect(rebuilt[LudoMatchPlayerSection], isNull);
    expect(rebuilt[MovableTokenGlow], isNull);
  });
}
