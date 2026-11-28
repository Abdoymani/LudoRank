import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:ludo_rank/app/app_routes.dart';
import 'package:ludo_rank/core/dependency_injection/injection_container.dart';
import 'package:ludo_rank/features/backup/data/data_export_service.dart';
import 'package:ludo_rank/features/backup/presentation/widgets/export_data_button.dart';
import 'package:ludo_rank/features/home/domain/entities/dashboard_summary.dart';
import 'package:ludo_rank/features/home/presentation/match_resumer.dart';
import 'package:ludo_rank/features/home/presentation/providers/home_provider.dart';
import 'package:ludo_rank/features/home/presentation/widgets/dashboard_card.dart';
import 'package:ludo_rank/features/tournaments/domain/entities/tournament.dart';
import 'package:ludo_rank/features/tournaments/presentation/widgets/create_tournament_dialog.dart';
import 'package:ludo_rank/features/tournaments/presentation/widgets/tournament_card.dart';
import 'package:ludo_rank/shared/widgets/app_error_widget.dart';
import 'package:ludo_rank/shared/widgets/app_loading.dart';
import 'package:ludo_rank/shared/widgets/app_scaffold.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  Future<void> _reload() => context.read<HomeProvider>().loadDashboard();

  /// Opens [location] and refreshes the counts when coming back.
  Future<void> _open(String location) async {
    await context.push(location);
    if (mounted) await _reload();
  }

  Future<void> _createTournament() async {
    await createTournamentAndOpen(context);
    if (mounted) await _reload();
  }

  Future<void> _resume(MatchOverview match) async {
    await resumeMatch(context, match);
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeProvider>(
      builder: (context, provider, child) {
        return AppScaffold(
          title: 'LudoRank',
          actions: [ExportDataButton(service: () => sl<DataExportService>())],
          body: _buildBody(provider),
        );
      },
    );
  }

  Widget _buildBody(HomeProvider provider) {
    final dashboard = provider.dashboard;

    if (dashboard == null && provider.isLoading) {
      return const AppLoading();
    }

    if (dashboard == null && provider.error != null) {
      return AppErrorWidget(message: provider.error!, onRetry: _reload);
    }

    final resumable = dashboard?.resumableMatch;

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (resumable != null) ...[
            _ResumeMatchCard(
              match: resumable,
              onResume: () => _resume(resumable),
            ),
            const SizedBox(height: 16),
          ],

          ElevatedButton.icon(
            onPressed: _createTournament,
            icon: const Icon(Icons.emoji_events),
            label: const Text('إنشاء بطولة جديدة'),
          ),

          const SizedBox(height: 24),

          // One short row of counts that open their lists.
          Row(
            children: [
              Expanded(
                child: DashboardCard(
                  icon: Icons.people,
                  title: 'اللاعبون',
                  value: provider.playersCount,
                  onTap: () => _open(AppRoutes.players),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DashboardCard(
                  icon: Icons.emoji_events,
                  title: 'البطولات',
                  value: provider.tournamentsCount,
                  onTap: () => _open(AppRoutes.tournaments),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DashboardCard(
                  icon: Icons.sports_esports,
                  title: 'المباريات',
                  value: provider.matchesCount,
                  onTap: () => _open(AppRoutes.matches),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          _LastTournamentCard(
            summary: dashboard?.lastTournament,
            onOpen: (id) => _open('${AppRoutes.tournaments}/$id'),
            onCreate: _createTournament,
          ),
        ],
      ),
    );
  }
}

class _ResumeMatchCard extends StatelessWidget {
  final MatchOverview match;
  final VoidCallback onResume;

  const _ResumeMatchCard({required this.match, required this.onResume});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.play_circle_fill_rounded,
              size: 40,
              color: colors.onPrimaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'كمّل آخر مباراة',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${match.title} • ${match.tournamentName}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.onPrimaryContainer),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: onResume, child: const Text('كمّل')),
          ],
        ),
      ),
    );
  }
}

class _LastTournamentCard extends StatelessWidget {
  final LastTournamentSummary? summary;
  final ValueChanged<String> onOpen;
  final VoidCallback onCreate;

  const _LastTournamentCard({
    required this.summary,
    required this.onOpen,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = this.summary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              summary?.tournament.status == TournamentStatus.running
                  ? 'البطولة الحالية'
                  : 'آخر بطولة',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (summary == null) ...[
              const Text('لسه مفيش بطولات.'),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add),
                  label: const Text('إنشاء بطولة'),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      summary.tournament.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TournamentStatusChip(status: summary.tournament.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${summary.counts.matches} مباراة • '
                '${summary.counts.players} لاعب',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.icon(
                  onPressed: () => onOpen(summary.tournament.id),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('فتح البطولة'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
