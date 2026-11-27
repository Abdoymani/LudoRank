import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ludo_rank/core/audio/game_sound.dart';
import 'package:ludo_rank/core/audio/sound_controller.dart';
import 'package:ludo_rank/features/ludo_game/domain/constants/ludo_paths.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_player.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/ludo_token.dart';
import 'package:ludo_rank/features/ludo_game/domain/entities/position.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/available_rolls.dart';
import 'package:ludo_rank/features/ludo_game/domain/models/move_option.dart';
import 'package:ludo_rank/features/ludo_game/domain/services/ludo_move_tracer.dart';
import 'package:ludo_rank/features/ludo_game/presentation/geometry/ludo_board_geometry.dart';
import 'package:ludo_rank/features/ludo_game/presentation/geometry/ludo_token_layout.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/ludo_match_board_art.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/match_die_face.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/match_seat_layout.dart';
import 'package:ludo_rank/features/ludo_game/presentation/widgets/match_ui/match_ui_colors.dart';

/// Live interactive wrapper around the visual board.
///
/// The board handles presentation and input only.
/// Legal moves and move execution remain controlled by the game logic.
///
/// Input is one hit test for the whole board ([resolveTap]) instead of a
/// small gesture area per token, so a finger never has to land on a 20dp
/// token: a tap picks, in this order, a dice chip next to the selected
/// token (its own widgets, drawn on top), a destination of the selected
/// token, then the nearest token of the current player that can move.
class LudoMatchBoard extends StatefulWidget {
  final List<LudoPlayer> players;
  final String? currentPlayerId;
  final List<MoveOption> availableMoves;
  final String? selectedTokenId;
  final int? selectedRollSequence;
  final MoveOption? pendingAutoMove;
  final ValueChanged<LudoToken> onTokenTap;
  final Future<void> Function(MoveOption) onMoveTap;

  /// Legal destinations for the currently selected token.
  final Map<Position, List<MoveOption>> legalMoveDestinations;

  /// Returns the dice value associated with a move.
  final int? Function(MoveOption) rollValueForMove;

  final AvailableRolls selectableRolls;
  final ValueChanged<int> onAvailableRollTap;

  /// Plays the per-square step sound during the move animation.
  final GameSoundPlayer? sounds;

  const LudoMatchBoard({
    super.key,
    required this.players,
    required this.currentPlayerId,
    required this.availableMoves,
    required this.selectedTokenId,
    required this.onTokenTap,
    required this.legalMoveDestinations,
    required this.rollValueForMove,
    required this.onMoveTap,
    this.selectedRollSequence,
    this.pendingAutoMove,
    required this.selectableRolls,
    required this.onAvailableRollTap,
    this.sounds,
  });

  /// Board frame width around the playing area, for a board of [side].
  static double frameFor(double side) => (side * .017).clamp(3.0, 5.0);

  /// Side of the playing area (the 15×15 grid) inside the frame. Matches
  /// the board art, which paints the grid inside a [frameFor] padding.
  static double innerSideFor(double side) => side - frameFor(side) * 2;

  /// A tap within this distance of a movable token's centre selects it:
  /// at least 24dp (a 48dp target) however small the cells are.
  static double tokenHitRadius(double cell) => math.max(cell * .8, 24.0);

  /// Side of the square around a destination cell that accepts the tap:
  /// always more than one full cell.
  static double destinationHitSide(double cell) => cell * 1.4;

  /// Size of one dice chip next to the selected token.
  static const double boardDieSize = 40.0;

  @override
  State<LudoMatchBoard> createState() => _LudoMatchBoardState();
}

/// What a tap on the board resolved to.
sealed class BoardTapTarget {
  const BoardTapTarget();
}

class DestinationTapTarget extends BoardTapTarget {
  final MoveOption move;
  const DestinationTapTarget(this.move);
}

class TokenTapTarget extends BoardTapTarget {
  final LudoToken token;
  const TokenTapTarget(this.token);
}

class _LudoMatchBoardState extends State<LudoMatchBoard>
    with SingleTickerProviderStateMixin {
  /// Time for one square. Each square is its own eased hop, so the piece
  /// lands on every cell (with its step sound) instead of gliding past.
  static const Duration stepDuration = Duration(milliseconds: 210);

  /// Leaving the base is one longer hop onto the start square.
  static const Duration exitDuration = Duration(milliseconds: 320);

  late final AnimationController _controller;

  MoveOption? _animatingMove;
  List<Position> _animationPath = <Position>[];
  String? _animatingTokenId;
  bool _startingAutoMove = false;
  bool _completingMove = false;
  int _lastSoundStep = 0;

  /// Side of the playing area at the last layout, for the tap hit test.
  double _innerSide = 0;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..addStatusListener(_onAnimationStatus);

    _controller.addListener(_onAnimationTick);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tryStartAutomaticMove();
    });
  }

  @override
  void didUpdateWidget(covariant LudoMatchBoard oldWidget) {
    super.didUpdateWidget(oldWidget);

    // A new pending move (or none) re-arms the automatic start. The
    // provider can replace one pending move by the next in a single
    // update (no delay between moves), so null is not the only reset.
    if (widget.pendingAutoMove == null ||
        !identical(widget.pendingAutoMove, oldWidget.pendingAutoMove)) {
      _startingAutoMove = false;
    }

    if (widget.pendingAutoMove != oldWidget.pendingAutoMove ||
        widget.selectedTokenId != oldWidget.selectedTokenId ||
        widget.selectedRollSequence != oldWidget.selectedRollSequence ||
        widget.availableMoves != oldWidget.availableMoves) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tryStartAutomaticMove();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);

        if (!side.isFinite || side <= 0) {
          return const SizedBox.shrink();
        }

        final frame = LudoMatchBoard.frameFor(side);
        final innerSide = LudoMatchBoard.innerSideFor(side);
        _innerSide = innerSide;
        final animating = _animatingMove != null;

        return Center(
          child: SizedBox.square(
            dimension: side,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned.fill(
                  child: RepaintBoundary(
                    child: LudoMatchBoardArt(
                      players: widget.players,
                      hiddenTokenIds: <String>{?_animatingTokenId},
                    ),
                  ),
                ),

                if (!animating && widget.selectedTokenId != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: _buildDestinationMarkers(
                          frame: frame,
                          innerSide: innerSide,
                        ),
                      ),
                    ),
                  ),

                // One hit test for the whole board (see [resolveTap]).
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey<String>('board-input'),
                    behavior: HitTestBehavior.opaque,
                    onTapUp: animating
                        ? null
                        : (details) => _handleBoardTap(
                            details.localPosition - Offset(frame, frame),
                          ),
                  ),
                ),

                if (animating)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: RepaintBoundary(
                        child: _buildAnimatedToken(
                          frame: frame,
                          innerSide: innerSide,
                        ),
                      ),
                    ),
                  ),

                if (!animating &&
                    widget.selectableRolls.isNotEmpty &&
                    widget.selectedTokenId != null)
                  ..._buildSelectedTokenDice(
                    side: side,
                    frame: frame,
                    innerSide: innerSide,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ============================================================
  // INPUT
  // ============================================================

  String _tokenIdOf(MoveOption move) {
    return switch (move) {
      MoveToken(:final tokenId) => tokenId,
      ExitToken(:final tokenId) => tokenId,
    };
  }

  /// Moves of the selected token that the current die choice allows.
  List<MoveOption> _selectedCandidates(List<MoveOption> moves) {
    final selectedTokenId = widget.selectedTokenId;
    return moves
        .where(
          (move) =>
              _tokenIdOf(move) == selectedTokenId &&
              (widget.selectedRollSequence == null ||
                  move.rollSequence == widget.selectedRollSequence),
        )
        .toList(growable: false);
  }

  /// Resolves a tap at [point] (playing-area coordinates, side
  /// [innerSide]) to a destination of the selected token or the nearest
  /// movable token of the current player. Dice chips are on top of the
  /// board and never reach this hit test.
  @visibleForTesting
  BoardTapTarget? resolveTap(Offset point, double innerSide) {
    final cell = innerSide / LudoBoardGeometry.gridSize;
    final geometry = LudoBoardGeometry.instance;

    // 1. A destination of the selected token.
    if (widget.selectedTokenId != null) {
      final half = LudoMatchBoard.destinationHitSide(cell) / 2;
      MoveOption? best;
      var bestDistance = double.infinity;

      for (final entry in widget.legalMoveDestinations.entries) {
        final candidates = _selectedCandidates(entry.value);
        if (candidates.isEmpty) continue;

        final center = geometry.cellCenter(entry.key, innerSide);
        final delta = point - center;
        if (delta.dx.abs() > half || delta.dy.abs() > half) continue;

        // Two dice of the same value reach the same square the same way;
        // different values to one square cannot be told apart, so wait
        // for a die to be chosen.
        final values = candidates.map(widget.rollValueForMove).toSet();
        if (values.length != 1) continue;

        final distance = delta.distance;
        if (distance < bestDistance) {
          bestDistance = distance;
          best = candidates.first;
        }
      }

      if (best != null) return DestinationTapTarget(best);
    }

    // 2. The nearest token of the current player that has a legal move.
    final movable = <String>{
      for (final move in widget.availableMoves) _tokenIdOf(move),
    };
    if (movable.isEmpty) return null;

    final centers = LudoTokenLayout.centers(widget.players, innerSide);
    final radius = LudoMatchBoard.tokenHitRadius(cell);
    LudoToken? nearest;
    var nearestDistance = double.infinity;

    for (final player in widget.players) {
      if (player.playerId != widget.currentPlayerId) continue;
      for (final token in player.tokens) {
        if (!movable.contains(token.id)) continue;
        final distance = (point - centers[token.id]!).distance;
        if (distance <= radius && distance < nearestDistance) {
          nearestDistance = distance;
          nearest = token;
        }
      }
    }

    return nearest == null ? null : TokenTapTarget(nearest);
  }

  void _handleBoardTap(Offset point) {
    if (_animatingMove != null || _innerSide <= 0) return;

    switch (resolveTap(point, _innerSide)) {
      case DestinationTapTarget(:final move):
        _startMoveAnimation(move);
      case TokenTapTarget(:final token):
        widget.onTokenTap(token);
      case null:
        break;
    }
  }

  // ============================================================
  // MOVE ANIMATION
  // ============================================================

  void _tryStartAutomaticMove() {
    if (_animatingMove != null || !mounted) return;

    // الحركة الوحيدة التي اكتشفها الـ Provider بعد رمي النرد.
    final pending = widget.pendingAutoMove;

    if (pending != null && !_startingAutoMove) {
      _startingAutoMove = true;
      _startMoveAnimation(pending);
      return;
    }

    // لو اختار اللاعب قطعة ورمية نرد، وكانت هناك حركة قانونية واحدة
    // تطابق الاختيار، شغّل الأنيميشن بدل التنفيذ المباشر.
    if (widget.selectedTokenId == null) return;

    final candidates = _selectedCandidates(widget.availableMoves);
    if (candidates.length == 1) {
      _startMoveAnimation(candidates.single);
    }
  }

  bool _sameMove(MoveOption a, MoveOption b) {
    if (a is MoveToken && b is MoveToken) {
      return a.tokenId == b.tokenId &&
          a.steps == b.steps &&
          a.rollSequence == b.rollSequence;
    }

    if (a is ExitToken && b is ExitToken) {
      return a.tokenId == b.tokenId && a.rollSequence == b.rollSequence;
    }

    return false;
  }

  void _startMoveAnimation(MoveOption move) {
    if (_animatingMove != null) return;

    // لا نحرّك أي قطعة بناءً على اختيار قديم لم يعد قانونيًا.
    if (!widget.availableMoves.any((candidate) => _sameMove(candidate, move))) {
      return;
    }

    final tokenId = _tokenIdOf(move);

    final player = widget.players.cast<LudoPlayer?>().firstWhere(
      (p) => p?.tokens.any((token) => token.id == tokenId) ?? false,
      orElse: () => null,
    );

    if (player == null) return;

    final token = player.tokens.firstWhere((t) => t.id == tokenId);
    final path = _pathFor(player.color);
    final geometry = LudoBoardGeometry.instance;

    // القطعة الموجودة في البيت ليس لها Position صالح على مسار اللعب.
    // نستخدم مكانها المرئي الحقيقي داخل Home Zone كبداية للأنيميشن.
    final startPosition = move is ExitToken
        ? geometry.tokenHomePosition(
            color: player.color,
            tokenIndex: token.tokenIndex,
          )
        : token.position;

    final positions = <Position>[startPosition];

    if (move is ExitToken) {
      // الخروج من مكان القطعة داخل البيت إلى نقطة البداية.
      positions.add(path.startingPosition);
    } else if (move is MoveToken) {
      // نفس حساب المحرك بالظبط (LudoMoveTracer) عشان الأنيميشن
      // ما يمشيش في طريق والقطعة تقف في مكان تاني.
      final trace = LudoMoveTracer.trace(
        path: path,
        hasCaptured: player.hasCaptured,
        token: token,
        steps: move.steps,
      );

      if (trace == null) return;

      positions.addAll(trace.map((pathStep) => pathStep.position));
    }

    if (positions.length < 2) return;

    setState(() {
      _lastSoundStep = 0;
      _animatingMove = move;
      _animatingTokenId = tokenId;
      _animationPath = positions;
    });

    // تحديد مدة الحركة قبل تشغيل الأنيميشن: كل مربع قفزة بزمن ثابت.
    final hops = positions.length - 1;
    _controller.duration = move is ExitToken
        ? exitDuration
        : stepDuration * hops;

    // تشغيل الحركة من البداية.
    _controller.forward(from: 0);
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted || _completingMove) {
      return;
    }

    if (_animatingMove == null) return;

    _completingMove = true;
    unawaited(_completeAnimatedMove());
  }

  Future<void> _completeAnimatedMove() async {
    final move = _animatingMove;
    if (move == null) {
      _completingMove = false;
      return;
    }

    try {
      // انتظر اعتماد الحركة داخل الـ Provider ومحرك اللعبة.
      await widget.onMoveTap(move);
    } catch (error, stackTrace) {
      debugPrint('Failed to complete animated move: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (mounted) {
        setState(() {
          _animatingMove = null;
          _animatingTokenId = null;
          _animationPath = <Position>[];
        });

        _controller.reset();

        // The provider may already offer the next automatic move (the
        // rest of the turn has one legal move); start it now that this
        // animation is cleared.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _tryStartAutomaticMove();
        });
      }

      _completingMove = false;
    }
  }

  void _onAnimationTick() {
    if (_animatingMove == null || _animationPath.length < 2) {
      return;
    }

    final totalSteps = _animationPath.length - 1;
    final currentStep = (_controller.value * totalSteps).floor().clamp(
      0,
      totalSteps,
    );

    if (currentStep <= _lastSoundStep) return;

    _lastSoundStep = currentStep;

    widget.sounds?.play(GameSound.step);
  }

  LudoPath _pathFor(LudoPlayerColor color) {
    return switch (color) {
      LudoPlayerColor.red => LudoPaths.red,
      LudoPlayerColor.green => LudoPaths.green,
      LudoPlayerColor.yellow => LudoPaths.yellow,
      LudoPlayerColor.blue => LudoPaths.blue,
    };
  }

  /// Progress inside the current hop, 0..1 (linear).
  double _hopFraction() {
    final hops = _animationPath.length - 1;
    if (hops <= 0) return 0;
    final scaled = _controller.value * hops;
    final index = scaled.floor().clamp(0, hops - 1);
    return (scaled - index).clamp(0.0, 1.0);
  }

  Offset _animatedCenter(double innerSide) {
    final count = _animationPath.length;
    final geometry = LudoBoardGeometry.instance;
    final scaled = _controller.value * (count - 1);
    final index = scaled.floor().clamp(0, count - 2);
    final fraction = Curves.easeInOut.transform(
      (scaled - index).clamp(0.0, 1.0),
    );

    final from = geometry.cellCenter(_animationPath[index], innerSide);
    final to = geometry.cellCenter(_animationPath[index + 1], innerSide);

    return Offset.lerp(from, to, fraction)!;
  }

  // ============================================================
  // LAYERS
  // ============================================================

  List<Widget> _buildDestinationMarkers({
    required double frame,
    required double innerSide,
  }) {
    final geometry = LudoBoardGeometry.instance;
    final cell = innerSide / LudoBoardGeometry.gridSize;
    final size = cell * .86;
    final widgets = <Widget>[];

    for (final entry in widget.legalMoveDestinations.entries) {
      final candidates = _selectedCandidates(entry.value);
      if (candidates.isEmpty) continue;

      final center = geometry.cellCenter(entry.key, innerSide);
      final diceValue = widget.rollValueForMove(candidates.first);

      widgets.add(
        Positioned(
          left: frame + center.dx - size / 2,
          top: frame + center.dy - size / 2,
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xDDFFFFFF),
              borderRadius: BorderRadius.circular(size * .22),
              border: Border.all(color: const Color(0xFFFFD166), width: 2),
            ),
            child: Center(
              child: MatchDieFace(value: diceValue, size: size * .8),
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _buildAnimatedToken({
    required double frame,
    required double innerSide,
  }) {
    if (_animatingMove == null || _animationPath.length < 2) {
      return const SizedBox.shrink();
    }

    final tokenId = _animatingTokenId;
    LudoPlayer? owner;

    for (final player in widget.players) {
      if (player.tokens.any((token) => token.id == tokenId)) {
        owner = player;
        break;
      }
    }

    if (owner == null) return const SizedBox.shrink();

    final cell = innerSide / LudoBoardGeometry.gridSize;
    final color = owner.color;

    // Transform only: the token moves every frame without a new layout.
    return CustomPaint(
      painter: _MovingTokenPainter(
        animation: _controller,
        color: color,
        cell: cell,
        origin: Offset(frame, frame),
        center: () => _animatedCenter(innerSide),
        lift: () => math.sin(math.pi * _hopFraction()),
      ),
    );
  }

  List<Widget> _buildSelectedTokenDice({
    required double side,
    required double frame,
    required double innerSide,
  }) {
    final tokenId = widget.selectedTokenId;

    LudoPlayer? owner;
    for (final player in widget.players) {
      if (player.tokens.any((token) => token.id == tokenId)) {
        owner = player;
        break;
      }
    }

    if (owner == null || tokenId == null) return const <Widget>[];

    final color = matchUiColorFor(owner.color);
    const dieSize = LudoMatchBoard.boardDieSize;
    const spacing = 4.0;

    final rolls = widget.selectableRolls.rolls;
    final totalWidth = rolls.length * dieSize + (rolls.length - 1) * spacing;

    final cell = innerSide / LudoBoardGeometry.gridSize;
    final center =
        Offset(frame, frame) +
        LudoTokenLayout.centers(widget.players, innerSide)[tokenId]!;
    final gap = LudoTokenLayout.tokenRadius(cell) + 4;

    // A top-row player sits across the table: their chips are turned to
    // face them and sit on their side of the token. Chips stay inside the
    // board so every one of them can be tapped.
    final facesFarSide = MatchSeatLayout.facesFarSide(owner.color);
    final above = center.dy - gap - dieSize;
    final below = center.dy + gap;
    var top = facesFarSide ? below : above;
    if (top < 0) top = below;
    if (top + dieSize > side) top = above;
    final left = (center.dx - totalWidth / 2)
        .clamp(0.0, math.max(0.0, side - totalWidth))
        .toDouble();

    return <Widget>[
      Positioned(
        left: left,
        top: top,
        width: totalWidth,
        height: dieSize,
        child: RotatedBox(
          quarterTurns: facesFarSide ? 2 : 0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < rolls.length; index++) ...[
                if (index > 0) const SizedBox(width: spacing),
                _BoardDieChip(
                  key: ValueKey<String>('board-die-${rolls[index].sequence}'),
                  value: rolls[index].value,
                  size: dieSize,
                  color: color,
                  selected:
                      widget.selectedRollSequence == rolls[index].sequence,
                  onTap: () => widget.onAvailableRollTap(rolls[index].sequence),
                ),
              ],
            ],
          ),
        ),
      ),
    ];
  }
}

class _BoardDieChip extends StatelessWidget {
  final int value;
  final double size;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _BoardDieChip({
    super.key,
    required this.value,
    required this.size,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF181321),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? const Color(0xFFFFD166) : color,
            width: selected ? 2.4 : 1.6,
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x59000000),
              blurRadius: 5,
              offset: Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: MatchDieFace(value: value, size: size * .72),
      ),
    );
  }
}

/// Paints the token that walks along its path. It repaints with the
/// animation but never lays anything out again.
class _MovingTokenPainter extends CustomPainter {
  final Animation<double> animation;
  final LudoPlayerColor color;
  final double cell;
  final Offset origin;
  final Offset Function() center;
  final double Function() lift;

  _MovingTokenPainter({
    required this.animation,
    required this.color,
    required this.cell,
    required this.origin,
    required this.center,
    required this.lift,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    // A small lift in the middle of each hop.
    final hop = lift();
    final at = origin + center() - Offset(0, hop * cell * .14);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.scale(1 + hop * .16);
    paintMatchToken(canvas, Offset.zero, cell, color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MovingTokenPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.cell != cell ||
        oldDelegate.origin != origin;
  }
}
