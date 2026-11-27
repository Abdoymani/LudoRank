import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ludo_rank/core/audio/sound_controller.dart';
import 'package:ludo_rank/core/dependency_injection/injection_container.dart';
import 'package:ludo_rank/core/settings/app_settings.dart';
import 'package:ludo_rank/features/ludo_game/domain/constants/ludo_paths.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_player.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_token.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/position.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/ludo_game_state.dart';
import 'package:ludo_rank/features/ludo_game/domain/services/ludo_game_engine.dart';
import 'package:ludo_rank/features/ludo_game/presentation/geometry/ludo_board_geometry.dart';
import 'package:ludo_rank/features/ludo_game/presentation/pages/match_game_page.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/ludo_match_board.dart';
import 'package:ludo_rank/features/match_players/domain/entities/match_player.dart';
import 'package:ludo_rank/features/matches/domain/Use-cases/cancel_match.dart';
import 'package:ludo_rank/features/matches/domain/entities/match.dart';
import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';
import 'package:ludo_rank/features/matches/domain/services/match_game_session.dart';
import 'package:ludo_rank/features/matches/presentation/providers/match_game_provider.dart';

import '../../matches/domain/services/match_game_service_test.dart'
    show
        FakeMatchRepository,
        FakeMatchPlayerRepository,
        FakeMatchGameStateRepository;
import '../../matches/presentation/providers/match_game_provider_test.dart'
    show FakeMatchGameService;
import '../../matches/presentation/providers/match_game_provider_timing_test.dart'
    show ScriptedRandom;

export '../../matches/presentation/providers/match_game_provider_timing_test.dart'
    show ScriptedRandom;

/// A token still in its base.
LudoToken homeToken(String playerId, int index) {
  return LudoToken(
    id: '$playerId-token-$index',
    playerId: playerId,
    tokenIndex: index,
    position: const Position(row: 0, column: 0),
    positionInPath: -1,
    state: LudoTokenState.initial,
  );
}

LudoPath pathFor(LudoPlayerColor color) {
  return switch (color) {
    LudoPlayerColor.red => LudoPaths.red,
    LudoPlayerColor.green => LudoPaths.green,
    LudoPlayerColor.yellow => LudoPaths.yellow,
    LudoPlayerColor.blue => LudoPaths.blue,
  };
}

/// A token on its own main loop at [step].
LudoToken loopToken(
  String playerId,
  LudoPlayerColor color,
  int index,
  int step,
) {
  return LudoToken(
    id: '$playerId-token-$index',
    playerId: playerId,
    tokenIndex: index,
    position: pathFor(color).positionAt(step: step, useHomeLane: false),
    positionInPath: step,
    state: LudoTokenState.normal,
  );
}

LudoPlayer ludoPlayer(
  String playerId,
  int seat,
  LudoPlayerColor color, {
  Map<int, int> onLoop = const <int, int>{},
}) {
  return LudoPlayer(
    id: 'ludo-$playerId',
    playerId: playerId,
    name: playerId,
    color: color,
    seat: seat,
    tokens: List<LudoToken>.generate(4, (index) {
      final step = onLoop[index];
      return step == null
          ? homeToken(playerId, index)
          : loopToken(playerId, color, index, step);
    }),
  );
}

/// Sets up the service locator and pumps [MatchGamePage] on a resumed
/// match whose engine starts from [state] and rolls [dice].
class MatchScreenHarness {
  final FakeMatchRepository matchRepository = FakeMatchRepository();
  final FakeMatchGameStateRepository gameStates =
      FakeMatchGameStateRepository();
  late final FakeMatchGameService service;
  late final SoundController sounds;
  late final LudoGameEngine engine;
  MatchGameProvider? provider;

  final Duration autoMoveDelay;
  final Duration diceAnimationDuration;

  MatchScreenHarness({
    this.autoMoveDelay = Duration.zero,
    this.diceAnimationDuration = Duration.zero,
  });

  Future<void> setUp({
    required List<LudoPlayer> players,
    List<int> dice = const <int>[],
    LudoGameState? state,
  }) async {
    await sl.reset();
    SharedPreferences.setMockInitialValues({'sound_enabled': false});
    sounds = SoundController(await AppSettings.load());
    service = FakeMatchGameService(
      matchRepository: matchRepository,
      matchPlayerRepository: FakeMatchPlayerRepository(),
      gameStateRepository: gameStates,
    );
    final now = DateTime(2026, 1, 1);
    final match = Match(
      id: 'match-1',
      tournamentId: 't1',
      playersCount: players.length,
      status: MatchStatus.playing,
      createdAt: now,
      updatedAt: now,
    );
    matchRepository.seed(match);
    engine = LudoGameEngine(
      initialState:
          state ??
          LudoGameState.initial(players: players).copyWith(isStarted: true),
      random: ScriptedRandom(<int>[...dice]),
    );
    service.resumeSession = MatchGameSession(
      match: match,
      matchPlayers: <MatchPlayer>[
        for (final player in players)
          MatchPlayer(
            id: 'mp-${player.playerId}',
            matchId: match.id,
            playerId: player.playerId,
            seat: player.seat,
            rank: null,
            points: 0,
            finished: false,
          ),
      ],
      engine: engine,
    );
    sl.registerFactory<MatchGameProvider>(() {
      return provider = MatchGameProvider(
        service: service,
        autoMoveDelay: autoMoveDelay,
        diceAnimationDuration: diceAnimationDuration,
      );
    });
    sl.registerSingleton<CancelMatch>(
      CancelMatch(
        matchRepository: matchRepository,
        gameStateRepository: gameStates,
      ),
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(392.7, 800),
    double textScale = 1.0,
    bool pulse = false,
  }) async {
    tester.view.physicalSize = size * 2.75;
    tester.view.devicePixelRatio = 2.75;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    // The movable-token glow pulses forever while a move is to be chosen,
    // which pumpAndSettle would wait on; tests opt in with [pulse]. With
    // "remove animations" on, Flutter also runs every animation 20x
    // faster, so timing tests pass pulse: true.
    if (!pulse) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
    }
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(
      ChangeNotifierProvider<SoundController>.value(
        value: sounds,
        child: MaterialApp(
          home: MatchGamePage(
            matchId: 'match-1',
            playerNames: <String, String>{
              for (final player in engine.state.players)
                player.playerId: player.name,
            },
            resumeExisting: true,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Global position of the center of board cell [position].
  Offset cellCenter(WidgetTester tester, Position position) {
    final box = tester.renderObject<RenderBox>(find.byType(LudoMatchBoard));
    final side = min(box.size.width, box.size.height);
    final frame = (side * .017).clamp(3.0, 5.0).toDouble();
    // The board art paints inside a [frame] padding on every side.
    final inner = side - frame * 2;
    final origin = box.localToGlobal(
      Offset((box.size.width - side) / 2, (box.size.height - side) / 2),
    );
    return origin +
        Offset(frame, frame) +
        LudoBoardGeometry.instance.cellCenter(position, inner);
  }

  /// One board cell, in logical pixels.
  double cellSize(WidgetTester tester) {
    final box = tester.renderObject<RenderBox>(find.byType(LudoMatchBoard));
    final side = min(box.size.width, box.size.height);
    final frame = (side * .017).clamp(3.0, 5.0).toDouble();
    return (side - frame * 2) / LudoBoardGeometry.gridSize;
  }

  /// Where [token] is drawn (base pad or board cell).
  Offset tokenCenter(WidgetTester tester, LudoToken token) {
    final player = engine.state.players.firstWhere(
      (p) => p.playerId == token.playerId,
    );
    final position = token.isInitial
        ? LudoBoardGeometry.instance.tokenHomePosition(
            color: player.color,
            tokenIndex: token.tokenIndex,
          )
        : token.position;
    return cellCenter(tester, position);
  }

  LudoToken token(String id) {
    return engine.state.players
        .expand((player) => player.tokens)
        .firstWhere((token) => token.id == id);
  }

  Future<void> tapToken(
    WidgetTester tester,
    String id, {
    Offset offset = Offset.zero,
  }) async {
    await tester.tapAt(tokenCenter(tester, token(id)) + offset);
    await tester.pump();
  }

  /// The roll button on the current player's card.
  Finder get rollButton => find.byKey(const ValueKey<String>('roll-button'));

  Future<void> roll(WidgetTester tester) async {
    await tester.tap(rollButton);
    await tester.pump();
  }
}
