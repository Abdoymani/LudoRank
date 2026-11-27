import 'dart:math';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:ludo_rank/core/dependency_injection/injection_container.dart';

import 'package:ludo_rank/features/matches/domain/entities/match.dart';
import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';
import 'package:ludo_rank/features/match_players/domain/entities/match_player.dart';
import 'package:ludo_rank/features/matches/domain/Use-cases/create_match.dart';
import 'package:ludo_rank/features/matches/domain/services/seat_draw.dart';
import 'package:ludo_rank/features/matches/presentation/seat_colors.dart';
import 'package:ludo_rank/features/matches/presentation/widgets/seat_order_dialog.dart';
import 'package:ludo_rank/features/ludo_game/presentation/pages/match_game_page.dart';
import 'package:ludo_rank/features/tournament_players/presentation/providers/tournament_player_provider.dart';
import 'package:ludo_rank/features/players/presentation/providers/player_provider.dart';
import 'package:ludo_rank/shared/widgets/app_scaffold.dart';

class CreateMatchPage extends StatefulWidget {
  final String tournamentId;

  /// Source for the seat draw. Defaults to `Random.secure()`; tests pass a
  /// seeded one.
  final Random? random;

  const CreateMatchPage({super.key, required this.tournamentId, this.random});

  @override
  State<CreateMatchPage> createState() => _CreateMatchPageState();
}

class _CreateMatchPageState extends State<CreateMatchPage> {
  final TournamentPlayerProvider tournamentPlayerProvider =
      sl<TournamentPlayerProvider>();

  final CreateMatch createMatch = sl<CreateMatch>();
  final PlayerProvider playerProvider = sl<PlayerProvider>();
  final Uuid uuid = const Uuid();

  int? _playersCount;

  final Set<String> _selectedPlayerIds = {};

  bool _isCreating = false;

  /// Seat draw (on by default): seats are dealt at random when the match
  /// is created. Off: seats follow the order the players were picked in.
  bool _drawSeats = true;

  late final Random _random = widget.random ?? Random.secure();

  @override
  void initState() {
    super.initState();

    tournamentPlayerProvider.loadPlayers(widget.tournamentId);
    playerProvider.loadPlayers();
  }

  void _selectPlayersCount(int count) {
    setState(() {
      _playersCount = count;

      // لو غيرنا عدد اللاعبين،
      // نمسح الاختيارات القديمة حتى لا تصبح غير صالحة.
      _selectedPlayerIds.clear();
    });
  }

  void _togglePlayer(String playerId) {
    if (_playersCount == null) {
      return;
    }

    setState(() {
      if (_selectedPlayerIds.contains(playerId)) {
        _selectedPlayerIds.remove(playerId);
        return;
      }

      if (_selectedPlayerIds.length >= _playersCount!) {
        return;
      }

      _selectedPlayerIds.add(playerId);
    });
  }

  bool get _canCreateMatch {
    return _playersCount != null &&
        _selectedPlayerIds.length == _playersCount &&
        !_isCreating;
  }

  Future<void> _createNewMatch() async {
    if (!_canCreateMatch) {
      return;
    }

    final picked = _selectedPlayerIds.toList();
    final selectedPlayers = await showDialog<List<String>>(
      context: context,
      builder: (_) => SeatOrderDialog(
        initialOrder: _drawSeats ? drawSeats(picked, _random) : picked,
        playerName: playerProvider.getPlayerName,
        redraw: _drawSeats ? () => drawSeats(picked, _random) : null,
      ),
    );

    if (selectedPlayers == null || !mounted) {
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      final now = DateTime.now();

      final match = Match(
        id: uuid.v4(),
        tournamentId: widget.tournamentId,
        playersCount: _playersCount!,
        status: MatchStatus.pending,
        createdAt: now,
        updatedAt: now,
      );

      await playerProvider.loadPlayers();

      final playerNames = <String, String>{
        for (final playerId in selectedPlayers)
          playerId: playerProvider.getPlayerName(playerId),
      };

      if (playerNames.values.any((name) => name == 'لاعب غير معروف')) {
        throw StateError('تعذر تحميل أسماء كل اللاعبين المختارين.');
      }
      final matchPlayers = <MatchPlayer>[];

      for (var i = 0; i < selectedPlayers.length; i++) {
        matchPlayers.add(
          MatchPlayer(
            id: uuid.v4(),
            matchId: match.id,
            playerId: selectedPlayers[i],
            seat: i + 1,
            rank: null,
            points: 0,
            finished: false,
          ),
        );
      }

      await createMatch(match: match, players: matchPlayers);

      if (!mounted) {
        return;
      }

      // Wait for the game page to close before returning to the match list,
      // so the list reloads with the match's real status. (pushReplacement
      // returned to the list immediately, while the match was still pending,
      // and a paused match then showed "start" instead of "resume".)
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) =>
              MatchGamePage(matchId: match.id, playerNames: playerNames),
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
      return;
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل إنشاء المباراة: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'إنشاء مباراة',
      body: ListenableBuilder(
        listenable: tournamentPlayerProvider,
        builder: (context, _) {
          if (tournamentPlayerProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (tournamentPlayerProvider.error != null) {
            return Center(child: Text(tournamentPlayerProvider.error!));
          }

          final players = tournamentPlayerProvider.players;

          if (players.isEmpty) {
            return const Center(child: Text('لا يوجد لاعبين داخل البطولة'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'عدد اللاعبين في المباراة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _PlayersCountButton(
                        count: 2,
                        selected: _playersCount == 2,
                        onTap: () {
                          _selectPlayersCount(2);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PlayersCountButton(
                        count: 3,
                        selected: _playersCount == 3,
                        onTap: () {
                          _selectPlayersCount(3);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PlayersCountButton(
                        count: 4,
                        selected: _playersCount == 4,
                        onTap: () {
                          _selectPlayersCount(4);
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                const Text(
                  'ترتيب المقاعد',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 12),

                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.casino_outlined),
                      label: Text('قرعة'),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.format_list_numbered),
                      label: Text('ترتيب يدوي'),
                    ),
                  ],
                  selected: {_drawSeats},
                  onSelectionChanged: (selection) {
                    setState(() => _drawSeats = selection.single);
                  },
                ),

                const SizedBox(height: 8),

                Text(
                  _drawSeats
                      ? 'المقاعد هتتوزع بالقرعة لما تدوس إنشاء. '
                            'المقعد 1 (الأخضر) بيبدأ الأول.'
                      : 'المقاعد بترتيب اختيارك. '
                            'المقعد 1 (الأخضر) بيبدأ الأول.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),

                const SizedBox(height: 24),

                if (_playersCount == null)
                  const Text(
                    'اختار عدد اللاعبين أولاً',
                    textAlign: TextAlign.center,
                  ),

                if (_playersCount != null) ...[
                  Text(
                    'اختار $_playersCount لاعبين',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  ...players.map((tournamentPlayer) {
                    final playerId = tournamentPlayer.playerId;

                    final selected = _selectedPlayerIds.contains(playerId);

                    final disabled =
                        !selected &&
                        _selectedPlayerIds.length >= _playersCount!;

                    final seat = selected ? _getSeat(playerId) : 0;

                    final showSeat = selected && !_drawSeats;

                    final tileColor = !selected
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                        : showSeat
                        ? seatColor(seat, _playersCount!)
                        : Theme.of(context).colorScheme.primary;

                    final backgroundColor = selected
                        ? tileColor.withValues(alpha: 0.16)
                        : Theme.of(context).colorScheme.surface;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      color: backgroundColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: selected
                              ? tileColor
                              : Theme.of(context).colorScheme.outlineVariant,
                          width: selected ? 1.5 : 0.7,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: CheckboxListTile(
                        value: selected,
                        onChanged: disabled
                            ? null
                            : (_) {
                                _togglePlayer(playerId);
                              },
                        activeColor: selected ? tileColor : null,
                        secondary: showSeat
                            ? CircleAvatar(
                                backgroundColor: tileColor,
                                child: Text(
                                  '$seat',
                                  style: TextStyle(
                                    color: onSeatColor(tileColor),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            : CircleAvatar(
                                child: Icon(
                                  selected
                                      ? Icons.casino_outlined
                                      : Icons.person_outline,
                                ),
                              ),
                        title: Text(
                          playerProvider.getPlayerName(playerId),
                          style: TextStyle(
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          !selected
                              ? 'لم يتم اختيار المقعد'
                              : showSeat
                              ? 'المقعد: $seat'
                              : 'المقعد بالقرعة',
                          style: TextStyle(
                            color: selected ? tileColor : null,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 20),

                  Text(
                    'تم اختيار ${_selectedPlayerIds.length} '
                    'من $_playersCount',
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 16),

                  ElevatedButton.icon(
                    onPressed: _canCreateMatch ? _createNewMatch : null,
                    icon: _isCreating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    label: Text(
                      _isCreating ? 'جاري إنشاء المباراة...' : 'إنشاء المباراة',
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  int _getSeat(String playerId) {
    final index = _selectedPlayerIds.toList().indexOf(playerId);

    return index == -1 ? 0 : index + 1;
  }
}

class _PlayersCountButton extends StatelessWidget {
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _PlayersCountButton({
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final padding = const EdgeInsets.symmetric(vertical: 16);
    final label = Text('$count لاعبين');

    if (selected) {
      return FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(padding: padding),
        child: label,
      );
    }

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(padding: padding),
      child: label,
    );
  }
}
