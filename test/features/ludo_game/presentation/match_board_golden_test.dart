@Tags(<String>['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_player.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/available_rolls.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/ludo_match_board.dart';

import 'match_screen_harness.dart';

/// One still board: any change to the board art shows up as a diff.
/// Regenerate on Linux with `flutter test --update-goldens --tags golden`.
void main() {
  testWidgets('match board', (tester) async {
    tester.view.physicalSize = const Size(360, 360) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final players = <LudoPlayer>[
      // Two green tokens stacked on one square, one further on.
      ludoPlayer('a', 1, LudoPlayerColor.green, onLoop: {0: 8, 1: 8, 2: 20}),
      ludoPlayer('b', 2, LudoPlayerColor.yellow, onLoop: {0: 3}),
      ludoPlayer('c', 3, LudoPlayerColor.red, onLoop: {1: 30}),
      ludoPlayer('d', 4, LudoPlayerColor.blue),
    ];

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF17121E),
          body: Center(
            child: RepaintBoundary(
              key: const ValueKey<String>('golden'),
              child: SizedBox.square(
                dimension: 340,
                child: LudoMatchBoard(
                  players: players,
                  currentPlayerId: 'a',
                  availableMoves: const [],
                  selectedTokenId: null,
                  onTokenTap: (_) {},
                  legalMoveDestinations: const {},
                  rollValueForMove: (_) => null,
                  onMoveTap: (_) async {},
                  selectableRolls: const AvailableRolls(),
                  onAvailableRollTap: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byKey(const ValueKey<String>('golden')),
      matchesGoldenFile('goldens/match_board.png'),
    );
  }, skip: !Platform.isLinux);
}
