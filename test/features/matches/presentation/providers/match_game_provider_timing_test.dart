import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_rank/features/ludo_game/domain/models/move_option.dart';
import 'package:ludo_rank/features/ludo_game/domain/services/ludo_game_engine.dart';
import 'package:ludo_rank/features/matches/domain/entities/match.dart';
import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';
import 'package:ludo_rank/features/matches/domain/services/match_game_session.dart';
import 'package:ludo_rank/features/matches/presentation/providers/match_game_provider.dart';

import '../../domain/services/match_game_service_test.dart'
    show
        FakeMatchRepository,
        FakeMatchPlayerRepository,
        FakeMatchGameStateRepository;
import 'match_game_provider_test.dart'
    show createSession, createStartedState, FakeMatchGameService;

/// Returns the queued die values (1..6) in order.
class ScriptedRandom implements Random {
  final List<int> dice;
  ScriptedRandom(this.dice);

  @override
  int nextInt(int max) => dice.removeAt(0) - 1;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

void main() {
  late FakeMatchGameStateRepository gameStateRepository;
  late FakeMatchGameService service;
  late Match match;

  setUp(() {
    final matchRepository = FakeMatchRepository();
    final matchPlayerRepository = FakeMatchPlayerRepository();
    gameStateRepository = FakeMatchGameStateRepository();
    service = FakeMatchGameService(
      matchRepository: matchRepository,
      matchPlayerRepository: matchPlayerRepository,
      gameStateRepository: gameStateRepository,
    );
    final now = DateTime(2026, 1, 1);
    match = Match(
      id: 'match-1',
      tournamentId: 'tournament-1',
      playersCount: 2,
      status: MatchStatus.playing,
      createdAt: now,
      updatedAt: now,
    );
  });

  MatchGameSession sessionWithDice(List<int> dice) {
    return createSession(
      match: match,
      engine: LudoGameEngine(
        initialState: createStartedState(),
        random: ScriptedRandom(dice),
      ),
    );
  }

  Future<MatchGameProvider> started(
    List<int> dice, {
    Duration autoMoveDelay = Duration.zero,
    Duration diceAnimationDuration = Duration.zero,
  }) async {
    final provider = MatchGameProvider(
      service: service,
      autoMoveDelay: autoMoveDelay,
      diceAnimationDuration: diceAnimationDuration,
    );
    service.startSession = sessionWithDice(dice);
    await provider.startMatch(matchId: match.id, playerNames: const {});
    return provider;
  }

  /// Dice for: player 1 rolls 6+2, takes token 0 out and moves it 2;
  /// player 2 rolls 1 (no move, turn passes back). Player 1 rolls next.
  const setupDice = <int>[6, 2, 1];

  /// Plays [setupDice] so player 1 has exactly one token on the board.
  Future<void> oneTokenOnBoard(MatchGameProvider provider) async {
    await provider.rollDice();
    await provider.rollDice();
    final exit = provider.availableMoves.whereType<ExitToken>().firstWhere(
      (move) => move.tokenId == 'player-1-token-0',
    );
    await provider.executeMove(exit);
    await provider.executeMove(provider.availableMoves.single);
    await provider.rollDice();
    expect(provider.currentPlayerId, 'player-1');
  }

  test('availableMoves is cached until the engine state changes', () async {
    final provider = await started([6, 2]);
    await provider.rollDice();
    await provider.rollDice();

    final first = provider.availableMoves;
    expect(first, isNotEmpty);
    expect(identical(first, provider.availableMoves), isTrue);

    await provider.executeMove(first.first);
    expect(identical(first, provider.availableMoves), isFalse);
  });

  test('a roll with no legal move is kept visible as a roll notice', () async {
    final provider = await started([3]);

    await provider.rollDice();

    final notice = provider.rollNotice;
    expect(notice, isNotNull);
    expect(notice!.playerId, 'player-1');
    expect(notice.value, 3);
    expect(notice.turnCancelled, isFalse);
    // The engine already passed the turn.
    expect(provider.currentPlayerId, 'player-2');
    provider.dispose();
  });

  test('the third six shows a cancelled-turn notice', () async {
    final provider = await started([6, 6, 6]);

    await provider.rollDice();
    await provider.rollDice();
    await provider.rollDice();

    expect(provider.rollNotice?.turnCancelled, isTrue);
    expect(provider.rollNotice?.value, 6);
    expect(provider.currentPlayerId, 'player-2');
    provider.dispose();
  });

  test('a normal roll shows no notice', () async {
    final provider = await started([6]);
    await provider.rollDice();
    expect(provider.rollNotice, isNull);
  });

  test(
    'the only legal move waits for autoMoveDelay before it is offered',
    () async {
      final provider = await started([
        ...setupDice,
        3,
      ], autoMoveDelay: const Duration(milliseconds: 80));
      await oneTokenOnBoard(provider);

      final roll = provider.rollDice();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Roll is visible, the piece has not started moving yet.
      expect(provider.turnState?.lastRoll, 3);
      expect(provider.pendingAutoMove, isNull);

      await roll;
      final pending = provider.pendingAutoMove;
      expect(pending, isA<MoveToken>());
      expect((pending! as MoveToken).steps, 3);
    },
  );

  test(
    'a delayed auto move is dropped when the page closed meanwhile',
    () async {
      final provider = await started([
        ...setupDice,
        3,
      ], autoMoveDelay: const Duration(milliseconds: 40));
      await oneTokenOnBoard(provider);

      final roll = provider.rollDice();
      provider.dispose();
      await roll;

      expect(provider.pendingAutoMove, isNull);
    },
  );

  test('closing the page while a save is running does not throw', () async {
    final provider = await started([6]);
    final save = Completer<void>();
    gameStateRepository.saveCompleter = save;

    final roll = provider.rollDice();
    expect(provider.isSavingSnapshot, isTrue);

    final waiting = provider.waitForPendingSave();
    provider.dispose();
    save.complete();

    await roll;
    await waiting;
    expect(gameStateRepository.saveCallCount, 1);
  });

  group('second move of the turn', () {
    // 6 then 2: the 6 brings token 0 out, then only token 0 can play the 2.
    Future<MatchGameProvider> afterExit({
      Duration autoMoveDelay = Duration.zero,
    }) async {
      final provider = await started([6, 2], autoMoveDelay: autoMoveDelay);
      await provider.rollDice();
      await provider.rollDice();
      expect(provider.pendingAutoMove, isNull, reason: 'several exits');
      return provider;
    }

    ExitToken exitOf(MatchGameProvider provider) => provider.availableMoves
        .whereType<ExitToken>()
        .firstWhere((move) => move.tokenId == 'player-1-token-0');

    test('the only legal move left is played automatically', () async {
      final provider = await afterExit();

      await provider.executeMove(exitOf(provider));

      final pending = provider.pendingAutoMove;
      expect(pending, isA<MoveToken>());
      final move = pending! as MoveToken;
      expect(move.tokenId, 'player-1-token-0');
      expect(move.steps, 2);

      await provider.executeMove(move);
      expect(provider.currentPlayerId, 'player-2');
      expect(provider.pendingAutoMove, isNull);
    });

    test('it waits for autoMoveDelay and does not hold executeMove', () async {
      final provider = await afterExit(
        autoMoveDelay: const Duration(milliseconds: 60),
      );

      await provider.executeMove(exitOf(provider));
      expect(provider.pendingAutoMove, isNull);

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(provider.pendingAutoMove, isA<MoveToken>());
      provider.dispose();
    });

    test('it is dropped when the player moves by hand first', () async {
      final provider = await afterExit(
        autoMoveDelay: const Duration(milliseconds: 60),
      );

      await provider.executeMove(exitOf(provider));
      await provider.executeMove(provider.availableMoves.single);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(provider.pendingAutoMove, isNull);
      expect(provider.currentPlayerId, 'player-2');
    });

    test('it is dropped when the page closed meanwhile', () async {
      final provider = await afterExit(
        autoMoveDelay: const Duration(milliseconds: 40),
      );

      await provider.executeMove(exitOf(provider));
      provider.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(provider.pendingAutoMove, isNull);
    });

    test('it waits while the save fails', () async {
      final provider = await afterExit(
        autoMoveDelay: const Duration(milliseconds: 20),
      );
      gameStateRepository.throwExceptionOnSave = true;

      await provider.executeMove(exitOf(provider));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(provider.hasSnapshotSaveError, isTrue);
      expect(provider.pendingAutoMove, isNull);
    });

    test('no automatic move when several moves remain', () async {
      final provider = await started([6, 6, 2]);
      await provider.rollDice();
      await provider.rollDice();
      await provider.rollDice();

      final exit = provider.availableMoves.whereType<ExitToken>().firstWhere(
        (move) => move.tokenId == 'player-1-token-0' && move.rollSequence == 1,
      );
      await provider.executeMove(exit);

      expect(provider.availableMoves.length, greaterThan(1));
      expect(provider.pendingAutoMove, isNull);
    });
  });

  test('resume restores the automatic move after a roll', () async {
    final first = await started([...setupDice, 3]);
    await oneTokenOnBoard(first);
    await first.rollDice();
    final saved = first.session!;

    final resumed = MatchGameProvider(service: service);
    service.resumeSession = MatchGameSession(
      match: match,
      matchPlayers: saved.matchPlayers,
      engine: LudoGameEngine(initialState: saved.state),
    );

    await resumed.resumeMatch(matchId: match.id);

    expect(resumed.pendingAutoMove, isA<MoveToken>());
  });

  group('dice animation', () {
    const dice = Duration(milliseconds: 60);
    Future<void> tumbleDone() => Future<void>.delayed(dice * 1.5);

    test('stays on the roller and holds input until the die stops', () async {
      final provider = await started([3], diceAnimationDuration: dice);

      await provider.rollDice();

      // The engine already passed the turn; the die is still the roller's.
      expect(provider.currentPlayerId, 'player-2');
      expect(provider.diceRoll?.playerId, 'player-1');
      expect(provider.diceRoll?.value, 3);
      expect(provider.diceRoll?.turnStateBefore.playerId, 'player-1');
      expect(provider.isInputLocked, isTrue);
      expect(provider.canRollDice, isFalse);
      // The "no move" notice waits for the die to stop.
      expect(provider.rollNotice, isNull);

      await tumbleDone();

      expect(provider.diceRoll, isNull);
      expect(provider.rollNotice?.value, 3);
      expect(provider.canRollDice, isTrue);
      provider.dispose();
    });

    test('a second roll while the die tumbles is ignored', () async {
      final provider = await started([6, 2], diceAnimationDuration: dice);

      await provider.rollDice();
      await provider.rollDice();
      expect(provider.turnState?.rolls, hasLength(1));

      await tumbleDone();
      await provider.rollDice();
      expect(provider.turnState?.rolls, hasLength(2));
      provider.dispose();
    });

    test('the automatic move waits at least for the die', () async {
      final provider = await started([
        ...setupDice,
        3,
      ], diceAnimationDuration: dice);
      Future<void> roll() async {
        await provider.rollDice();
        await tumbleDone();
      }

      await roll();
      await roll();
      final exit = provider.availableMoves.whereType<ExitToken>().firstWhere(
        (move) => move.tokenId == 'player-1-token-0',
      );
      await provider.executeMove(exit);
      await provider.executeMove(provider.availableMoves.single);
      await roll();
      expect(provider.currentPlayerId, 'player-1');

      final rolling = provider.rollDice();
      await Future<void>.delayed(dice ~/ 3);
      expect(provider.isDiceRolling, isTrue);
      expect(provider.pendingAutoMove, isNull);

      await rolling;
      expect(provider.isDiceRolling, isFalse);
      expect(provider.pendingAutoMove, isA<MoveToken>());
      provider.dispose();
    });

    test('a board animation locks taps and the roll button', () async {
      final provider = await started([3]);
      expect(provider.canRollDice, isTrue);

      provider.setBoardAnimating(true);
      expect(provider.isInputLocked, isTrue);
      expect(provider.canRollDice, isFalse);
      await provider.rollDice();
      expect(provider.turnState?.rolls, isEmpty);

      provider.setBoardAnimating(false);
      expect(provider.canRollDice, isTrue);
      provider.dispose();
    });
  });
}
