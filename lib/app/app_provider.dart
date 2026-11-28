import 'package:ludo_rank/features/match_players/presentation/providers/match_player_provider.dart';
import 'package:ludo_rank/features/matches/presentation/providers/match_provider.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:ludo_rank/core/dependency_injection/injection_container.dart';

import 'package:ludo_rank/features/home/presentation/providers/home_provider.dart';
import 'package:ludo_rank/features/players/presentation/providers/player_provider.dart';
import 'package:ludo_rank/features/tournaments/presentation/providers/tournament_provider.dart';
import 'package:ludo_rank/features/tournament_players/presentation/providers/tournament_player_provider.dart';

import 'package:ludo_rank/app/theme_controller.dart';

import 'package:ludo_rank/core/audio/sound_controller.dart';
import 'package:ludo_rank/core/settings/app_settings.dart';

class AppProviders {
  /// A getter, so every app instance reads the current get_it registrations
  /// (tests reset them between runs).
  static List<SingleChildWidget> get providers => [
    ChangeNotifierProvider<ThemeController>(
      create: (_) => ThemeController(settings: sl<AppSettings>()),
    ),
    // Singleton owned by get_it, so `.value` (the provider must not dispose it).
    ChangeNotifierProvider<SoundController>.value(value: sl<SoundController>()),
    ChangeNotifierProvider<HomeProvider>(create: (_) => sl<HomeProvider>()),
    ChangeNotifierProvider<PlayerProvider>(create: (_) => sl<PlayerProvider>()),
    ChangeNotifierProvider<TournamentProvider>(
      create: (_) => sl<TournamentProvider>(),
    ),
    ChangeNotifierProvider<TournamentPlayerProvider>(
      create: (_) => sl<TournamentPlayerProvider>(),
    ),
    ChangeNotifierProvider<MatchProvider>(create: (_) => sl<MatchProvider>()),
    ChangeNotifierProvider<MatchPlayerProvider>(
      create: (_) => sl<MatchPlayerProvider>(),
    ),
  ];
}
