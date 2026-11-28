import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:ludo_rank/app/app_routes.dart';
import 'package:ludo_rank/features/tournaments/domain/entities/tournament.dart';
import 'package:ludo_rank/features/tournaments/presentation/providers/tournament_provider.dart';
import 'package:ludo_rank/features/tournaments/presentation/widgets/create_tournament_dialog.dart';
import 'package:ludo_rank/features/tournaments/presentation/widgets/tournament_card.dart';
import 'package:ludo_rank/shared/widgets/app_empty_state.dart';
import 'package:ludo_rank/shared/widgets/app_error_widget.dart';
import 'package:ludo_rank/shared/widgets/app_loading.dart';
import 'package:ludo_rank/shared/widgets/app_scaffold.dart';

class TournamentsPage extends StatefulWidget {
  /// The status filter selected when the page opens.
  final TournamentFilter initialFilter;

  const TournamentsPage({super.key, this.initialFilter = TournamentFilter.all});

  static const Map<TournamentFilter, String> filterLabels = {
    TournamentFilter.all: 'الكل',
    TournamentFilter.running: 'شغالة',
    TournamentFilter.draft: 'مسودة',
    TournamentFilter.finished: 'منتهية',
  };

  @override
  State<TournamentsPage> createState() => _TournamentsPageState();
}

class _TournamentsPageState extends State<TournamentsPage> {
  late TournamentFilter _filter = widget.initialFilter;

  final _searchController = TextEditingController();

  String _query = '';

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TournamentProvider>().loadTournaments();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() {
    return context.read<TournamentProvider>().loadTournaments();
  }

  Future<void> _create() async {
    await createTournamentAndOpen(context);
    if (mounted) await _reload();
  }

  Future<void> _open(Tournament tournament) async {
    await context.push('${AppRoutes.tournaments}/${tournament.id}');
    // Matches and players may have changed the status and counts.
    if (mounted) await _reload();
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _filter = TournamentFilter.all;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TournamentProvider>(
      builder: (context, provider, child) {
        return AppScaffold(
          title: 'البطولات',
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _create,
            icon: const Icon(Icons.add),
            label: const Text('بطولة جديدة'),
          ),
          body: _buildBody(provider),
        );
      },
    );
  }

  Widget _buildBody(TournamentProvider provider) {
    if (provider.isLoading && provider.tournaments.isEmpty) {
      return const AppLoading();
    }

    if (provider.error != null && provider.tournaments.isEmpty) {
      return AppErrorWidget(message: provider.error!, onRetry: _reload);
    }

    if (provider.tournaments.isEmpty) {
      return AppEmptyState(
        icon: Icons.emoji_events_outlined,
        title: 'لسه مفيش بطولات',
        subtitle: 'ابدأ بإنشاء أول بطولة وضيف لاعبينها.',
        action: FilledButton.icon(
          onPressed: _create,
          icon: const Icon(Icons.add),
          label: const Text('إنشاء بطولة'),
        ),
      );
    }

    final tournaments = provider.filtered(_filter, _query);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _searchController,
            maxLength: Tournament.maxNameLength,
            textInputAction: TextInputAction.search,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'دوّر باسم البطولة',
              prefixIcon: const Icon(Icons.search),
              counterText: '',
              isDense: true,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'مسح البحث',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final filter in TournamentFilter.values)
                ChoiceChip(
                  label: Text(TournamentsPage.filterLabels[filter]!),
                  showCheckmark: false,
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
            ],
          ),
        ),
        Expanded(
          child: tournaments.isEmpty
              ? AppEmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'مفيش بطولات مطابقة',
                  action: TextButton(
                    onPressed: _clearFilters,
                    child: const Text('عرض كل البطولات'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: tournaments.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, index) {
                      final tournament = tournaments[index];

                      return TournamentCard(
                        key: ValueKey(tournament.id),
                        tournament: tournament,
                        counts: provider.countsFor(tournament.id),
                        onTap: () => _open(tournament),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
