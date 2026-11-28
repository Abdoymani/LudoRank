import 'package:flutter/material.dart';

import 'package:ludo_rank/core/dependency_injection/injection_container.dart';
import 'package:ludo_rank/features/home/domain/entities/dashboard_summary.dart';
import 'package:ludo_rank/features/home/domain/repositories/home_repository.dart';
import 'package:ludo_rank/features/home/presentation/match_resumer.dart';
import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';
import 'package:ludo_rank/features/matches/presentation/pages/tournament_matches_page.dart';
import 'package:ludo_rank/features/matches/presentation/widgets/match_status_chip.dart';
import 'package:ludo_rank/shared/widgets/app_empty_state.dart';
import 'package:ludo_rank/shared/widgets/app_error_widget.dart';
import 'package:ludo_rank/shared/widgets/app_loading.dart';
import 'package:ludo_rank/shared/widgets/app_scaffold.dart';

/// Every match of every tournament (the home "matches" card). A match
/// opens its tournament's match list, where it can be started or resumed.
class AllMatchesPage extends StatefulWidget {
  const AllMatchesPage({super.key});

  @override
  State<AllMatchesPage> createState() => _AllMatchesPageState();
}

class _AllMatchesPageState extends State<AllMatchesPage> {
  List<MatchOverview>? _matches;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final matches = await sl<HomeRepository>().getAllMatches();
      if (!mounted) return;
      setState(() {
        _matches = matches;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  /// A paused match opens straight into the game; any other match opens
  /// its tournament's list (start, results, cancel live there).
  Future<void> _openMatch(MatchOverview match) async {
    if (match.status == MatchStatus.playing) {
      await resumeMatch(context, match);
      if (mounted) await _load();
      return;
    }
    await _openTournamentMatches(match);
  }

  Future<void> _openTournamentMatches(MatchOverview match) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TournamentMatchesPage(tournamentId: match.tournamentId),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(title: 'المباريات', body: _buildBody());
  }

  Widget _buildBody() {
    final matches = _matches;

    if (matches == null) {
      return _error == null
          ? const AppLoading()
          : AppErrorWidget(message: _error!, onRetry: _load);
    }

    if (matches.isEmpty) {
      return const AppEmptyState(
        icon: Icons.sports_esports_outlined,
        title: 'لسه مفيش مباريات',
        subtitle: 'المباريات بتتعمل من جوه البطولة.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: matches.length,
        itemBuilder: (context, index) {
          final match = matches[index];

          return Card(
            key: ValueKey(match.matchId),
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              onTap: () => _openMatch(match),
              leading: CircleAvatar(
                child: Text(
                  match.matchNumber > 0 ? '${match.matchNumber}' : '#',
                ),
              ),
              title: Text(
                match.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${match.tournamentName} • ${match.playersCount} لاعبين',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: MatchStatusChip(status: match.status),
            ),
          );
        },
      ),
    );
  }
}
