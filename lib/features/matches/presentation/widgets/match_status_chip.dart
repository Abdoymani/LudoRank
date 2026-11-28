import 'package:flutter/material.dart';

import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';

extension MatchStatusLabel on MatchStatus {
  String get title => switch (this) {
    MatchStatus.pending => 'لم تبدأ',
    MatchStatus.playing => 'متوقفة',
    MatchStatus.finished => 'منتهية',
    MatchStatus.cancelled => 'ملغاة',
    MatchStatus.unknown => 'غير معروفة',
  };

  Color get color => switch (this) {
    MatchStatus.pending => Colors.grey,
    MatchStatus.playing => Colors.orange.shade700,
    MatchStatus.finished => Colors.blue,
    MatchStatus.cancelled => Colors.red,
    MatchStatus.unknown => Colors.blueGrey,
  };
}

/// Small coloured pill with a match status.
class MatchStatusChip extends StatelessWidget {
  final MatchStatus status;

  const MatchStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status.color;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        status.title,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
