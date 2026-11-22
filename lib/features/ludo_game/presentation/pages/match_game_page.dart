import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ludo_rank/shared/widgets/sound_toggle_button.dart';

import 'package:ludo_rank/core/dependency_injection/injection_container.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_player.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_token.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/move_option.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/ludo_game_result_overlay.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/ludo_match_board.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/ludo_match_player_section.dart';
import 'package:ludo_rank/features/matches/presentation/providers/match_game_provider.dart';
import 'package:ludo_rank/features/match_players/domain/entities/match_player.dart';
import 'dart:async';

import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/match_die_face.dart';
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
        ..showSnackBar(SnackBar(content: Text('تعذر إلغاء المباراة: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MatchGameProvider>.value(
      value: provider,
      child: Consumer<MatchGameProvider>(
        builder: (context, gameProvider, _) {
          return PopScope<Object?>(
            canPop: _canPopFreely,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _handleBack();
            },
            child: Scaffold(
              appBar: AppBar(
                toolbarHeight: 48,
                centerTitle: true,
                title: const Text(
                  'LudoRank',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                leading: IconButton(
                  onPressed: gameProvider.isLoading || _leaving
                      ? null
                      : _handleBack,
                  tooltip: 'رجوع',
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                actions: <Widget>[
                  if (gameProvider.isGameFinished && !gameProvider.isFinished)
                    IconButton(
                      onPressed: gameProvider.isLoading
                          ? null
                          : gameProvider.retryFinishPersistence,
                      tooltip: 'إعادة حفظ النتيجة',
                      icon: const Icon(Icons.sync),
                    )
                  else
                    const SoundToggleButton(),
                ],
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
                      provider: gameProvider,
                      onTokenTap: _onTokenTap,
                      onMove: _executeMove,
                    ),
                    if (gameProvider.rollNotice != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Center(
                            child: _RollNoticeBanner(
                              notice: gameProvider.rollNotice!,
                            ),
                          ),
                        ),
                      ),
                    if (gameProvider.error != null)
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 8,
                        child: _ErrorBanner(
                          message: gameProvider.error!,
                          onClose: gameProvider.clearError,
                        ),
                      ),
                    if (gameProvider.isGameFinished)
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: gameProvider.isLoading,
                          child: LudoGameResultOverlay(
                            players: gameProvider.completedPlayers,
                            playerNames: widget.playerNames,
                            isSaved: gameProvider.isFinished,
                            isLoading: gameProvider.isLoading,
                            onRetry: gameProvider.retryFinishPersistence,
                            onClose: gameProvider.isFinished
                                ? () => Navigator.pop(context, true)
                                : null,
                            gameResult: gameProvider.result,
                            matchPlayers:
                                gameProvider.session?.matchPlayers ??
                                const <MatchPlayer>[],
                            gamePlayers: gameProvider.players,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LiveMatchLayout extends StatelessWidget {
  final MatchGameProvider provider;
  final ValueChanged<LudoToken> onTokenTap;
  final Future<void> Function(MoveOption) onMove;
  const _LiveMatchLayout({
    required this.provider,
    required this.onTokenTap,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    final players = provider.players;
    final currentPlayer = provider.currentPlayer;

    if (players.isEmpty || currentPlayer == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            provider.error ?? 'جارٍ تحميل المباراة...',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }
    final playersByColor = <LudoPlayerColor, LudoPlayer>{
      for (final player in players) player.color: player,
    };

    final green = playersByColor[LudoPlayerColor.green];
    final yellow = playersByColor[LudoPlayerColor.yellow];
    final red = playersByColor[LudoPlayerColor.red];
    final blue = playersByColor[LudoPlayerColor.blue];

    return LayoutBuilder(
      builder: (context, constraints) {
        final shortScreen = constraints.maxHeight < 630;
        final activeCardHeight = shortScreen ? 110.0 : 126.0;
        final inactiveCardHeight = shortScreen ? 34.0 : 42.0;
        final rowGap = shortScreen ? 4.0 : 6.0;
        final sidePadding = constraints.maxWidth < 360 ? 8.0 : 12.0;

        final topHasPlayers = green != null || yellow != null;
        final bottomHasPlayers = red != null || blue != null;

        final topHeight = topHasPlayers ? activeCardHeight : 0.0;
        final bottomHeight = bottomHasPlayers ? activeCardHeight : 0.0;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: EdgeInsets.fromLTRB(sidePadding, 5, sidePadding, 5),
              child: Column(
                children: <Widget>[
                  if (topHeight > 0) ...<Widget>[
                    SizedBox(
                      height: topHeight,
                      child: _buildHomeSideRow(
                        left: green,
                        right: yellow,
                        currentPlayer: currentPlayer,
                        activeCardHeight: activeCardHeight,
                        inactiveCardHeight: inactiveCardHeight,
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
                            child: LudoMatchBoard(
                              players: players,
                              currentPlayerId: currentPlayer.playerId,
                              availableMoves: provider.availableMoves,
                              selectedTokenId: provider.selectedTokenId,
                              selectedRollSequence:
                                  provider.selectedRollSequence,
                              pendingAutoMove: provider.isSnapshotSaveBlocked
                                  ? null
                                  : provider.pendingAutoMove,
                              onTokenTap: onTokenTap,
                              legalMoveDestinations:
                                  provider.selectedMoveDestinations,
                              rollValueForMove: provider.rollValueForMove,
                              onMoveTap: onMove,

                              // الرميات التي تناسب التوكن المحدد فقط.
                              selectableRolls: provider.selectableRolls,
                              onAvailableRollTap:
                                  provider.handleAvailableRollTap,
                              sounds: provider.sounds,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (bottomHeight > 0) ...<Widget>[
                    SizedBox(height: rowGap),
                    SizedBox(
                      height: bottomHeight,
                      child: _buildHomeSideRow(
                        left: red,
                        right: blue,
                        currentPlayer: currentPlayer,
                        activeCardHeight: activeCardHeight,
                        inactiveCardHeight: inactiveCardHeight,
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
  Widget _buildHomeSideRow({
    required LudoPlayer? left,
    required LudoPlayer? right,
    required LudoPlayer currentPlayer,
    required double activeCardHeight,
    required double inactiveCardHeight,
  }) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: <Widget>[
          Expanded(
            child: _buildPlayerSlot(
              left,
              currentPlayer,
              activeCardHeight,
              inactiveCardHeight,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: _buildPlayerSlot(
              right,
              currentPlayer,
              activeCardHeight,
              inactiveCardHeight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerSlot(
    LudoPlayer? player,
    LudoPlayer currentPlayer,
    double activeCardHeight,
    double inactiveCardHeight,
  ) {
    if (player == null) return const SizedBox.shrink();

    final isCurrent = player.playerId == currentPlayer.playerId;

    return Align(
      alignment: Alignment.center,
      child: SizedBox(
        width: double.infinity,
        height: isCurrent ? activeCardHeight : inactiveCardHeight,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: LudoMatchPlayerSection(
            player: player,
            isCurrent: isCurrent,
            turnState: provider.turnState,
            availableRolls: isCurrent
                ? provider.availableRolls
                : provider.availableRolls.clear(),
            canRoll: isCurrent && provider.canRollDice,
            onRoll: () {
              unawaited(provider.rollDice());
            },
            height: isCurrent ? activeCardHeight : inactiveCardHeight,
            onAvailableRollTap: provider.handleAvailableRollTap,
            selectedRollSequence: provider.selectedRollSequence,
          ),
        ),
      ),
    );
  }
}

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
