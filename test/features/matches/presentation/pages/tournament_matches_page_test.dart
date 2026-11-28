import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_rank/app/app_routes.dart';
import 'package:ludo_rank/features/ludo_game/presentation/pages/match_game_page.dart';
import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';
import 'package:ludo_rank/features/matches/presentation/pages/create_match_page.dart';
import 'package:ludo_rank/features/matches/presentation/pages/tournament_matches_page.dart';
import 'package:ludo_rank/features/tournaments/domain/entities/tournament.dart';

import '../../../../helpers/test_app.dart';

void main() {
  final app = TestApp();

  setUp(app.setUp);
  tearDown(app.tearDown);

  late String ali;
  late String mona;

  Future<String> seed({
    TournamentStatus status = TournamentStatus.running,
  }) async {
    ali = await app.addPlayer('علي');
    mona = await app.addPlayer('منى');
    final id = await app.addTournament(
      'كأس الشتاء',
      status: status,
      createdAt: DateTime(2026, 5, 1),
      playerIds: [ali, mona],
    );
    for (final matchStatus in [
      MatchStatus.finished, // 1
      MatchStatus.playing, // 2
      MatchStatus.pending, // 3
      MatchStatus.cancelled, // 4
      MatchStatus.finished, // 5
    ]) {
      await app.addMatch(id, playerIds: [ali, mona], status: matchStatus);
    }
    return id;
  }

  /// Opens the tournament, then its matches list.
  Future<void> openMatches(WidgetTester tester, String tournamentId) async {
    await app.pump(tester, location: '${AppRoutes.tournaments}/$tournamentId');
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data == 'استكمال البطولة' || w.data == 'عرض المباريات'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TournamentMatchesPage), findsOneWidget);
  }

  List<String> visibleTitles(WidgetTester tester) {
    return find
        .textContaining(RegExp(r'^مباراة رقم \d$'))
        .evaluate()
        .map((element) => (element.widget as Text).data!)
        .toList();
  }

  testWidgets('open matches come first, each with its action', (tester) async {
    final id = await seed();
    await openMatches(tester, id);

    expect(visibleTitles(tester).take(3), [
      'مباراة رقم 2',
      'مباراة رقم 3',
      'مباراة رقم 5',
    ]);
    expect(find.text('عدد المباريات: 5 • مفتوحة: 2'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'كمّل'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'ابدأ'), findsOneWidget);
    expect(
      find.widgetWithText(FloatingActionButton, 'مباراة جديدة'),
      findsOneWidget,
    );
  });

  testWidgets('"كمّل" resumes the paused match', (tester) async {
    final id = await seed();
    await openMatches(tester, id);

    await tester.tap(find.widgetWithText(FilledButton, 'كمّل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final game = tester.widget<MatchGamePage>(find.byType(MatchGamePage));
    expect(game.resumeExisting, isTrue);
    expect(game.playerNames, {ali: 'علي', mona: 'منى'});
  });

  testWidgets('the FAB opens match creation', (tester) async {
    final id = await seed();
    await openMatches(tester, id);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.byType(CreateMatchPage), findsOneWidget);
  });

  testWidgets('a finished tournament offers no new match', (tester) async {
    final id = await seed(status: TournamentStatus.finished);
    await openMatches(tester, id);

    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('a match with an unknown status has no actions', (tester) async {
    ali = await app.addPlayer('علي');
    mona = await app.addPlayer('منى');
    final id = await app.addTournament(
      'كأس الشتاء',
      status: TournamentStatus.running,
      createdAt: DateTime(2026, 5, 1),
      playerIds: [ali, mona],
    );
    final matchId = await app.addMatch(id, playerIds: [ali, mona]);
    await app.database.customStatement(
      "UPDATE matches SET status = 'archived' WHERE id = ?",
      [matchId],
    );

    await openMatches(tester, id);

    expect(find.text('غير معروفة'), findsOneWidget);
    expect(find.text('ابدأ'), findsNothing);
    expect(find.text('كمّل'), findsNothing);
    expect(find.text('إلغاء'), findsNothing);
  });
}
