import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_rank/app/app_routes.dart';
import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';
import 'package:ludo_rank/features/tournaments/domain/entities/tournament.dart';

import '../../../helpers/test_app.dart';

void main() {
  final app = TestApp();

  setUp(app.setUp);
  tearDown(app.tearDown);

  Finder statValue(String label, String value) {
    final card = find.ancestor(
      of: find.text(label),
      matching: find.byType(Card),
    );
    return find.descendant(of: card, matching: find.text(value));
  }

  testWidgets('shows status, counts and standings of a running tournament', (
    tester,
  ) async {
    final ali = await app.addPlayer('علي');
    final mona = await app.addPlayer('منى');
    final sara = await app.addPlayer('سارة');
    final id = await app.addTournament(
      'كأس الشتاء',
      status: TournamentStatus.running,
      createdAt: DateTime(2026, 5, 1),
      playerIds: [ali, mona, sara],
    );
    await app.addMatch(
      id,
      playerIds: [mona, ali],
      status: MatchStatus.finished,
    );
    await app.addMatch(id, playerIds: [ali, sara], status: MatchStatus.playing);

    await app.pump(tester, location: '${AppRoutes.tournaments}/$id');
    await tester.pumpAndSettle();

    expect(find.text('كأس الشتاء'), findsOneWidget);
    expect(find.text('شغالة'), findsOneWidget);
    expect(statValue('المشاركون', '3'), findsOneWidget);
    expect(statValue('إجمالي المباريات', '2'), findsOneWidget);
    expect(statValue('مباريات مكتملة', '1'), findsOneWidget);

    // The winner of the finished match leads the standings.
    final first = tester.getTopLeft(find.text('منى')).dy;
    final second = tester.getTopLeft(find.text('علي')).dy;
    expect(first, lessThan(second));

    expect(find.text('إنهاء البطولة'), findsOneWidget);
  });

  testWidgets('a finished tournament is read-only', (tester) async {
    final id = await app.addTournament(
      'بطولة الصيف',
      status: TournamentStatus.finished,
      createdAt: DateTime(2026, 4, 1),
    );

    await app.pump(tester, location: '${AppRoutes.tournaments}/$id');
    await tester.pumpAndSettle();

    expect(find.text('منتهية'), findsOneWidget);
    expect(find.text('عرض المباريات'), findsOneWidget);
    expect(find.text('إنهاء البطولة'), findsNothing);
  });
}
