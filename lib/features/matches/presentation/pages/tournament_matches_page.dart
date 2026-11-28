import 'package:flutter/material.dart';

import 'package:ludo_rank/core/dependency_injection/injection_container.dart';

import 'package:ludo_rank/features/matches/domain/Use-cases/cancel_match.dart';
import 'package:ludo_rank/features/matches/domain/entities/match.dart';
import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';
import 'package:ludo_rank/features/matches/presentation/providers/match_provider.dart';
import 'package:ludo_rank/features/matches/presentation/pages/create_match_page.dart';

import 'package:ludo_rank/shared/widgets/app_scaffold.dart';

import 'package:ludo_rank/features/ludo_game/presentation/pages/match_game_page.dart';

import 'package:ludo_rank/features/match_players/domain/entities/match_player.dart';
import 'package:ludo_rank/features/matches/domain/repositories/match_repository.dart';
import 'package:ludo_rank/features/match_players/domain/repositories/match_player_repository.dart';

import 'package:ludo_rank/features/players/domain/entities/player.dart';
import 'package:ludo_rank/features/players/domain/repositories/player_repository.dart';
import 'package:ludo_rank/features/matches/presentation/seat_colors.dart';
import 'package:ludo_rank/features/matches/presentation/widgets/match_status_chip.dart';
import 'package:ludo_rank/features/tournaments/domain/entities/tournament.dart';
import 'package:ludo_rank/features/tournaments/domain/repositories/tournament_repository.dart';
import 'package:ludo_rank/features/tournaments/domain/services/tournament_lifecycle_service.dart';

class TournamentMatchesPage extends StatefulWidget {
  final String tournamentId;

  const TournamentMatchesPage({super.key, required this.tournamentId});

  @override
  State<TournamentMatchesPage> createState() => _TournamentMatchesPageState();
}

class _TournamentMatchesPageState extends State<TournamentMatchesPage> {
  late final MatchProvider matchProvider;

  late final MatchPlayerRepository matchPlayerRepository;
  late final PlayerRepository playerRepository;
  String? _expandedMatchId;
  final Map<String, List<_FinishedPlayerResult>> _finishedResults = {};
  final Set<String> _loadingResults = {};

  /// Null until loaded. New matches are offered only while it is open.
  TournamentStatus? _tournamentStatus;

  bool get _canCreateMatches {
    final status = _tournamentStatus;
    return status == null || TournamentStatusTransitions.isOpen(status);
  }

  @override
  void initState() {
    super.initState();

    matchProvider = sl<MatchProvider>();
    matchPlayerRepository = sl<MatchPlayerRepository>();
    playerRepository = sl<PlayerRepository>();

    _loadMatches();
  }

  /// Open matches first (started, then not started), then the rest;
  /// newest first within each group.
  static List<Match> sortForList(Iterable<Match> matches) {
    int group(MatchStatus status) => switch (status) {
      MatchStatus.playing => 0,
      MatchStatus.pending => 1,
      _ => 2,
    };

    return matches.toList()..sort((a, b) {
      final byGroup = group(a.status).compareTo(group(b.status));
      if (byGroup != 0) return byGroup;
      return b.matchNumber.compareTo(a.matchNumber);
    });
  }

  Future<void> _loadMatches() async {
    await Future.wait([
      matchProvider.loadMatches(widget.tournamentId),
      _loadTournamentStatus(),
    ]);
  }

  Future<void> _loadTournamentStatus() async {
    try {
      final tournament = await sl<TournamentRepository>().getTournamentById(
        widget.tournamentId,
      );
      if (!mounted || tournament == null) return;
      setState(() => _tournamentStatus = tournament.status);
    } catch (e) {
      // Keep offering new matches; CreateMatch still refuses closed ones.
      debugPrint('Tournament status load failed: $e');
    }
  }

  Future<void> _createNewMatch() async {
    // CreateMatchPage returns only after the new match's game page closed,
    // so this reload sees the match's real status (playing/finished).
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateMatchPage(tournamentId: widget.tournamentId),
      ),
    );

    if (!mounted) {
      return;
    }

    await _loadMatches();
  }

  Future<void> _refreshMatches() async {
    await _loadMatches();
  }

  Future<void> _cancelMatch(Match match) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('إلغاء ${_matchTitle(match)}؟'),
        content: const Text(
          'لن تُحسب هذه المباراة في ترتيب البطولة، '
          'ولن يمكن استكمالها بعد الإلغاء.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('إلغاء المباراة'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await sl<CancelMatch>()(match.id);
      if (!mounted) return;
      await _loadMatches();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('تم إلغاء ${_matchTitle(match)}.')),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('تعذر إلغاء المباراة: $e')));
    }
  }

  Future<void> _toggleFinishedMatch(Match match) async {
    if (_expandedMatchId == match.id) {
      setState(() => _expandedMatchId = null);
      return;
    }

    setState(() => _expandedMatchId = match.id);

    if (_finishedResults.containsKey(match.id) ||
        _loadingResults.contains(match.id)) {
      return;
    }

    setState(() => _loadingResults.add(match.id));

    try {
      final matchPlayers = await matchPlayerRepository.getMatchPlayers(
        match.id,
      );

      final results = await Future.wait(
        matchPlayers.map((matchPlayer) async {
          final player = await playerRepository.getPlayerById(
            matchPlayer.playerId,
          );

          return _FinishedPlayerResult(
            name: player?.name ?? 'لاعب غير معروف',
            seat: matchPlayer.seat,
            rank: matchPlayer.rank,
            points: matchPlayer.points,
            color: seatColor(matchPlayer.seat, match.playersCount),
            colorName: seatColorName(matchPlayer.seat, match.playersCount),
          );
        }),
      );

      results.sort((a, b) {
        final rankA = a.rank ?? 999;
        final rankB = b.rank ?? 999;
        return rankA.compareTo(rankB);
      });

      if (!mounted) return;

      setState(() {
        _finishedResults[match.id] = results;
        _loadingResults.remove(match.id);
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loadingResults.remove(match.id));

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('تعذر تحميل نتيجة المباراة: $e')),
        );
    }
  }

  Future<void> _openMatch(Match listed, {bool resumeExisting = false}) async {
    // The list can be older than the database (e.g. the match was started
    // and paused since it loaded). Use the stored status to decide whether
    // this is a new start or a resume.
    Match match = listed;
    try {
      match = await sl<MatchRepository>().getById(listed.id) ?? listed;
    } catch (_) {}
    if (!mounted) return;
    if (match.status == MatchStatus.playing) resumeExisting = true;
    if (match.status == MatchStatus.pending) resumeExisting = false;

    final expectedStatus = resumeExisting
        ? MatchStatus.playing
        : MatchStatus.pending;

    if (match.status != expectedStatus) {
      if (!mounted) return;

      final message = switch (match.status) {
        MatchStatus.playing => 'المباراة بدأت بالفعل. استخدم زر كمّل.',
        MatchStatus.finished => 'هذه المباراة منتهية بالفعل.',
        MatchStatus.cancelled => 'هذه المباراة ملغاة.',
        MatchStatus.pending => 'المباراة لم تبدأ بعد.',
        MatchStatus.unknown =>
          'حالة هذه المباراة غير معروفة، لا يمكن فتحها من هذا الإصدار.',
      };

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));

      return;
    }
    try {
      final matchPlayers = await matchPlayerRepository.getMatchPlayers(
        match.id,
      );

      if (!mounted) {
        return;
      }

      final playerEntries = await Future.wait(
        matchPlayers.map((MatchPlayer matchPlayer) async {
          final Player? player = await playerRepository.getPlayerById(
            matchPlayer.playerId,
          );

          if (player == null) {
            throw StateError('اللاعب ${matchPlayer.playerId} غير موجود.');
          }

          return MapEntry(matchPlayer.playerId, player.name);
        }),
      );

      if (!mounted) {
        return;
      }

      final playerNames = <String, String>{
        for (final entry in playerEntries) entry.key: entry.value,
      };

      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => MatchGamePage(
            matchId: match.id,
            playerNames: playerNames,
            resumeExisting: resumeExisting,
          ),
        ),
      );
      if (!mounted) {
        return;
      }

      // Always refresh: a match left with "pause" is now Playing (resumable)
      // even though the game page did not finish it.
      await _loadMatches();
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('تعذر فتح المباراة: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'مباريات البطولة',
      floatingActionButton: _canCreateMatches
          ? FloatingActionButton.extended(
              onPressed: _createNewMatch,
              icon: const Icon(Icons.add),
              label: const Text('مباراة جديدة'),
            )
          : null,
      body: ListenableBuilder(
        listenable: matchProvider,
        builder: (context, _) {
          if (matchProvider.isLoading && matchProvider.matches.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (matchProvider.error != null && matchProvider.matches.isEmpty) {
            return _ErrorView(
              message: matchProvider.error!,
              onRetry: _loadMatches,
            );
          }

          final matches = sortForList(matchProvider.matches);
          if (matches.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refreshMatches,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 80),

                  Icon(
                    Icons.sports_esports_outlined,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary,
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    'لا توجد مباريات حتى الآن',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    _canCreateMatches
                        ? 'اعمل مباراة جديدة واختار اللاعبين المشاركين فيها.'
                        : 'البطولة دي مقفولة، مينفعش تتضاف لها مباريات.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final hasError = matchProvider.error != null;

          return RefreshIndicator(
            onRefresh: _refreshMatches,
            child: ListView.builder(
              // Room at the bottom so the FAB never covers a button.
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: matches.length + 1 + (hasError ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _MatchesHeader(
                      matchesCount: matches.length,
                      openCount: matches
                          .where(
                            (match) =>
                                match.status == MatchStatus.playing ||
                                match.status == MatchStatus.pending,
                          )
                          .length,
                    ),
                  );
                }

                if (index > matches.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      matchProvider.error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  );
                }

                final match = matches[index - 1];

                return _MatchCard(
                  key: ValueKey(match.id),
                  match: match,
                  expanded: _expandedMatchId == match.id,
                  loadingResult: _loadingResults.contains(match.id),
                  results: _finishedResults[match.id] ?? const [],
                  onTap: () {
                    if (match.status == MatchStatus.finished) {
                      _toggleFinishedMatch(match);
                    } else {
                      _openMatch(match);
                    }
                  },
                  onResume: match.status == MatchStatus.playing
                      ? () => _openMatch(match, resumeExisting: true)
                      : null,
                  onStart: match.status == MatchStatus.pending
                      ? () => _openMatch(match)
                      : null,
                  onCancel: CancelMatch.canCancel(match.status)
                      ? () => _cancelMatch(match)
                      : null,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _MatchesHeader extends StatelessWidget {
  final int matchesCount;
  final int openCount;

  const _MatchesHeader({required this.matchesCount, required this.openCount});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.sports_esports, size: 32),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'مباريات البطولة',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    openCount > 0
                        ? 'عدد المباريات: $matchesCount • مفتوحة: $openCount'
                        : 'عدد المباريات: $matchesCount',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  final Match match;
  final VoidCallback onTap;
  final bool expanded;
  final bool loadingResult;
  final List<_FinishedPlayerResult> results;
  final VoidCallback? onResume;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;

  const _MatchCard({
    super.key,
    required this.match,
    required this.onTap,
    required this.expanded,
    required this.loadingResult,
    required this.results,
    required this.onResume,
    required this.onStart,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isFinished = match.status == MatchStatus.finished;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        child: Text(
                          match.matchNumber > 0 ? '${match.matchNumber}' : '#',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _matchTitle(match),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('عدد اللاعبين: ${match.playersCount}'),
                          ],
                        ),
                      ),
                      MatchStatusChip(status: match.status),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        isFinished ? Icons.emoji_events_outlined : Icons.people,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isFinished
                              ? (expanded
                                    ? 'إخفاء نتيجة المباراة'
                                    : 'عرض نتيجة المباراة')
                              : '${match.playersCount} لاعبين',
                        ),
                      ),
                      Icon(
                        isFinished
                            ? (expanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down)
                            : Icons.arrow_forward_ios,
                        size: 18,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (onResume != null || onStart != null || onCancel != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onCancel != null)
                    TextButton.icon(
                      onPressed: onCancel,
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('إلغاء'),
                    ),
                  if (onStart != null)
                    OutlinedButton.icon(
                      onPressed: onStart,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('ابدأ'),
                    ),
                  if (onResume != null)
                    FilledButton.icon(
                      onPressed: onResume,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('كمّل'),
                    ),
                ],
              ),
            ),

          if (expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: _buildResultContent(context),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultContent(BuildContext context) {
    final theme = Theme.of(context);

    if (loadingResult) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'لا توجد تفاصيل نتيجة مسجلة لهذه المباراة.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'نتيجة المباراة',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        for (final result in results)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.45,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: result.color.withValues(alpha: 0.55)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: result.color,
                  child: Icon(
                    Icons.person,
                    color: onSeatColor(result.color),
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'اللون: ${result.colorName}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      result.rank == null
                          ? 'بدون ترتيب'
                          : 'المركز ${result.rank}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text('${result.points} نقطة'),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 60),

            const SizedBox(height: 16),

            const Text(
              'حدث خطأ أثناء تحميل المباريات',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            Text(message, textAlign: TextAlign.center),

            const SizedBox(height: 20),

            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinishedPlayerResult {
  final String name;
  final int seat;
  final int? rank;
  final int points;
  final Color color;
  final String colorName;

  const _FinishedPlayerResult({
    required this.name,
    required this.seat,
    required this.rank,
    required this.points,
    required this.color,
    required this.colorName,
  });
}

String _matchTitle(Match match) {
  return match.matchNumber > 0
      ? 'مباراة رقم ${match.matchNumber}'
      : 'مباراة ${match.id.substring(0, 8)}';
}
