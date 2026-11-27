import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:ludo_rank/core/audio/game_sound.dart';
import 'package:ludo_rank/core/audio/sound_controller.dart';
import 'package:ludo_rank/core/database/database_checkpointer.dart';
import 'package:ludo_rank/features/matches/presentation/providers/game_sound_events.dart';

import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_player.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/available_rolls.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/game_result.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/ludo_game_state.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/move_option.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/turn_state.dart';

import 'package:ludo_rank/features/match_players/domain/entities/match_player.dart';

import '../../domain/entities/match.dart';
import '../../domain/entities/match_status.dart';
import '../../domain/services/match_game_service.dart';
import '../../domain/services/match_game_session.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_token.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/position.dart';

class MatchGameProvider extends ChangeNotifier {
  final MatchGameService service;

  /// Plays game sound effects. Null in tests (silent).
  final GameSoundPlayer? sounds;

  MatchGameSession? _session;

  MatchStatus? _matchStatus;

  final List<MatchPlayer> _completedPlayers = [];

  String? _selectedTokenId;
  int? _selectedRollSequence;

  // الحركة الوحيدة المنتظرة للتنفيذ التلقائي.
  MoveOption? _pendingAutoMove;

  // حماية من استدعاء التنفيذ التلقائي أكثر من مرة.
  bool _isAutoMoveExecuting = false;
  bool _isLoading = false;

  String? _error;
  bool _isSavingSnapshot = false;
  bool _snapshotSaveFailed = false;

  /// Pause between showing a roll and auto-moving the only legal token,
  /// so players can see the die before the piece starts walking.
  final Duration autoMoveDelay;

  bool _disposed = false;

  // Cache of engine.getValidMoves() for the current engine state. The engine
  // replaces its state object on every change, so identity is a safe key.
  LudoGameState? _movesCacheState;
  List<MoveOption> _movesCache = const <MoveOption>[];

  /// Waits for this match's in-flight save before a WAL checkpoint.
  final DatabaseCheckpointer? checkpointer;

  MatchGameProvider({
    required this.service,
    this.sounds,
    this.autoMoveDelay = Duration.zero,
    this.checkpointer,
  }) {
    checkpointer?.addPendingSaveWaiter(waitForPendingSave);
  }

  bool get isDisposed => _disposed;

  // Shows a roll whose turn passed without a move (no legal move or a
  // third six), which the engine otherwise skips in the same frame.
  RollNotice? _rollNotice;
  Timer? _rollNoticeTimer;
  final List<Timer> _soundTimers = <Timer>[];

  // The save started by the last roll or move; leaving the page waits for it.
  Future<void>? _pendingSave;

  RollNotice? get rollNotice => _rollNotice;

  /// Display time for [rollNotice].
  static const Duration rollNoticeDuration = Duration(milliseconds: 1400);

  /// Waits for an in-flight snapshot save (used before leaving the match).
  Future<void> waitForPendingSave() async {
    final save = _pendingSave;
    if (save == null) return;
    try {
      await save;
    } catch (_) {
      // The save error is already shown through [error].
    }
  }

  @override
  void notifyListeners() {
    // Async saves can finish after the page closed; never touch a disposed
    // notifier.
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    checkpointer?.removePendingSaveWaiter(waitForPendingSave);
    _rollNoticeTimer?.cancel();
    for (final timer in _soundTimers) {
      timer.cancel();
    }
    _soundTimers.clear();
    super.dispose();
  }

  // ============================================================
  // CONSTRUCTOR AND DESTRUCTOR isAutoMove
  // ======================================
  MoveOption? get pendingAutoMove => _pendingAutoMove;

  bool get isAutoMoveExecuting => _isAutoMoveExecuting;

  // ============================================================
  // SESSION
  // ============================================================

  MatchGameSession? get session => _session;

  /// Match metadata snapshot.
  ///
  /// IMPORTANT:
  /// status هنا هو الـ snapshot الأصلي الموجود داخل Session.
  /// استخدم [matchStatus] لمعرفة الـ lifecycle الحالي.
  Match? get match => _session?.match;

  // ============================================================
  // GAME STATE
  // ============================================================

  LudoGameState? get state => _session?.state;

  List<LudoPlayer> get players {
    return _session?.state.players ?? const <LudoPlayer>[];
  }

  LudoPlayer? get currentPlayer {
    return _session?.engine.currentPlayer;
  }

  String? get currentPlayerId {
    return _session?.currentPlayerId;
  }

  // ============================================================
  // TURN
  // ============================================================

  TurnState? get turnState {
    return _session?.engine.state.turnState;
  }

  AvailableRolls get availableRolls {
    return _session?.engine.state.turnState.availableRolls ??
        const AvailableRolls();
  }

  List<MoveOption> get availableMoves {
    final session = _session;
    if (session == null) return const <MoveOption>[];

    final engineState = session.engine.state;
    if (!identical(engineState, _movesCacheState)) {
      _movesCacheState = engineState;
      _movesCache = List<MoveOption>.unmodifiable(
        session.engine.getValidMoves(),
      );
    }
    return _movesCache;
  }

  // ===========================
  /// Legal destinations for the currently selected token.
  /// Each destination keeps the original MoveOption objects.
  /// =============================
  Map<Position, List<MoveOption>> get selectedMoveDestinations {
    final session = _session;
    final tokenId = _selectedTokenId;

    if (session == null || tokenId == null) {
      return const <Position, List<MoveOption>>{};
    }

    final result = <Position, List<MoveOption>>{};

    for (final move in availableMoves) {
      final moveTokenId = switch (move) {
        MoveToken(:final tokenId) => tokenId,
        ExitToken(:final tokenId) => tokenId,
      };

      if (moveTokenId != tokenId) continue;

      final destination = session.engine.getMoveDestination(move);
      if (destination == null) continue;

      result.putIfAbsent(destination, () => <MoveOption>[]).add(move);
    }

    return Map.unmodifiable({
      for (final entry in result.entries)
        entry.key: List<MoveOption>.unmodifiable(entry.value),
    });
  }

  /// Gets the visible dice value for a legal move without exposing its sequence.
  int? rollValueForMove(MoveOption move) {
    return availableRolls.getBySequence(move.rollSequence)?.value;
  }

  /// Executes the exact legal option selected on the board.
  Future<void> handleBoardMoveTap(MoveOption move) async {
    if (!availableMoves.any((candidate) {
      if (candidate is MoveToken && move is MoveToken) {
        return candidate.tokenId == move.tokenId &&
            candidate.steps == move.steps &&
            candidate.rollSequence == move.rollSequence;
      }

      if (candidate is ExitToken && move is ExitToken) {
        return candidate.tokenId == move.tokenId &&
            candidate.rollSequence == move.rollSequence;
      }

      return false;
    })) {
      return;
    }

    await executeMove(move);
  }

  // ===========================================================
  // وأضف Getters في قسم UI STATE:
  // ===========================================================
  bool get isSavingSnapshot => _isSavingSnapshot;

  bool get hasSnapshotSaveError => _snapshotSaveFailed;

  bool get isSnapshotSaveBlocked => _isSavingSnapshot || _snapshotSaveFailed;

  // ============================================================
  // RESULT
  // ============================================================

  /// Final GameResult.
  ///
  /// قبل انتهاء اللعبة:
  /// null
  ///
  /// بعد انتهاء الـ Engine:
  /// يحتوي على ترتيب اللاعبين.
  GameResult? get result {
    final currentSession = _session;

    if (currentSession == null || !currentSession.isFinished) {
      return null;
    }

    return currentSession.result;
  }

  List<MatchPlayer> get completedPlayers {
    return List.unmodifiable(_completedPlayers);
  }

  // ============================================================
  // UI STATE
  // ============================================================

  MatchStatus? get matchStatus => _matchStatus;

  String? get selectedTokenId => _selectedTokenId;
  int? get selectedRollSequence => _selectedRollSequence;

  bool get isLoading => _isLoading;

  String? get error => _error;

  // ============================================================
  // STATUS HELPERS
  // ============================================================

  bool get isStarted {
    return _session?.isStarted ?? false;
  }

  /// هل محرك Ludo انتهى بالفعل؟
  ///
  /// قد تكون true بينما ما زلنا نحفظ النتيجة في DB.
  bool get isGameFinished {
    return _session?.isFinished ?? false;
  }

  /// هل Match نفسها أصبحت Finished في persistence؟
  bool get isFinished {
    return _matchStatus == MatchStatus.finished;
  }

  bool get isPlaying {
    return _matchStatus == MatchStatus.playing;
  }

  bool get canRollDice {
    return isStarted &&
        !isLoading &&
        !isSnapshotSaveBlocked &&
        !isGameFinished &&
        turnState?.isRolling == true;
  }

  bool get canExecuteMove {
    return isStarted &&
        !isLoading &&
        !isSnapshotSaveBlocked &&
        !isGameFinished &&
        turnState?.isPlaying == true &&
        availableMoves.isNotEmpty;
  }

  // ============================================================
  // ROLL DICE HELPERS
  // ============================================================
  AvailableRolls get selectableRolls {
    final legalSequences = availableMoves
        .where((move) {
          if (_selectedTokenId == null) return true;

          if (move is MoveToken) {
            return move.tokenId == _selectedTokenId;
          }

          if (move is ExitToken) {
            return move.tokenId == _selectedTokenId;
          }

          return false;
        })
        .map((move) => move.rollSequence)
        .toSet();

    return AvailableRolls(
      rolls: availableRolls.rolls
          .where((roll) => legalSequences.contains(roll.sequence))
          .toList(growable: false),
    );
  }

  // ============================================================
  // START MATCH
  // ============================================================

  /// Starts a brand-new Pending Match.
  ///
  /// Pending -> Playing
  ///
  /// This method does NOT resume an existing Playing Match.
  Future<void> startMatch({
    required String matchId,
    required Map<String, String> playerNames,
    Random? random,
  }) async {
    _setLoading(true);
    _error = null;

    _selectedTokenId = null;
    _selectedRollSequence = null;
    _isSavingSnapshot = false;
    _snapshotSaveFailed = false;

    _completedPlayers.clear();

    try {
      final createdSession = await service.startMatch(
        matchId: matchId,
        playerNames: playerNames,
        random: random,
      );

      _session = createdSession;

      _matchStatus = createdSession.match.status;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }
  // ============================================================
  //
  // ============================================================

  // ============================================================
  // RESUME MATCH
  // ============================================================

  /// Restores an existing Playing Match from its saved snapshot.
  ///
  /// This method does NOT start a new match and does NOT reset
  /// the restored LudoGameEngine state.
  Future<void> resumeMatch({required String matchId}) async {
    // منع الاحتفاظ بأي اختيارات أو حركة معلقة من جلسة سابقة.
    _session = null;
    _matchStatus = null;

    _selectedTokenId = null;
    _selectedRollSequence = null;

    _pendingAutoMove = null;
    _isAutoMoveExecuting = false;

    _isSavingSnapshot = false;
    _snapshotSaveFailed = false;

    _completedPlayers.clear();

    _error = null;

    _setLoading(true);

    try {
      // الاستعادة تتم من الخدمة مباشرة، وليس من startMatch.
      final restoredSession = await service.resumeMatch(matchId: matchId);

      _session = restoredSession;
      _matchStatus = restoredSession.match.status;

      // The match may have been left right after a roll with only one legal
      // move; restore the automatic move so the board doesn't look frozen.
      final moves = availableMoves;
      if (turnState?.isPlaying == true && moves.length == 1) {
        _pendingAutoMove = moves.single;
      }
    } catch (e) {
      _session = null;
      _matchStatus = null;
      if (e is StateError &&
          e.toString().contains('لا توجد Snapshot محفوظة للمباراة')) {
        _error =
            'لا يمكن استكمال هذه المباراة. لا توجد نسخة محفوظة من حالة اللعب، '
            'لأن المباراة بدأت قبل تفعيل نظام الحفظ والاستعادة. '
            'يمكنك بدء مباراة جديدة.';
      } else {
        _error =
            'تعذر استكمال المباراة بسبب مشكلة في البيانات المحفوظة. '
            'لم يتم حذف المباراة أو بيانات البطولة.';
      }
    } finally {
      _setLoading(false);
    }

    // The app closed after the winning move but before the result was
    // saved: the finished board was restored, so save the result now and
    // show the result screen instead of asking for the last move again.
    final restored = _session;
    if (restored != null &&
        restored.isFinished &&
        _matchStatus != MatchStatus.finished) {
      await _completeFinishedMatch();
    }
  }

  // ============================================================
  // ROLL DICE
  // ============================================================

  /// Rolls the dice through LudoGameEngine.
  ///
  /// All dice rules remain inside the Engine:
  /// - normal rolls
  /// - six
  /// - multiple sixes
  /// - third-six cancellation
  /// - no-legal-move handling
  Future<void> rollDice() async {
    final currentSession = _session;

    if (currentSession == null ||
        isLoading ||
        isSnapshotSaveBlocked ||
        isGameFinished ||
        turnState?.isRolling != true) {
      return;
    }

    try {
      _error = null;

      _selectedTokenId = null;
      _selectedRollSequence = null;
      _pendingAutoMove = null;
      _isAutoMoveExecuting = false;

      _rollNotice = null;
      _rollNoticeTimer?.cancel();

      // المحرك وحده مسؤول عن قواعد رمي النرد.
      final stateBeforeRoll = currentSession.engine.state;
      currentSession.engine.rollDice();
      _playSounds(
        GameSoundEvents.forRoll(stateBeforeRoll, currentSession.engine.state),
      );
      _showRollNoticeIfTurnPassed(stateBeforeRoll, currentSession);

      // الحركة الوحيدة تتنفذ تلقائيًا، لكن بعد ما اللاعب يشوف النرد.
      final legalMoves = availableMoves;
      final stateAfterRoll = currentSession.engine.state;
      final autoMove = turnState?.isPlaying == true && legalMoves.length == 1
          ? legalMoves.single
          : null;

      if (autoMove != null && autoMoveDelay == Duration.zero) {
        _pendingAutoMove = autoMove;
      }

      // قفل اللعب قبل بدء الحفظ.
      _isSavingSnapshot = true;
      _snapshotSaveFailed = false;

      notifyListeners();

      try {
        await _trackSave(service.saveSnapshot(session: currentSession));

        _isSavingSnapshot = false;
        _snapshotSaveFailed = false;

        notifyListeners();

        if (autoMove != null && autoMoveDelay > Duration.zero) {
          await _offerAutoMoveAfterDelay(
            currentSession,
            stateAfterRoll,
            autoMove,
          );
        }
      } catch (e) {
        _isSavingSnapshot = false;
        _snapshotSaveFailed = true;

        _error = 'تعذر حفظ حالة الرمية: $e';

        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      _pendingAutoMove = null;

      notifyListeners();
    }
  }

  Future<void> retrySnapshotSave() async {
    final currentSession = _session;

    if (currentSession == null || _isSavingSnapshot || !_snapshotSaveFailed) {
      return;
    }

    _isSavingSnapshot = true;

    notifyListeners();

    try {
      await service.saveSnapshot(session: currentSession);

      _snapshotSaveFailed = false;
      _error = null;
    } catch (e) {
      _snapshotSaveFailed = true;
      _error = 'فشلت إعادة حفظ حالة الرمية: $e';
    } finally {
      _isSavingSnapshot = false;
      notifyListeners();
    }
  }

  // ===========================================================
  //  executePendingAutoMove
  //============================================================
  Future<void> executePendingAutoMove() async {
    if (_isAutoMoveExecuting ||
        isLoading ||
        isSnapshotSaveBlocked ||
        isGameFinished) {
      return;
    }

    final move = _pendingAutoMove;
    final currentSession = _session;

    if (move == null ||
        currentSession == null ||
        turnState?.isPlaying != true) {
      return;
    }

    // نتحقق أن الحركة ما زالت قانونية قبل تنفيذها.
    final isStillLegal = availableMoves.any((candidate) {
      if (candidate is MoveToken && move is MoveToken) {
        return candidate.tokenId == move.tokenId &&
            candidate.steps == move.steps &&
            candidate.rollSequence == move.rollSequence;
      }

      if (candidate is ExitToken && move is ExitToken) {
        return candidate.tokenId == move.tokenId &&
            candidate.rollSequence == move.rollSequence;
      }

      return false;
    });

    if (!isStillLegal) {
      _pendingAutoMove = null;
      notifyListeners();
      return;
    }

    // قفل التنفيذ قبل أي عملية غير متزامنة.
    _isAutoMoveExecuting = true;
    _pendingAutoMove = null;

    notifyListeners();

    try {
      await executeMove(move);
    } finally {
      _isAutoMoveExecuting = false;
      notifyListeners();
    }
  }

  // ============================================================
  // SELECT TOKEN
  // ============================================================
  /// Handles a token tap using the legal moves from LudoGameEngine.
  ///
  /// One legal move  -> execute immediately.
  /// Multiple moves  -> select the token and show its move options.
  /// No legal moves  -> do not move the token.
  Future<void> handleTokenTap(LudoToken token) async {
    if (isSnapshotSaveBlocked) {
      return;
    }
    final currentSession = _session;
    final activePlayer = currentPlayer;

    if (currentSession == null ||
        activePlayer == null ||
        token.playerId != activePlayer.playerId ||
        turnState?.isPlaying != true ||
        isLoading ||
        currentSession.isFinished) {
      return;
    }

    final tokenMoves = availableMoves
        .where((move) {
          if (move is MoveToken) return move.tokenId == token.id;
          if (move is ExitToken) return move.tokenId == token.id;
          return false;
        })
        .toList(growable: false);

    if (tokenMoves.isEmpty) return;

    // إذا اختير النرد أولًا، نحاول تنفيذ الحركة المطابقة له فقط.
    if (_selectedRollSequence != null) {
      final matchingMoves = tokenMoves
          .where((move) => move.rollSequence == _selectedRollSequence)
          .toList(growable: false);

      if (matchingMoves.length == 1) {
        _pendingAutoMove = matchingMoves.single;
        notifyListeners();
        return;
      }

      if (matchingMoves.isNotEmpty) {
        _selectedTokenId = token.id;
        notifyListeners();
        return;
      }

      // الرمية المختارة لا تناسب هذا التوكن.
      // نحدد التوكن ونترك الواجهة تعرض رمياته القانونية.
      _selectedTokenId = token.id;
      _selectedRollSequence = null;
      notifyListeners();
      return;
    }

    // لمسة واحدة تكفي عندما توجد حركة قانونية واحدة فقط.
    if (tokenMoves.length == 1) {
      _pendingAutoMove = tokenMoves.single;
      notifyListeners();
      return;
    }

    // تعدد الحركات: نحدد التوكن ليختار اللاعب النرد المناسب.
    _selectedTokenId = token.id;
    notifyListeners();
  }

  //
  /// UI-only token selection
  ///
  /// This method NEVER moves a token
  /// and NEVER changes the LudoGameEngine.
  void selectToken(String tokenId) {
    if (_selectedTokenId == tokenId) {
      _selectedTokenId = null;
      _selectedRollSequence = null;
    } else {
      _selectedTokenId = tokenId;
    }

    notifyListeners();
  }

  void clearSelection() {
    if (_selectedTokenId == null && _selectedRollSequence == null) {
      return;
    }

    _selectedTokenId = null;
    _selectedRollSequence = null;

    notifyListeners();
  }

  // ============================================================
  // EXECUTE MOVE
  // ============================================================

  /// Executes an already validated MoveOption through
  /// the LudoGameEngine.
  ///
  /// If the move finishes the complete Ludo game,
  /// the provider automatically persists the Match.
  Future<void> executeMove(MoveOption move) async {
    if (isSnapshotSaveBlocked || isLoading || isGameFinished) {
      return;
    }

    final currentSession = _session;

    if (_isAutoMoveExecuting &&
        _pendingAutoMove != null &&
        move != _pendingAutoMove) {
      return;
    }

    if (currentSession == null) {
      _setError('لا توجد جلسة مباراة نشطة.');
      return;
    }

    try {
      _error = null;

      // 1. تنفيذ الحركة من خلال المحرك فقط.
      final stateBeforeMove = currentSession.engine.state;
      currentSession.engine.executeMove(move);
      final moveSound = GameSoundEvents.forMove(
        stateBeforeMove,
        currentSession.engine.state,
        move,
      );
      if (moveSound != null) sounds?.play(moveSound);

      // 2. مسح اختيارات اللاعب والحركة المعلقة.
      _selectedTokenId = null;
      _selectedRollSequence = null;
      _pendingAutoMove = null;

      // 3. لو المباراة انتهت، نحفظ النتيجة النهائية.
      // لا نحفظ Snapshot عادية لحالة منتهية.
      if (currentSession.isFinished) {
        notifyListeners();

        if (_matchStatus != MatchStatus.finished) {
          await _completeFinishedMatch();
        }

        return;
      }

      // The turn goes on (e.g. 6 then 3, the 6 was played) and the rest
      // has a single legal move: play it automatically, like after a roll.
      final legalMoves = availableMoves;
      final stateAfterMove = currentSession.engine.state;
      final autoMove = turnState?.isPlaying == true && legalMoves.length == 1
          ? legalMoves.single
          : null;

      if (autoMove != null && autoMoveDelay == Duration.zero) {
        _pendingAutoMove = autoMove;
      }

      // 4. قفل اللعب أثناء حفظ Snapshot.
      _isSavingSnapshot = true;
      _snapshotSaveFailed = false;

      notifyListeners();

      // 5. حفظ الحالة الجديدة بعد الحركة.
      var saved = false;
      try {
        await _trackSave(service.saveSnapshot(session: currentSession));

        _isSavingSnapshot = false;
        _snapshotSaveFailed = false;
        _error = null;
        saved = true;
      } catch (e) {
        _isSavingSnapshot = false;
        _snapshotSaveFailed = true;
        _error = 'تعذر حفظ حالة الحركة: $e';
      }

      notifyListeners();

      // Not awaited: the board waits for executeMove to finish its
      // animation bookkeeping before it can start the next move.
      if (saved && autoMove != null && autoMoveDelay > Duration.zero) {
        unawaited(
          _offerAutoMoveAfterDelay(currentSession, stateAfterMove, autoMove),
        );
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  // ============================================================
  // HANDLE ROLL TAP
  // ============================================================
  Future<void> handleAvailableRollTap(int sequence) async {
    if (turnState?.isPlaying != true ||
        isLoading ||
        isSnapshotSaveBlocked ||
        isGameFinished ||
        !availableRolls.containsSequence(sequence)) {
      return;
    }

    final options = availableMoves
        .where((move) {
          if (move.rollSequence != sequence) return false;

          if (_selectedTokenId == null) return true;

          if (move is MoveToken) {
            return move.tokenId == _selectedTokenId;
          }

          if (move is ExitToken) {
            return move.tokenId == _selectedTokenId;
          }

          return false;
        })
        .toList(growable: false);

    if (options.isEmpty) return;

    // عند تحديد توكن، اختيار النرد ينفذ الحركة القانونية المرتبطة به.
    if (_selectedTokenId != null && options.length == 1) {
      _pendingAutoMove = options.single;
      notifyListeners();
      return;
    }

    // قبل تحديد التوكن، نحتفظ باختيار النرد حتى يختار اللاعب حجرًا.
    _selectedRollSequence = sequence;
    notifyListeners();
  }

  // ============================================================
  // COMPLETE FINISHED MATCH
  // ============================================================

  /// Internal lifecycle operation.
  ///
  /// The UI does NOT call this directly.
  Future<void> _completeFinishedMatch() async {
    final currentSession = _session;

    if (currentSession == null) {
      _setError('لا توجد جلسة مباراة نشطة.');
      return;
    }

    if (!currentSession.isFinished) {
      _setError('محرك اللعبة لم ينتهِ بعد.');
      return;
    }

    if (_matchStatus == MatchStatus.finished) {
      return;
    }

    _setLoading(true);
    _error = null;

    try {
      final updatedPlayers = await service.completeMatch(currentSession);

      _completedPlayers
        ..clear()
        ..addAll(updatedPlayers);

      _matchStatus = MatchStatus.finished;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  // ============================================================
  // RETRY FINAL PERSISTENCE
  // ============================================================

  /// Used only when the Ludo engine already finished
  /// but persistence failed.
  ///
  /// This is NOT the normal match-completion flow.
  Future<void> retryFinishPersistence() async {
    final currentSession = _session;

    if (currentSession == null) {
      _setError('لا توجد جلسة مباراة نشطة.');
      return;
    }

    if (!currentSession.isFinished) {
      _setError('لا يمكن إعادة حفظ النتيجة قبل انتهاء اللعبة.');
      return;
    }

    if (_matchStatus == MatchStatus.finished) {
      return;
    }

    await _completeFinishedMatch();
  }

  // ============================================================
  // RESET
  // ============================================================

  /// Clears runtime/UI state.
  ///
  /// Does NOT delete the Match from the database.
  void reset() {
    _session = null;

    _matchStatus = null;

    _completedPlayers.clear();

    _selectedTokenId = null;

    _selectedRollSequence = null;

    _error = null;

    _isLoading = false;
    _pendingAutoMove = null;
    _isAutoMoveExecuting = false;

    _isSavingSnapshot = false;
    _snapshotSaveFailed = false;

    notifyListeners();
  }

  // ============================================================
  // ERROR
  // ============================================================

  void clearError() {
    if (_error == null) {
      return;
    }

    _error = null;

    notifyListeners();
  }

  // ============================================================
  // INTERNAL HELPERS
  // ============================================================

  void _setLoading(bool value) {
    _isLoading = value;

    notifyListeners();
  }

  void _setError(String message) {
    _error = message;

    notifyListeners();
  }

  void _playSounds(List<GameSound> list) {
    final player = sounds;
    if (player == null) return;
    // Follow-up sounds (six, cancelled) wait for the dice rattle to end.
    for (var i = 0; i < list.length; i++) {
      final sound = list[i];
      if (i == 0) {
        player.play(sound);
      } else {
        late final Timer timer;
        timer = Timer(Duration(milliseconds: 420 * i), () {
          _soundTimers.remove(timer);
          if (!_disposed) player.play(sound);
        });
        _soundTimers.add(timer);
      }
    }
  }

  /// Offers [move] as the automatic move after [autoMoveDelay], so the
  /// players see the dice/board first. Skipped if the page closed, the
  /// state changed, or the player already moved by hand.
  Future<void> _offerAutoMoveAfterDelay(
    MatchGameSession session,
    LudoGameState expectedState,
    MoveOption move,
  ) async {
    await Future<void>.delayed(autoMoveDelay);
    if (!_disposed &&
        identical(_session, session) &&
        identical(session.engine.state, expectedState) &&
        _pendingAutoMove == null &&
        !isSnapshotSaveBlocked) {
      _pendingAutoMove = move;
      notifyListeners();
    }
  }

  Future<void> _trackSave(Future<void> save) {
    _pendingSave = save;
    return save;
  }

  void _showRollNoticeIfTurnPassed(
    LudoGameState before,
    MatchGameSession session,
  ) {
    final after = session.engine.state;
    final value = session.engine.lastRolledValue;
    if (value == null ||
        after.isFinished ||
        after.currentPlayerIndex == before.currentPlayerIndex) {
      return;
    }

    final roller = before.players[before.currentPlayerIndex];
    _rollNotice = RollNotice(
      playerId: roller.playerId,
      playerName: roller.name,
      value: value,
      turnCancelled: before.turnState.sixRollCount >= 2,
    );

    _rollNoticeTimer?.cancel();
    _rollNoticeTimer = Timer(rollNoticeDuration, () {
      if (_disposed) return;
      _rollNotice = null;
      notifyListeners();
    });
  }
}

/// A roll that ended the turn without a move, shown briefly to the players.
@immutable
class RollNotice {
  final String playerId;
  final String playerName;
  final int value;

  /// True when this was the third six (the whole turn is cancelled).
  final bool turnCancelled;

  const RollNotice({
    required this.playerId,
    required this.playerName,
    required this.value,
    required this.turnCancelled,
  });
}
