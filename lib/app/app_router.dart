import 'package:go_router/go_router.dart';
import 'package:ludo_rank/features/splash/presentation/pages/splash_page.dart';
import 'package:ludo_rank/features/players/presentation/pages/players_page.dart';

import '../features/home/presentation/pages/home_page.dart';
import '../features/tournaments/presentation/pages/tournament_details_page.dart';
import 'app_routes.dart';
import 'package:ludo_rank/features/tournaments/presentation/pages/tournaments_page.dart';
import 'package:ludo_rank/features/tournaments/presentation/providers/tournament_provider.dart';

final GoRouter appRouter = createAppRouter();

/// The app's routes. Tests build their own router (with another
/// [initialLocation]) so navigation state does not leak between them.
GoRouter createAppRouter({String initialLocation = AppRoutes.splash}) =>
    GoRouter(
      initialLocation: initialLocation,

      routes: [
        GoRoute(
          path: AppRoutes.splash,
          name: 'splash',
          builder: (context, state) => const SplashPage(),
        ),

        GoRoute(
          path: AppRoutes.home,
          name: 'home',
          builder: (context, state) => const HomePage(),
        ),

        GoRoute(
          path: AppRoutes.players,
          name: 'players',

          builder: (context, state) {
            return const PlayersPage();
          },
        ),

        GoRoute(
          path: AppRoutes.tournaments,
          name: 'tournaments',
          builder: (context, state) => TournamentsPage(
            initialFilter: TournamentFilter.fromName(
              state.uri.queryParameters['status'],
            ),
          ),
        ),

        GoRoute(
          path: '${AppRoutes.tournaments}/:id',

          name: 'tournament-details',

          builder: (context, state) {
            final id = state.pathParameters['id']!;

            return TournamentDetailsPage(tournamentId: id);
          },
        ),
      ],
    );
