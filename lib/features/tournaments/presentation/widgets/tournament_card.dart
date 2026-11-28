import 'package:flutter/material.dart';

import 'package:ludo_rank/features/tournaments/domain/entities/tournament.dart';
import 'package:ludo_rank/features/tournaments/presentation/extensions/tournament_status_extension.dart';

class TournamentCard extends StatelessWidget {
  final Tournament tournament;

  final TournamentCounts counts;

  final VoidCallback? onTap;

  const TournamentCard({
    super.key,
    required this.tournament,
    this.counts = TournamentCounts.zero,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.emoji_events, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tournament.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TournamentStatusChip(status: tournament.status),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _CountLabel(
                    icon: Icons.people_alt_rounded,
                    text: '${counts.players} لاعب',
                  ),
                  _CountLabel(
                    icon: Icons.sports_esports_rounded,
                    text: '${counts.matches} مباراة',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('فتح'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountLabel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _CountLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(text, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

/// Small coloured pill with the tournament status.
class TournamentStatusChip extends StatelessWidget {
  final TournamentStatus status;

  const TournamentStatusChip({super.key, required this.status});

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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(
            status.title,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
