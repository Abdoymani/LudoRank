import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ludo_rank/shared/widgets/sound_toggle_button.dart';

import 'package:ludo_rank/core/dependency_injection/injection_container.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_player.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_token.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/position.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/available_rolls.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/turn_state.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/move_option.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/ludo_game_result_overlay.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/ludo_match_board.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/ludo_match_player_section.dart';
import 'package:ludo_rank/features/matches/presentation/providers/match_game_provider.dart';
import 'package:ludo_rank/features/match_players/domain/entities/match_player.dart';
import 'dart:async';

import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/match_die_face.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/match_seat_layout.dart';
import 'package:ludo_rank/features/matches/domain/Use-cases/cancel_match.dart';

class MatchGamePage extends StatefulWidget {
  /// Database match ID.
  final String matchId;

  /// Key = playerId, value = name.
  final Map<String, String> playerNames;
  final bool resumeExisting;

  const MatchGamePage({
    super.key,
    required this.matchId,
    required this.playerNames,
    this.resumeExisting = false,
  });

  @override
  State<MatchGamePage> createState() => _MatchGamePageState();
}

class _MatchGamePageState extends State<MatchGamePage> {
  /// Largest text scale used inside the match screen.
  static const double maxTextScale = 1.3;

  late final MatchGameProvider provider;

  @override
  void initState() {
    super.initState();

    provider = sl<MatchGameProvider>();

    if (widget.resumeExisting) {
      provider.resumeMatch(matchId: widget.matchId);
    } else {
      provider.startMatch(
        matchId: widget.matchId,
        playerNames: widget.playerNames,
      );
    }
  }

  @override
  void dispose() {
    provider.dispose();
    super.dispose();
  }

  Future<void> _onTokenTap(LudoToken token) async {
    await provider.handleTokenTap(token);
  }

  Future<void> _executeMove(MoveOption move) async {
    await provider.executeMove(move);
  }

  bool _leaving = false;

  bool get _canPopFreely => provider.isGameFinished && provider.isFinished;

  /// Back arrow and Android back both land here: the player chooses to keep
  /// playing, pause (the match is saved after every roll and move and can be
  /// resumed from the tournament's match list), or cancel the match.
  Future<void> _handleBack() async {
    if (_leaving) return;

    if (_canPopFreely) {
      if (mounted) Navigator.pop(context, true);
      return;
    }

    // Nothing started (e.g. loading failed): just leave.
    if (provider.session == null || provider.isGameFinished) {
      if (mounted) Navigator.pop(context, true);
      return;
    }

    final choice = await showModalBottomSheet<_LeaveChoice>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) =>
          _LeaveMatchSheet(saveFailed: provider.hasSnapshotSaveError),
    );

    if (!mounted || choice == null || choice == _LeaveChoice.stay) return;

    if (choice == _LeaveChoice.pause) {
      await _leave(cancel: false);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إلغاء المباراة نهائيًا؟'),
        content: const Text(
          'لن تُحسب هذه المباراة في ترتيب البطولة، ولن يمكن استكمالها بعد الإلغاء.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('إلغاء المباراة'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) await _leave(cancel: true);
  }

  Future<void> _leave({required bool cancel}) async {
    setState(() => _leaving = true);
    try {
      // Let the last roll/move finish saving so nothing is written after
      // the player left (or after the match was cancelled).
      await provider.waitForPendingSave();
      if (cancel) await sl<CancelMatch>()(widget.matchId);
      if (!mounted) return;

      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.pop(context, true);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              cancel
                  ? 'تم إلغاء المباراة.'
                  : 'تم حفظ المباراة. تقدر تكملها من قائمة المباريات بزر "استكمال".',
            ),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      setState(() => _leaving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              cancel ? 'تعذر إلغاء المباراة: $e' : 'تعذر إيقاف المباراة: $e',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // No Consumer around the page: each part below listens to just the
    // values it shows (context.select), so a roll or a move rebuilds the
    // card and the board that changed, not the whole Scaffold.
    return ChangeNotifierProvider<MatchGameProvider>.value(
      value: provider,
      // A bigger system font is honoured up to 1.3x here: beyond that the
      // cards would eat the board on a phone.
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: maxTextScale,
        child: _MatchPopGuard(
          onBack: _handleBack,
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: 48,
              centerTitle: true,
              title: const Text(
                'LudoRank',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              leading: _BackButton(leaving: _leaving, onBack: _handleBack),
              actions: const <Widget>[_AppBarAction()],
              bottom: const PreferredSize(
                preferredSize: Size.fromHeight(1),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFF51465E),
                ),
              ),
            ),
            body: SafeArea(
              top: false,
              child: Stack(
                children: <Widget>[
                  _LiveMatchLayout(
                    onTokenTap: _onTokenTap,
                    onMove: _executeMove,
                  ),
                  const _RollNoticeLayer(),
                  const _ErrorLayer(),
                  _ResultLayer(
                    playerNames: widget.playerNames,
                    onClose: () => Navigator.pop(context, true),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MatchPopGuard extends StatelessWidget {
  final VoidCallback onBack;
  final Widget child;

  const _MatchPopGuard({required this.onBack, required this.child});

  @override
  Widget build(BuildContext context) {
    final canPop = context.select<MatchGameProvider, bool>(
      (p) => p.isGameFinished && p.isFinished,
    );
    return PopScope<Object?>(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack();
      },
      child: child,
    );
  }
}

class _BackButton extends StatelessWidget {
  final bool leaving;
  final VoidCallback onBack;

  const _BackButton({required this.leaving, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final loading = context.select<MatchGameProvider, bool>((p) => p.isLoading);
    return IconButton(
      onPressed: loading || leaving ? null : onBack,
      tooltip: 'رجوع',
      icon: const Icon(Icons.arrow_back_rounded),
    );
  }
}

class _AppBarAction extends StatelessWidget {
  const _AppBarAction();

  @override
  Widget build(BuildContext context) {
    final (needsRetry, loading) = context
        .select<MatchGameProvider, (bool, bool)>(
          (p) => (p.isGameFinished && !p.isFinished, p.isLoading),
        );
    if (!needsRetry) return const SoundToggleButton();
    return IconButton(
      onPressed: loading
          ? null
          : context.read<MatchGameProvider>().retryFinishPersistence,
      tooltip: 'إعادة حفظ النتيجة',
      icon: const Icon(Icons.sync),
    );
  }
}

class _RollNoticeLayer extends StatelessWidget {
  const _RollNoticeLayer();

  @override
  Widget build(BuildContext context) {
    final notice = context.select<MatchGameProvider, RollNotice?>(
      (p) => p.rollNotice,
    );
    if (notice == null) return const SizedBox.shrink();

    // A notice about a top-row player's roll faces that player.
    var facesFarSide = false;
    for (final player in context.read<MatchGameProvider>().players) {
      if (player.playerId == notice.playerId) {
        facesFarSide = MatchSeatLayout.facesFarSide(player.color);
      }
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: RotatedBox(
            quarterTurns: facesFarSide ? 2 : 0,
            child: _RollNoticeBanner(notice: notice),
          ),
        ),
      ),
    );
  }
}

class _ErrorLayer extends StatelessWidget {
  const _ErrorLayer();

  @override
  Widget build(BuildContext context) {
    final error = context.select<MatchGameProvider, String?>((p) => p.error);
    if (error == null) return const SizedBox.shrink();
    return Positioned(
      left: 10,
      right: 10,
      bottom: 8,
      child: _ErrorBanner(
        message: error,
        onClose: context.read<MatchGameProvider>().clearError,
      ),
    );
  }
}

class _ResultLayer extends StatelessWidget {
  final Map<String, String> playerNames;
  final VoidCallback onClose;

  const _ResultLayer({required this.playerNames, required this.onClose});

  @override
  Widget build(BuildContext context) {
    // completedPlayers is filled exactly when the match becomes finished,
    // so the status flags are enough to know when to rebuild.
    final (finished, saved, loading) = context
        .select<MatchGameProvider, (bool, bool, bool)>(
          (p) => (p.isGameFinished, p.isFinished, p.isLoading),
        );
    if (!finished) return const SizedBox.shrink();

    final provider = context.read<MatchGameProvider>();
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: loading,
        child: LudoGameResultOverlay(
          players: provider.completedPlayers,
          playerNames: playerNames,
          isSaved: saved,
          isLoading: loading,
          onRetry: provider.retryFinishPersistence,
          onClose: saved ? onClose : null,
          gameResult: provider.result,
          matchPlayers: provider.session?.matchPlayers ?? const <MatchPlayer>[],
          gamePlayers: provider.players,
          sounds: provider.sounds,
        ),
      ),
    );
  }
}

class _LiveMatchLayout extends StatelessWidget {
  final ValueChanged<LudoToken> onTokenTap;
  final Future<void> Function(MoveOption) onMove;

  const _LiveMatchLayout({required this.onTokenTap, required this.onMove});

  @override
  Widget build(BuildContext context) {
    // Only the seating changes this layout: which colours play, and
    // whether the match is loaded. Turns and moves rebuild the parts.
    final (loaded, error, colors) = context
        .select<MatchGameProvider, (bool, String?, String)>(
          (p) => (
            p.players.isNotEmpty && p.currentPlayer != null,
            p.players.isEmpty ? p.error : null,
            p.players.map((player) => player.color.name).join(','),
          ),
        );

    if (!loaded) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            error ?? 'جارٍ تحميل المباراة...',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    bool plays(LudoPlayerColor color) => colors.split(',').contains(color.name);

    return LayoutBuilder(
      builder: (context, constraints) {
        final shortScreen = constraints.maxHeight < 630;
        // Card heights follow the (clamped) text size instead of fixed
        // numbers, so a bigger font never pushes text out of a card.
        final textScaler = MediaQuery.textScalerOf(context);
        final heights = (
          active: LudoMatchPlayerSection.activeHeightFor(textScaler),
          inactive: LudoMatchPlayerSection.inactiveHeightFor(textScaler),
        );
        final rowGap = shortScreen ? 4.0 : 6.0;
        final sidePadding = constraints.maxWidth < 360 ? 8.0 : 12.0;

        final topHasPlayers = MatchSeatLayout.topRow.any(plays);
        final bottomHasPlayers = MatchSeatLayout.bottomRow.any(plays);

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: EdgeInsets.fromLTRB(sidePadding, 5, sidePadding, 5),
              child: Column(
                children: <Widget>[
                  if (topHasPlayers) ...<Widget>[
                    SizedBox(
                      height: heights.active,
                      child: _buildHomeSideRow(
                        colors: MatchSeatLayout.topRow,
                        facesFarSide: true,
                        plays: plays,
                        activeHeight: heights.active,
                        inactiveHeight: heights.inactive,
                      ),
                    ),
                    SizedBox(height: rowGap),
                  ],
                  Expanded(
                    child: Center(
                      child: LayoutBuilder(
                        builder: (context, boardConstraints) {
                          final side =
                              boardConstraints.maxWidth <
                                  boardConstraints.maxHeight
                              ? boardConstraints.maxWidth
                              : boardConstraints.maxHeight;

                          return SizedBox.square(
                            dimension: side,
                            child: _BoardSlot(
                              onTokenTap: onTokenTap,
                              onMove: onMove,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (bottomHasPlayers) ...<Widget>[
                    SizedBox(height: rowGap),
                    SizedBox(
                      height: heights.active,
                      child: _buildHomeSideRow(
                        colors: MatchSeatLayout.bottomRow,
                        facesFarSide: false,
                        plays: plays,
                        activeHeight: heights.active,
                        inactiveHeight: heights.inactive,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// The two slots follow the physical homes and never reorder the colors.
  /// LTR slots preserve green/yellow and red/blue board-side positioning;
  /// each player's own contents stay RTL Arabic.
  ///
  /// [facesFarSide] is the row above the board: its cards are turned 180°
  /// so those players read them from their side ([MatchSeatLayout]).
  Widget _buildHomeSideRow({
    required List<LudoPlayerColor> colors,
    required bool facesFarSide,
    required bool Function(LudoPlayerColor) plays,
    required double activeHeight,
    required double inactiveHeight,
  }) {
    Widget slot(LudoPlayerColor color) {
      if (!plays(color)) return const SizedBox.shrink();
      return _PlayerSlot(
        color: color,
        facesFarSide: facesFarSide,
        activeHeight: activeHeight,
        inactiveHeight: inactiveHeight,
      );
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: <Widget>[
          Expanded(child: slot(colors[0])),
          const SizedBox(width: 7),
          Expanded(child: slot(colors[1])),
        ],
      ),
    );
  }
}

/// One player's card. Rebuilds only when what this card shows changes:
/// a waiting player's card ignores the other players' rolls and moves.
class _PlayerSlot extends StatelessWidget {
  final LudoPlayerColor color;
  final bool facesFarSide;
  final double activeHeight;
  final double inactiveHeight;

  const _PlayerSlot({
    required this.color,
    required this.facesFarSide,
    required this.activeHeight,
    required this.inactiveHeight,
  });

  @override
  Widget build(BuildContext context) {
    final card = context.select<MatchGameProvider, _CardData?>((p) {
      LudoPlayer? player;
      for (final candidate in p.players) {
        if (candidate.color == color) player = candidate;
      }
      if (player == null) return null;

      // While the die tumbles, the roller's card stays the active one with
      // their pre-roll turn, even if the roll already passed the turn.
      final dice = p.diceRoll;
      final shownCurrent = dice?.playerId ?? p.currentPlayerId;
      final isCurrent = player.playerId == shownCurrent;
      if (!isCurrent) return _CardData.waiting(player);

      if (dice != null) {
        return _CardData(
          player: player,
          isCurrent: true,
          turnState: dice.turnStateBefore,
          availableRolls: const AvailableRolls(),
          canRoll: false,
          selectedRollSequence: null,
          dice: dice,
        );
      }

      return _CardData(
        player: player,
        isCurrent: true,
        turnState: p.turnState,
        availableRolls: p.availableRolls,
        canRoll: p.canRollDice,
        selectedRollSequence: p.selectedRollSequence,
      );
    });
    if (card == null) return const SizedBox.shrink();

    final provider = context.read<MatchGameProvider>();
    final height = card.isCurrent ? activeHeight : inactiveHeight;

    // A card that grows or shrinks with the turn stays against the board.
    return Align(
      alignment: facesFarSide ? Alignment.bottomCenter : Alignment.topCenter,
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: RotatedBox(
          quarterTurns: facesFarSide ? 2 : 0,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: LudoMatchPlayerSection(
              player: card.player,
              isCurrent: card.isCurrent,
              turnState: card.turnState,
              availableRolls: card.availableRolls,
              canRoll: card.canRoll,
              onRoll: () {
                unawaited(provider.rollDice());
              },
              height: height,
              onAvailableRollTap: provider.handleAvailableRollTap,
              selectedRollSequence: card.selectedRollSequence,
              rollingDie: switch (card.dice) {
                final dice? => (
                  id: dice.id,
                  value: dice.value,
                  duration: dice.duration,
                ),
                null => null,
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// What one card shows; equal data means the card does not rebuild.
@immutable
class _CardData {
  final LudoPlayer player;
  final bool isCurrent;
  final TurnState? turnState;
  final AvailableRolls availableRolls;
  final bool canRoll;
  final int? selectedRollSequence;
  final DiceRollAnimation? dice;

  const _CardData({
    required this.player,
    required this.isCurrent,
    required this.turnState,
    required this.availableRolls,
    required this.canRoll,
    required this.selectedRollSequence,
    this.dice,
  });

  const _CardData.waiting(this.player)
    : isCurrent = false,
      turnState = null,
      availableRolls = const AvailableRolls(),
      canRoll = false,
      selectedRollSequence = null,
      dice = null;

  @override
  bool operator ==(Object other) =>
      other is _CardData &&
      other.player == player &&
      other.isCurrent == isCurrent &&
      other.turnState == turnState &&
      other.availableRolls == availableRolls &&
      other.canRoll == canRoll &&
      other.selectedRollSequence == selectedRollSequence &&
      other.dice == dice;

  @override
  int get hashCode => Object.hash(
    player,
    isCurrent,
    turnState,
    availableRolls,
    canRoll,
    selectedRollSequence,
    dice,
  );
}

/// The board, rebuilt only when what it draws or accepts changes.
class _BoardSlot extends StatelessWidget {
  final ValueChanged<LudoToken> onTokenTap;
  final Future<void> Function(MoveOption) onMove;

  const _BoardSlot({required this.onTokenTap, required this.onMove});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<MatchGameProvider>();
    final board = context.select<MatchGameProvider, _BoardData>(
      (p) => (
        players: p.players,
        currentPlayerId: p.currentPlayerId,
        moves: p.availableMoves,
        selectedTokenId: p.selectedTokenId,
        selectedRoll: p.selectedRollSequence,
        pending: p.isSnapshotSaveBlocked ? null : p.pendingAutoMove,
        destinations: p.selectedMoveDestinations,
        selectableRolls: p.selectableRolls,
        diceRolling: p.isDiceRolling,
      ),
    );

    return LudoMatchBoard(
      players: board.players,
      currentPlayerId: board.currentPlayerId,
      availableMoves: board.moves,
      selectedTokenId: board.selectedTokenId,
      selectedRollSequence: board.selectedRoll,
      pendingAutoMove: board.pending,
      onTokenTap: onTokenTap,
      legalMoveDestinations: board.destinations,
      rollValueForMove: provider.rollValueForMove,
      onMoveTap: onMove,
      // الرميات التي تناسب التوكن المحدد فقط.
      selectableRolls: board.selectableRolls,
      onAvailableRollTap: provider.handleAvailableRollTap,
      sounds: provider.sounds,
      inputLocked: board.diceRolling,
      onAnimatingChanged: provider.setBoardAnimating,
    );
  }
}

/// What the board shows; records compare field by field (lists by
/// identity, which the provider keeps stable per engine state).
typedef _BoardData = ({
  List<LudoPlayer> players,
  String? currentPlayerId,
  List<MoveOption> moves,
  String? selectedTokenId,
  int? selectedRoll,
  MoveOption? pending,
  Map<Position, List<MoveOption>> destinations,
  AvailableRolls selectableRolls,
  bool diceRolling,
});

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onClose;

  const _ErrorBanner({required this.message, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close),
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ],
        ),
      ),
    );
  }
}

enum _LeaveChoice { stay, pause, cancel }

class _LeaveMatchSheet extends StatelessWidget {
  final bool saveFailed;

  const _LeaveMatchSheet({required this.saveFailed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'الخروج من المباراة',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              saveFailed
                  ? 'تنبيه: آخر حركة لم تُحفظ. لو خرجت، المباراة هتكمل من آخر حالة محفوظة.'
                  : 'المباراة محفوظة بعد كل رمية وحركة.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: saveFailed ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, _LeaveChoice.stay),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('كمّل اللعب'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, _LeaveChoice.pause),
              icon: const Icon(Icons.pause_rounded),
              label: const Text('إيقاف مؤقت والخروج (تكملها بعدين)'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              onPressed: () => Navigator.pop(context, _LeaveChoice.cancel),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('إلغاء المباراة نهائيًا'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows a roll that ended the turn without a move, so players see what
/// was rolled before the next player's card takes over.
class _RollNoticeBanner extends StatelessWidget {
  final RollNotice notice;

  const _RollNoticeBanner({required this.notice});

  @override
  Widget build(BuildContext context) {
    final message = notice.turnCancelled
        ? 'تالت 6 في نفس الدور: الدور اتلغى'
        : 'مفيش حركة متاحة';

    return Material(
      elevation: 10,
      color: const Color(0xEE1B1524),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            MatchDieFace(value: notice.value, size: 40),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  notice.playerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
