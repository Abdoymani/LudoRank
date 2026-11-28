import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ludo_rank/core/audio/game_sound.dart';
import 'package:ludo_rank/core/audio/sound_controller.dart';

import 'package:ludo_rank/features/match_players/domain/entities/match_player.dart';

import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_player.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/game_result.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/match_ui_colors.dart';

/// The final result. It enters with a fade and a scale, then the ranks
/// appear one after the other, each with a short reveal sound.
class LudoGameResultOverlay extends StatefulWidget {
  final List<MatchPlayer> players;
  final Map<String, String> playerNames;
  final bool isSaved;
  final bool isLoading;

  final VoidCallback onRetry;
  final VoidCallback? onClose;

  final GameResult? gameResult;
  final List<MatchPlayer> matchPlayers;

  // لاعبو المحرك، لاستخراج اللون الحقيقي لكل لاعب.
  final List<LudoPlayer> gamePlayers;

  /// Plays the reveal sound for each rank. Null: silent.
  final GameSoundPlayer? sounds;

  /// The card's fade + scale.
  static const Duration entranceDuration = Duration(milliseconds: 380);

  /// Time between two ranks appearing.
  static const Duration rankStagger = Duration(milliseconds: 160);

  /// How long one rank takes to appear.
  static const Duration rankDuration = Duration(milliseconds: 260);

  const LudoGameResultOverlay({
    super.key,
    required this.players,
    this.playerNames = const <String, String>{},
    required this.isSaved,
    required this.isLoading,
    required this.onRetry,
    required this.onClose,
    this.gameResult,
    this.matchPlayers = const <MatchPlayer>[],
    this.gamePlayers = const <LudoPlayer>[],
    this.sounds,
  });

  @override
  State<LudoGameResultOverlay> createState() => _LudoGameResultOverlayState();
}

class _LudoGameResultOverlayState extends State<LudoGameResultOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final int _rows;
  int _soundsPlayed = 0;

  @override
  void initState() {
    super.initState();
    _rows = math.max(
      widget.players.length,
      widget.gameResult?.players.length ?? 0,
    );
    final total =
        LudoGameResultOverlay.entranceDuration +
        LudoGameResultOverlay.rankStagger * math.max(0, _rows - 1) +
        LudoGameResultOverlay.rankDuration;
    _controller = AnimationController(vsync: this, duration: total)
      ..addListener(_playRankSounds)
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _totalMs => _controller.duration!.inMicroseconds / 1000;

  /// Where rank [index] starts appearing, as a fraction of the animation.
  double _rankStart(int index) {
    final ms =
        LudoGameResultOverlay.entranceDuration.inMilliseconds * .7 +
        LudoGameResultOverlay.rankStagger.inMilliseconds * index;
    return (ms / _totalMs).clamp(0.0, 1.0);
  }

  void _playRankSounds() {
    while (_soundsPlayed < _rows &&
        _controller.value >= _rankStart(_soundsPlayed)) {
      _soundsPlayed++;
      widget.sounds?.play(GameSound.reveal);
    }
  }

  /// The animation of rank [index] (0 = first place).
  Animation<double> _rankAnimation(int index) {
    final start = _rankStart(index);
    final end =
        (start + LudoGameResultOverlay.rankDuration.inMilliseconds / _totalMs)
            .clamp(start, 1.0);
    return CurvedAnimation(
      parent: _controller,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
  }

  Widget _reveal(int index, Widget child) {
    final animation = _rankAnimation(index);
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .35),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final players = widget.players;
    final playerNames = widget.playerNames;
    final isSaved = widget.isSaved;
    final isLoading = widget.isLoading;
    final onRetry = widget.onRetry;
    final onClose = widget.onClose;
    final gameResult = widget.gameResult;
    final matchPlayers = widget.matchPlayers;
    final gamePlayers = widget.gamePlayers;

    final sortedPlayers = [...players]
      ..sort((a, b) => (a.rank ?? 999).compareTo(b.rank ?? 999));

    // ربط معرف اللاعب بلونه الفعلي في اللعبة.
    final playerColors = <String, Color>{
      for (final player in gamePlayers)
        player.playerId: matchUiColorFor(player.color),
    };

    final entranceEnd =
        (LudoGameResultOverlay.entranceDuration.inMilliseconds / _totalMs)
            .clamp(0.0, 1.0);
    final entrance = CurvedAnimation(
      parent: _controller,
      curve: Interval(0, entranceEnd, curve: Curves.easeOut),
    );
    final pop = CurvedAnimation(
      parent: _controller,
      curve: Interval(0, entranceEnd, curve: Curves.easeOutBack),
    );

    return FadeTransition(
      opacity: entrance,
      child: Material(
        color: Colors.black.withValues(alpha: 0.58),
        child: Center(
          child: ScaleTransition(
            scale: Tween<double>(begin: .86, end: 1).animate(pop),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                margin: const EdgeInsets.all(20),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSaved ? Icons.emoji_events : Icons.warning_amber,
                        size: 56,
                        color: isSaved
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.error,
                      ),

                      const SizedBox(height: 10),

                      Text(
                        isSaved ? 'انتهت المباراة' : 'انتهت اللعبة',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 6),

                      Text(
                        isSaved
                            ? 'تم حفظ ترتيب اللاعبين والنقاط.'
                            : 'اللعبة انتهت، لكن لم يتم حفظ النتيجة في قاعدة البيانات بعد.',
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 18),

                      if (sortedPlayers.isNotEmpty)
                        _ResultsList(
                          players: sortedPlayers,
                          playerNames: playerNames,
                          playerColors: playerColors,
                          reveal: _reveal,
                        )
                      else if (gameResult != null)
                        _EngineResultsList(
                          gameResult: gameResult,
                          matchPlayers: matchPlayers,
                          playerNames: playerNames,
                          playerColors: playerColors,
                          reveal: _reveal,
                        ),

                      const SizedBox(height: 18),

                      if (!isSaved)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: isLoading ? null : onRetry,
                            icon: isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.sync),
                            label: Text(
                              isLoading
                                  ? 'جاري إعادة الحفظ...'
                                  : 'إعادة حفظ النتيجة',
                            ),
                          ),
                        ),

                      if (isSaved && onClose != null)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: onClose,
                            child: const Text('العودة'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps rank [index]'s row in its reveal animation.
typedef _RankReveal = Widget Function(int index, Widget child);

// ==================================================================
// RESULTS
// ==================================================================

class _ResultsList extends StatelessWidget {
  final List<MatchPlayer> players;
  final Map<String, String> playerNames;
  final Map<String, Color> playerColors;
  final _RankReveal reveal;

  const _ResultsList({
    required this.players,
    required this.playerNames,
    required this.playerColors,
    required this.reveal,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < players.length; index++)
          reveal(
            index,
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ResultRow(
                player: players[index],
                displayName:
                    playerNames[players[index].playerId] ??
                    'اللاعب ${players[index].seat}',
                color: playerColors[players[index].playerId],
              ),
            ),
          ),
      ],
    );
  }
}

// ==================================================================
// RESULT ROW
// ==================================================================

class _ResultRow extends StatelessWidget {
  final MatchPlayer player;
  final String displayName;
  final Color? color;

  const _ResultRow({
    required this.player,
    required this.displayName,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final playerColor = color ?? Colors.grey;
    final isYellow = playerColor == const Color(0xFFF7BE00);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: playerColor.withValues(alpha: 0.09),
        border: Border.all(
          color: playerColor.withValues(alpha: 0.65),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: playerColor,
            foregroundColor: isYellow ? const Color(0xFF21182B) : Colors.white,
            child: Text(
              '${player.rank ?? "-"}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Text(
              displayName,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          Text(
            '${player.points} نقطة',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: playerColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================================================================
// ENGINE RESULTS
// ==================================================================

class _EngineResultsList extends StatelessWidget {
  final GameResult gameResult;
  final List<MatchPlayer> matchPlayers;
  final Map<String, String> playerNames;
  final Map<String, Color> playerColors;
  final _RankReveal reveal;

  const _EngineResultsList({
    required this.gameResult,
    required this.matchPlayers,
    required this.playerNames,
    required this.playerColors,
    required this.reveal,
  });

  @override
  Widget build(BuildContext context) {
    final results = [...gameResult.players]
      ..sort((a, b) => a.rank.compareTo(b.rank));

    return Column(
      children: [
        for (var index = 0; index < results.length; index++)
          reveal(
            index,
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _EngineResultRow(
                rank: results[index].rank,
                displayName:
                    playerNames[results[index].playerId] ??
                    _fallbackName(results[index].playerId),
                color: playerColors[results[index].playerId],
              ),
            ),
          ),
      ],
    );
  }

  String _fallbackName(String playerId) {
    for (final player in matchPlayers) {
      if (player.playerId == playerId) {
        return 'اللاعب ${player.seat}';
      }
    }

    return 'لاعب';
  }
}

// ==================================================================
// ENGINE RESULT ROW
// ==================================================================

class _EngineResultRow extends StatelessWidget {
  final int rank;
  final String displayName;
  final Color? color;

  const _EngineResultRow({
    required this.rank,
    required this.displayName,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final playerColor = color ?? Colors.grey;
    final isYellow = playerColor == const Color(0xFFF7BE00);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: playerColor.withValues(alpha: 0.09),
        border: Border.all(
          color: playerColor.withValues(alpha: 0.65),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: playerColor,
            foregroundColor: isYellow ? const Color(0xFF21182B) : Colors.white,
            child: Text(
              '$rank',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Text(
              displayName,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
