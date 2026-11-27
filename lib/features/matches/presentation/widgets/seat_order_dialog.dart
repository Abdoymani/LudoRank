import 'package:flutter/material.dart';

import 'package:ludo_rank/features/matches/presentation/seat_colors.dart';

/// Shows the seat order (and colours) a new match will use, before it is
/// created. Pops with the confirmed order (index 0 = seat 1), or null.
///
/// With [redraw] (seat draw on), the order can be drawn again.
class SeatOrderDialog extends StatefulWidget {
  final List<String> initialOrder;
  final String Function(String playerId) playerName;
  final List<String> Function()? redraw;

  const SeatOrderDialog({
    super.key,
    required this.initialOrder,
    required this.playerName,
    this.redraw,
  });

  @override
  State<SeatOrderDialog> createState() => _SeatOrderDialogState();
}

class _SeatOrderDialogState extends State<SeatOrderDialog>
    with SingleTickerProviderStateMixin {
  static const _rowFade = Duration(milliseconds: 250);
  static const _rowGap = Duration(milliseconds: 150);

  late List<String> _order = widget.initialOrder;

  /// Reveals the drawn seats one after another.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: _rowFade + _rowGap * (widget.initialOrder.length - 1),
  );

  bool get _isDraw => widget.redraw != null;

  @override
  void initState() {
    super.initState();
    if (_isDraw) {
      _reveal.forward();
    } else {
      _reveal.value = 1;
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  /// The part of the reveal in which row [index] fades in.
  Animation<double> _rowAnimation(int index) {
    final total = _reveal.duration!.inMilliseconds;
    final start = (_rowGap * index).inMilliseconds / total;
    final end = start + _rowFade.inMilliseconds / total;

    return CurvedAnimation(
      parent: _reveal,
      curve: Interval(start, end.clamp(0, 1), curve: Curves.easeOut),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playersCount = _order.length;

    return AlertDialog(
      title: Text(_isDraw ? 'نتيجة القرعة' : 'ترتيب المقاعد'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < playersCount; i++)
              _SeatRow(
                seat: i + 1,
                playersCount: playersCount,
                name: widget.playerName(_order[i]),
                reveal: _rowAnimation(i),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('رجوع'),
        ),
        if (_isDraw)
          TextButton.icon(
            onPressed: () {
              setState(() => _order = widget.redraw!());
              _reveal.forward(from: 0);
            },
            icon: const Icon(Icons.casino_outlined),
            label: const Text('قرعة تاني'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _order),
          child: const Text('ابدأ المباراة'),
        ),
      ],
    );
  }
}

class _SeatRow extends StatelessWidget {
  final int seat;
  final int playersCount;
  final String name;

  final Animation<double> reveal;

  const _SeatRow({
    required this.seat,
    required this.playersCount,
    required this.name,
    required this.reveal,
  });

  @override
  Widget build(BuildContext context) {
    final color = seatColor(seat, playersCount);
    final theme = Theme.of(context);

    final row = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: color,
            child: Text(
              '$seat',
              style: TextStyle(
                color: onSeatColor(color),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  seatColorName(seat, playersCount),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (seat == 1)
            Text(
              'بيبدأ الأول',
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );

    return FadeTransition(
      opacity: reveal,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(reveal),
        child: row,
      ),
    );
  }
}
