import 'package:flutter/material.dart';

import 'package:ludo_rank/core/dependency_injection/injection_container.dart';
import 'package:ludo_rank/features/home/domain/entities/dashboard_summary.dart';
import 'package:ludo_rank/features/home/domain/repositories/home_repository.dart';
import 'package:ludo_rank/features/ludo_game/presentation/pages/match_game_page.dart';
import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';
import 'package:ludo_rank/features/matches/domain/repositories/match_repository.dart';

/// Opens the game page of a started match from outside its tournament
/// (the home shortcut). Returns when the game page closes.
Future<void> resumeMatch(BuildContext context, MatchOverview match) async {
  final messenger = ScaffoldMessenger.of(context);

  void tell(String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  final Map<String, String> playerNames;
  try {
    // The shortcut can be older than the database.
    final current = await sl<MatchRepository>().getById(match.matchId);
    if (current?.status != MatchStatus.playing) {
      tell('المباراة دي مش متوقفة دلوقتي. افتحها من صفحة البطولة.');
      return;
    }

    playerNames = await sl<HomeRepository>().getMatchPlayerNames(match.matchId);
    if (playerNames.length != current!.playersCount) {
      throw StateError('missing players');
    }
  } catch (error) {
    debugPrint('Resume match ${match.matchId} failed: $error');
    tell('تعذر فتح المباراة، حاول مرة أخرى.');
    return;
  }

  if (!context.mounted) return;

  await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => MatchGamePage(
        matchId: match.matchId,
        playerNames: playerNames,
        resumeExisting: true,
      ),
    ),
  );
}
