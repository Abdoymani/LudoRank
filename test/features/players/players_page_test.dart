import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_rank/app/app_routes.dart';
import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';
import 'package:ludo_rank/features/tournaments/domain/entities/tournament.dart';

import '../../helpers/test_app.dart';

void main() {
  final app = TestApp();

  setUp(app.setUp);
  tearDown(app.tearDown);

  testWidgets('each player shows their record, and a tap renames them', (
    tester,
  ) async {
    late String ali;
    late String mona;
    await tester.runAsync(() async {
      ali = await app.addPlayer('علي');
      mona = await app.addPlayer('منى');
      await app.addPlayer('سارة');
      final cup = await app.addTournament(
        'كأس',
        status: TournamentStatus.running,
        createdAt: DateTime(2026, 1, 1),
        playerIds: [ali, mona],
      );
      // Ali first, Mona second; a pending match does not count.
      await app.addMatch(
        cup,
        playerIds: [ali, mona],
        status: MatchStatus.finished,
      );
      await app.addMatch(cup, playerIds: [mona, ali]);
    });

    await app.pump(tester, location: AppRoutes.players);
    await tester.pumpAndSettle();

    expect(find.text('1 مباراة • 1 فوز • 2 نقطة'), findsOneWidget);
    expect(find.text('1 مباراة • 0 فوز • 1 نقطة'), findsOneWidget);
    expect(find.text('لسه ملعبش مباريات'), findsOneWidget);

    await tester.tap(find.text('سارة'));
    await tester.pumpAndSettle();
    expect(find.text('تعديل اللاعب'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'سارة أحمد');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('سارة أحمد'), findsOneWidget);
    expect(find.text('تعديل اللاعب'), findsNothing);
  });

  testWidgets('renaming to a taken name keeps the dialog open', (tester) async {
    await tester.runAsync(() async {
      await app.addPlayer('علي');
      await app.addPlayer('منى');
    });

    await app.pump(tester, location: AppRoutes.players);
    await tester.pumpAndSettle();

    await tester.tap(find.text('منى'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'علي');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('تعديل اللاعب'), findsOneWidget);
    expect(find.text('منى'), findsOneWidget, reason: 'list unchanged');
  });
}
