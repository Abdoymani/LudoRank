import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:ludo_rank/app/app_routes.dart';
import 'package:ludo_rank/features/home/presentation/providers/home_provider.dart';
import 'package:ludo_rank/features/home/presentation/widgets/dashboard_card.dart';
import 'package:ludo_rank/features/players/presentation/widgets/app_loading.dart';
import 'package:ludo_rank/features/tournaments/presentation/widgets/create_tournament_dialog.dart';
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
      context.read<HomeProvider>().loadDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeProvider>(
      builder: (context, provider, child) {
        return AppScaffold(
          title: 'LudoRank',
          body: provider.isLoading
              ? const AppLoading()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          await showDialog(
                            context: context,
                            builder: (_) => const CreateTournamentDialog(),
                          );
                        },
                        icon: const Icon(Icons.emoji_events),
                        label: const Text('إنشاء بطولة جديدة'),
                      ),

                      const SizedBox(height: 24),

                      // Responsive dashboard grid
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;

                          final crossAxisCount = width >= 1000
                              ? 4
                              : width >= 650
                              ? 3
                              : 2;

                          final childAspectRatio = width >= 650 ? 1.35 : 0.72;

                          return GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: childAspectRatio,
                            children: [
                              DashboardCard(
                                icon: Icons.people,
                                title: 'اللاعبون',
                                value: provider.playersCount,
                                onTap: () {
                                  context.push(AppRoutes.players);
                                },
                              ),

                              DashboardCard(
                                icon: Icons.emoji_events,
                                title: 'البطولات',
                                value: provider.tournamentsCount,
                                onTap: () {
                                  context.push(AppRoutes.tournaments);
                                },
                              ),

                              DashboardCard(
                                icon: Icons.sports_esports,
                                title: 'المباريات',
                                value: provider.matchesCount,
                              ),

                              DashboardCard(
                                icon: Icons.workspace_premium,
                                title: 'بطولات منتهية',
                                value: provider.finishedTournamentsCount,
                              ),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 24),

                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'آخر بطولة',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 12),
                              const Text('لا توجد بطولة حالياً'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}
