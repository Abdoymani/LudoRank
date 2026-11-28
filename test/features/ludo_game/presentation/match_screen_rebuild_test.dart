import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_rank/core/dependency_injection/injection_container.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_player.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/ludo_match_board.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/ludo_match_board_art.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/ludo_match_player_section.dart';

import 'match_screen_harness.dart';

/// Counts widget rebuilds, so the match screen stays cheap per frame.
class RebuildCounter {
  final Map<Type, int> byType = <Type, int>{};
  final Map<String, int> cardsByPlayer = <String, int>{};

  void start() {
    debugOnRebuildDirtyWidget = (element, _) {
      final widget = element.widget;
      byType[widget.runtimeType] = (byType[widget.runtimeType] ?? 0) + 1;
      if (widget is LudoMatchPlayerSection) {
        final id = widget.player.playerId;
        cardsByPlayer[id] = (cardsByPlayer[id] ?? 0) + 1;
      }
    };
  }

  void stop() => debugOnRebuildDirtyWidget = null;

  int of(Type type) => byType[type] ?? 0;
}

void main() {
  late MatchScreenHarness harness;
  late RebuildCounter counter;

  setUp(() {
    harness = MatchScreenHarness();
    counter = RebuildCounter();
  });
  tearDown(() {
    counter.stop();
    return sl.reset();
  });

  testWidgets('while a token walks, nothing but the moving token is rebuilt', (
    tester,
  ) async {
    await harness.setUp(
      players: [
        ludoPlayer('a', 1, LudoPlayerColor.green, onLoop: {0: 5}),
        ludoPlayer('b', 2, LudoPlayerColor.red),
      ],
      dice: [3],
    );
    // Real durations: "remove animations" would run the walk 20x faster.
    await harness.pump(tester, pulse: true);
    await harness.roll(tester);
    // The only move starts by itself once the roll is saved.
    bool walking() => tester
        .widget<LudoMatchBoardArt>(find.byType(LudoMatchBoardArt))
        .hiddenTokenIds
        .isNotEmpty;
    for (var i = 0; i < 5 && !walking(); i++) {
      await tester.pump();
    }
    expect(walking(), isTrue);

    counter.start();
    // Three squares take 630ms; stay inside the walk.
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    counter.stop();

    expect(counter.of(Scaffold), 0);
    expect(counter.of(LudoMatchBoard), 0);
    expect(counter.of(LudoMatchBoardArt), 0);
    expect(counter.of(LudoMatchPlayerSection), 0);

    await tester.pumpAndSettle();
    expect(harness.token('a-token-0').positionInPath, 8);
  });

  testWidgets('a roll rebuilds the cards it changes, not the waiting ones', (
    tester,
  ) async {
    await harness.setUp(
      players: [
        ludoPlayer('a', 1, LudoPlayerColor.green),
        ludoPlayer('b', 2, LudoPlayerColor.yellow),
        ludoPlayer('c', 3, LudoPlayerColor.red),
        ludoPlayer('d', 4, LudoPlayerColor.blue),
      ],
      dice: [3],
    );
    await harness.pump(tester);

    counter.start();
    // No legal move: the turn passes from a to b.
    await harness.roll(tester);
    await tester.pumpAndSettle();
    counter.stop();

    expect(harness.engine.state.currentPlayer.playerId, 'b');
    expect(counter.cardsByPlayer['a'], isNotNull);
    expect(counter.cardsByPlayer['b'], isNotNull);
    expect(counter.cardsByPlayer['c'], isNull);
    expect(counter.cardsByPlayer['d'], isNull);
    expect(counter.of(Scaffold), 0);
  });
}
