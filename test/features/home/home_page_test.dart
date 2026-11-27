import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_rank/features/home/presentation/pages/all_matches_page.dart';
import 'package:ludo_rank/features/ludo_game/presentation/pages/match_game_page.dart';
import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';
import 'package:ludo_rank/features/matches/presentation/pages/tournament_matches_page.dart';
import 'package:ludo_rank/features/tournaments/domain/entities/tournament.dart';
import 'package:ludo_rank/features/tournaments/presentation/pages/tournament_details_page.dart';
import 'package:ludo_rank/features/tournaments/presentation/pages/tournaments_page.dart';
import 'package:ludo_rank/features/tournaments/presentation/widgets/tournament_card.dart';

import '../../helpers/test_app.dart';

void main() {
  final app = TestApp();

  setUp(app.setUp);
  tearDown(app.tearDown);

  late String ali;
  late String mona;
  late String winterCup;

  Future<void> seed({bool withPausedMatch = true}) async {
    ali = await app.addPlayer('علي');
    mona = await app.addPlayer('منى');
    await app.addTournament(
      'بطولة الصيف',
      status: TournamentStatus.finished,
      createdAt: DateTime(2026, 4, 1),
    );
    winterCup = await app.addTournament(
      'كأس الشتاء',
      status: TournamentStatus.running,
      createdAt: DateTime(2026, 5, 1),
      playerIds: [ali, mona],
    );
    await app.addMatch(
      winterCup,
      playerIds: [ali, mona],
      status: MatchStatus.finished,
      updatedAt: DateTime(2026, 5, 3),
    );
    await app.addMatch(
      winterCup,
      playerIds: [mona, ali],
      status: withPausedMatch ? MatchStatus.playing : MatchStatus.pending,
      updatedAt: DateTime(2026, 5, 2),
    );
  }

  testWidgets('an empty app offers to create the first tournament', (
    tester,
  ) async {
    await app.pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('لسه مفيش بطولات.'), findsOneWidget);
    expect(find.text('كمّل آخر مباراة'), findsNothing);

    await tester.tap(find.text('إنشاء بطولة جديدة'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'دوري الجمعة');
    await tester.tap(find.text('إنشاء'));
    await tester.pumpAndSettle();

    // The new tournament opens right away.
    expect(find.byType(TournamentDetailsPage), findsOneWidget);

    // Back home, it is the last tournament.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('دوري الجمعة'), findsOneWidget);
    expect(find.text('مسودة'), findsOneWidget);
  });

  testWidgets('shows the last tournament with its counts and opens it', (
    tester,
  ) async {
    await seed();
    await app.pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('كأس الشتاء'), findsOneWidget);
    expect(find.text('شغالة'), findsOneWidget);
    expect(find.text('2 مباراة • 2 لاعب'), findsOneWidget);

    await tester.ensureVisible(find.text('فتح البطولة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('فتح البطولة'));
    await tester.pumpAndSettle();

    expect(find.byType(TournamentDetailsPage), findsOneWidget);
  });

  testWidgets('a paused match gets a resume shortcut that opens the game', (
    tester,
  ) async {
    await seed();
    await app.pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('كمّل آخر مباراة'), findsOneWidget);
    expect(find.text('مباراة رقم 2 • كأس الشتاء'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'كمّل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final game = tester.widget<MatchGamePage>(find.byType(MatchGamePage));
    expect(game.resumeExisting, isTrue);
    expect(game.playerNames, {mona: 'منى', ali: 'علي'});
  });

  testWidgets('no shortcut when no match is paused', (tester) async {
    await seed(withPausedMatch: false);
    await app.pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('كمّل آخر مباراة'), findsNothing);
  });

  testWidgets('the matches card lists every match, open ones first', (
    tester,
  ) async {
    await seed();
    await app.pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('المباريات'));
    await tester.pumpAndSettle();

    expect(find.byType(AllMatchesPage), findsOneWidget);
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title! as Text).data)
        .toList();
    expect(titles, ['مباراة رقم 2', 'مباراة رقم 1']);
    expect(find.text('متوقفة'), findsOneWidget);
    expect(find.text('منتهية'), findsOneWidget);

    await tester.tap(find.text('مباراة رقم 1'));
    await tester.pumpAndSettle();
    expect(find.byType(TournamentMatchesPage), findsOneWidget);
  });

  testWidgets('the finished card opens the finished tournaments', (
    tester,
  ) async {
    await seed();
    await app.pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('بطولات منتهية'));
    await tester.pumpAndSettle();

    expect(find.byType(TournamentsPage), findsOneWidget);
    final names = tester
        .widgetList<TournamentCard>(find.byType(TournamentCard))
        .map((card) => card.tournament.name);
    expect(names, ['بطولة الصيف']);
  });
}
