import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_rank/core/dependency_injection/injection_container.dart';
import 'package:ludo_rank/features/ludo_game/presentation/pages/match_game_page.dart';
import 'package:ludo_rank/features/match_players/domain/repositories/match_player_repository.dart';
import 'package:ludo_rank/features/matches/domain/repositories/match_repository.dart';
import 'package:ludo_rank/features/matches/domain/services/seat_draw.dart';
import 'package:ludo_rank/features/matches/presentation/pages/create_match_page.dart';
import 'package:ludo_rank/features/matches/presentation/widgets/seat_order_dialog.dart';
import 'package:ludo_rank/features/tournaments/domain/entities/tournament.dart';

import '../../../../helpers/test_app.dart';

void main() {
  final app = TestApp();

  setUp(app.setUp);
  tearDown(app.tearDown);

  late String tournamentId;
  late Map<String, String> names; // id -> name

  Future<void> seed() async {
    names = {};
    for (final name in ['علي', 'منى', 'سارة', 'كريم']) {
      names[await app.addPlayer(name)] = name;
    }
    tournamentId = await app.addTournament(
      'كأس الشتاء',
      status: TournamentStatus.running,
      createdAt: DateTime(2026, 5, 1),
      playerIds: names.keys.toList(),
    );
  }

  /// Picks 3 players (علي, منى, سارة in that order).
  Future<List<String>> pickThree(WidgetTester tester) async {
    await tester.tap(find.text('3 لاعبين'));
    await tester.pumpAndSettle();
    final picked = names.keys.take(3).toList();
    for (final id in picked) {
      await tester.tap(find.text(names[id]!));
      await tester.pump();
    }
    return picked;
  }

  /// Names in the seat-order dialog, seat 1 first.
  List<String> dialogOrder(WidgetTester tester) {
    final dialog = find.byType(SeatOrderDialog);
    return [
      for (final name in names.values)
        if (find
            .descendant(of: dialog, matching: find.text(name))
            .evaluate()
            .isNotEmpty)
          name,
    ]..sort((a, b) {
      double y(String name) => tester
          .getTopLeft(find.descendant(of: dialog, matching: find.text(name)))
          .dy;
      return y(a).compareTo(y(b));
    });
  }

  Future<List<String>> storedSeatOrder() async {
    final match = (await sl<MatchRepository>().getTournamentMatches(
      tournamentId,
    )).single;
    final players = await sl<MatchPlayerRepository>().getMatchPlayers(match.id);
    players.sort((a, b) => a.seat.compareTo(b.seat));
    return [for (final player in players) names[player.playerId]!];
  }

  testWidgets('draw is on by default: seats are drawn, shown, then saved', (
    tester,
  ) async {
    await seed();
    await app.pumpPage(
      tester,
      CreateMatchPage(tournamentId: tournamentId, random: Random(5)),
    );
    await tester.pumpAndSettle();

    final picked = await pickThree(tester);
    // While drawing, the list does not promise seats.
    expect(find.text('المقعد بالقرعة'), findsNWidgets(3));

    final expected = Random(5);
    final firstDraw = drawSeats(picked, expected);
    final secondDraw = drawSeats(picked, expected);
    // The seed gives two different draws, so the test sees the redraw.
    expect(secondDraw, isNot(firstDraw));

    await tester.tap(find.text('إنشاء المباراة'));
    await tester.pumpAndSettle();

    expect(find.text('نتيجة القرعة'), findsOneWidget);
    expect(dialogOrder(tester), [for (final id in firstDraw) names[id]]);
    expect(find.text('أخضر'), findsOneWidget);
    expect(find.text('بيبدأ الأول'), findsOneWidget);

    await tester.tap(find.text('قرعة تاني'));
    await tester.pumpAndSettle();
    expect(dialogOrder(tester), [for (final id in secondDraw) names[id]]);

    await tester.tap(find.text('ابدأ المباراة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(MatchGamePage), findsOneWidget);
    expect(await storedSeatOrder(), [for (final id in secondDraw) names[id]]);
  });

  testWidgets('manual order keeps the pick order', (tester) async {
    await seed();
    await app.pumpPage(
      tester,
      CreateMatchPage(tournamentId: tournamentId, random: Random(5)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ترتيب يدوي'));
    await tester.pumpAndSettle();
    await pickThree(tester);
    expect(find.text('المقعد: 1'), findsOneWidget);

    await tester.tap(find.text('إنشاء المباراة'));
    await tester.pumpAndSettle();

    expect(find.text('ترتيب المقاعد'), findsNWidgets(2));
    expect(find.text('قرعة تاني'), findsNothing);
    expect(dialogOrder(tester), ['علي', 'منى', 'سارة']);

    await tester.tap(find.text('ابدأ المباراة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(await storedSeatOrder(), ['علي', 'منى', 'سارة']);
  });

  testWidgets('going back from the seat order creates nothing', (tester) async {
    await seed();
    await app.pumpPage(tester, CreateMatchPage(tournamentId: tournamentId));
    await tester.pumpAndSettle();

    await pickThree(tester);
    await tester.tap(find.text('إنشاء المباراة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('رجوع'));
    await tester.pumpAndSettle();

    expect(find.byType(SeatOrderDialog), findsNothing);
    expect(
      await sl<MatchRepository>().getTournamentMatches(tournamentId),
      isEmpty,
    );
  });
}
