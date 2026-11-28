import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_rank/core/audio/game_sound.dart';
import 'package:ludo_rank/core/dependency_injection/injection_container.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_player.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/game_result.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/ludo_game_result_overlay.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/ludo_match_board_art.dart';
import 'package:ludo_rank/features/match_players/domain/entities/match_player.dart';
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

  testWidgets('a captured token slides home after the capturing token '
      'lands, and input waits for it', (tester) async {
    final harness = MatchScreenHarness();
    // Green's token on 10 rolls 4 and lands on red's token (green's 14).
    final victimCell = pathFor(
      LudoPlayerColor.green,
    ).positionAt(step: 14, useHomeLane: false);
    final redStep = pathFor(
      LudoPlayerColor.red,
    ).mainLoopPath.indexOf(victimCell);
    await harness.setUp(
      players: [
        ludoPlayer('a', 1, LudoPlayerColor.green, onLoop: {0: 10}),
        ludoPlayer('b', 2, LudoPlayerColor.red, onLoop: {0: redStep}),
      ],
      dice: [4],
    );
    await harness.pump(tester, pulse: true);

    Set<String> hidden() => tester
        .widget<LudoMatchBoardArt>(find.byType(LudoMatchBoardArt))
        .hiddenTokenIds;

    await harness.roll(tester);
    // Wait for the only move to start by itself, then for its 4 hops.
    for (var i = 0; i < 5 && hidden().isEmpty; i++) {
      await tester.pump();
    }
    expect(hidden(), {'a-token-0'});
    // Four hops of 210ms.
    for (var i = 0; i < 30 && hidden().contains('a-token-0'); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Landed and captured: the red token is on its way home.
    expect(harness.token('a-token-0').positionInPath, 14);
    expect(harness.token('b-token-0').isInitial, isTrue);
    expect(hidden(), contains('b-token-0'));
    expect(
      harness.played.sounds,
      containsAllInOrder([GameSound.capture, GameSound.tokenReturn]),
    );
    expect(harness.played.haptics, [GameHaptic.light]);
    expect(harness.provider!.isInputLocked, isTrue);
    expect(
      tester.widget<FilledButton>(harness.rollButton).onPressed,
      isNull,
      reason: 'the capture bonus roll waits for the token to get home',
    );

    await tester.pump(const Duration(milliseconds: 380));
    await tester.pump();
    expect(hidden(), isEmpty);
    expect(harness.provider!.isInputLocked, isFalse);
    expect(
      tester.widget<FilledButton>(harness.rollButton).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the result fades and scales in, then ranks appear one by '
      'one with a reveal sound each', (tester) async {
    final played = RecordingSounds();
    await tester.pumpWidget(
      MaterialApp(
        home: LudoGameResultOverlay(
          players: const <MatchPlayer>[],
          isSaved: false,
          isLoading: false,
          onRetry: () {},
          onClose: null,
          playerNames: const {'a': 'A', 'b': 'B', 'c': 'C'},
          gameResult: const GameResult(
            players: [
              GamePlayerResult(playerId: 'b', rank: 1, finished: true),
              GamePlayerResult(playerId: 'a', rank: 2, finished: true),
              GamePlayerResult(playerId: 'c', rank: 3, finished: false),
            ],
            isFinished: true,
          ),
          sounds: played,
        ),
      ),
    );

    double opacityOf(String name) {
      final fade = find.ancestor(
        of: find.text(name),
        matching: find.byType(FadeTransition),
      );
      // The nearest FadeTransition is the row's own reveal.
      return tester.widget<FadeTransition>(fade.first).opacity.value;
    }

    final card = find.ancestor(
      of: find.byType(Card),
      matching: find.byType(ScaleTransition),
    );
    expect(tester.widget<ScaleTransition>(card.first).scale.value, .86);
    expect(played.sounds, isEmpty);

    // Mid-way: first place shown, third not yet.
    await tester.pump(const Duration(milliseconds: 520));
    expect(opacityOf('B'), greaterThan(.5));
    expect(opacityOf('C'), lessThan(.1));
    expect(played.sounds.length, inInclusiveRange(1, 2));

    await tester.pumpAndSettle();
    expect(opacityOf('B'), 1);
    expect(opacityOf('C'), 1);
    expect(tester.widget<ScaleTransition>(card.first).scale.value, 1);
    expect(played.sounds, List.filled(3, GameSound.reveal));
  });
}
