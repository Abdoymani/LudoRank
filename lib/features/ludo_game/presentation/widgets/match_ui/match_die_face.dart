import 'dart:math' as math;

import 'package:flutter/material.dart';

class MatchDieFace extends StatelessWidget {
  final int? value;
  final double size;

  const MatchDieFace({super.key, required this.value, this.size = 34});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCFF),
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(color: const Color(0xFFE2DCEA), width: 1),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: value == null
          ? Icon(
              Icons.casino_outlined,
              size: size * 0.55,
              color: const Color(0xFF81788B),
            )
          : CustomPaint(
              painter: _MatchDiePipsPainter(value: value!, size: size),
            ),
    );
  }
}

class _MatchDiePipsPainter extends CustomPainter {
  final int value;
  final double size;

  const _MatchDiePipsPainter({required this.value, required this.size});

  static const Map<int, List<Offset>> _pips = <int, List<Offset>>{
    1: <Offset>[Offset(.5, .5)],
    2: <Offset>[Offset(.28, .28), Offset(.72, .72)],
    3: <Offset>[Offset(.28, .28), Offset(.5, .5), Offset(.72, .72)],
    4: <Offset>[
      Offset(.28, .28),
      Offset(.72, .28),
      Offset(.28, .72),
      Offset(.72, .72),
    ],
    5: <Offset>[
      Offset(.28, .28),
      Offset(.72, .28),
      Offset(.5, .5),
      Offset(.28, .72),
      Offset(.72, .72),
    ],
    6: <Offset>[
      Offset(.28, .25),
      Offset(.72, .25),
      Offset(.28, .5),
      Offset(.72, .5),
      Offset(.28, .75),
      Offset(.72, .75),
    ],
  };

  @override
  void paint(Canvas canvas, Size paintSize) {
    final radius = size * 0.075;
    final paint = Paint()
      ..color = const Color(0xFF30213D)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    for (final point in _pips[value] ?? const <Offset>[]) {
      canvas.drawCircle(
        Offset(point.dx * paintSize.width, point.dy * paintSize.height),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MatchDiePipsPainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.size != size;
  }
}

/// A die that tumbles for [duration] each time [rollId] changes, then
/// settles on [value]. Shows [value] still when there is nothing to roll.
///
/// It owns its controller, so the tumble repaints only the die: the card
/// around it is not rebuilt per frame.
class AnimatedMatchDieFace extends StatefulWidget {
  final int? value;
  final double size;

  /// A new id starts a new tumble; null means no roll is animating.
  final int? rollId;
  final Duration duration;

  const AnimatedMatchDieFace({
    super.key,
    required this.value,
    required this.size,
    this.rollId,
    this.duration = Duration.zero,
  });

  @override
  State<AnimatedMatchDieFace> createState() => _AnimatedMatchDieFaceState();
}

class _AnimatedMatchDieFaceState extends State<AnimatedMatchDieFace>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);

  /// Faces shown while tumbling; fixed per roll so it is deterministic.
  static const List<int> _tumble = <int>[3, 5, 2, 6, 1, 4, 2, 5];

  @override
  void initState() {
    super.initState();
    _maybeStart(null);
  }

  @override
  void didUpdateWidget(covariant AnimatedMatchDieFace oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeStart(oldWidget.rollId);
  }

  void _maybeStart(int? previousRollId) {
    final rollId = widget.rollId;
    if (rollId == null || rollId == previousRollId) return;
    if (widget.duration == Duration.zero) return;
    _controller.duration = widget.duration;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        if (!_controller.isAnimating || t >= 1) {
          return MatchDieFace(value: widget.value, size: widget.size);
        }

        // Tumbling for the first 70%, then the result lands with a bounce.
        const settleAt = .7;
        final settled = t >= settleAt;
        final face = settled
            ? widget.value
            : _tumble[((t / settleAt) * _tumble.length).floor().clamp(
                0,
                _tumble.length - 1,
              )];
        final angle = settled ? 0.0 : (1 - t / settleAt) * 2.4 * math.pi;
        final scale = settled
            ? 1 + .18 * math.sin(math.pi * (t - settleAt) / (1 - settleAt))
            : .88 + .12 * math.sin(math.pi * t / settleAt * 3).abs();

        return Transform.rotate(
          angle: angle,
          child: Transform.scale(
            scale: scale,
            child: MatchDieFace(value: face, size: widget.size),
          ),
        );
      },
    );
  }
}
