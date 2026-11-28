import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_rank/app/app_routes.dart';
import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';
import 'package:ludo_rank/features/tournaments/domain/entities/tournament.dart';
import 'package:ludo_rank/features/tournaments/presentation/pages/tournament_details_page.dart';
import 'package:ludo_rank/features/tournaments/presentation/widgets/tournament_card.dart';

import '../../../helpers/test_app.dart';

void main() {
  final app = TestApp();

  setUp(app.setUp);
  tearDown(app.tearDown);

  List<String> cardNames(WidgetTester tester) {
    return tester
        .widgetList<TournamentCard>(find.byType(TournamentCard))
        .map((card) => card.tournament.name)
        .toList();
  }

  Future<void> seed() async {
    final a = await app.addPlayer('علي');
    final b = await app.addPlayer('منى');
    final running = await app.addTournament(
      'دوري رمضان',
      status: TournamentStatus.running,
      createdAt: DateTime(2026, 3, 1),
      playerIds: [a, b],
    );
    await app.addMatch(
      running,
      playerIds: [a, b],
      status: MatchStatus.finished,
    );
    await app.addMatch(running, playerIds: [b, a]);
    await app.addTournament('كأس الشتاء', createdAt: DateTime(2026, 5, 1));
    await app.addTournament(
      'بطولة الصيف',
      status: TournamentStatus.finished,
      createdAt: DateTime(2026, 4, 1),
    );
  }

  testWidgets('lists newest first with status and player/match counts', (
    tester,
  ) async {
    await seed();
    await app.pump(tester, location: AppRoutes.tournaments);
    await tester.pumpAndSettle();

    expect(cardNames(tester), ['كأس الشتاء', 'بطولة الصيف', 'دوري رمضان']);

    final ramadan = find.ancestor(
      of: find.text('دوري رمضان'),
      matching: find.byType(TournamentCard),
    );
    for (final text in ['شغالة', '2 لاعب', '2 مباراة']) {
      expect(
        find.descendant(of: ramadan, matching: find.text(text)),
        findsOneWidget,
      );
    }
  });

  testWidgets('filters by status and searches by name', (tester) async {
    await seed();
    await app.pump(tester, location: AppRoutes.tournaments);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'شغالة'));
    await tester.pump();
    expect(cardNames(tester), ['دوري رمضان']);

    await tester.tap(find.widgetWithText(ChoiceChip, 'مسودة'));
    await tester.pump();
    expect(cardNames(tester), ['كأس الشتاء']);

    await tester.tap(find.widgetWithText(ChoiceChip, 'منتهية'));
    await tester.pump();
    expect(cardNames(tester), ['بطولة الصيف']);

    await tester.tap(find.widgetWithText(ChoiceChip, 'الكل'));
    // Hamza and taa marbuta forms do not matter.
    await tester.enterText(find.byType(TextField), 'بطوله');
    await tester.pump();
    expect(cardNames(tester), ['بطولة الصيف']);

    await tester.enterText(find.byType(TextField), 'xyz');
    await tester.pump();
    expect(find.byType(TournamentCard), findsNothing);
    expect(find.text('مفيش بطولات مطابقة'), findsOneWidget);

    await tester.tap(find.text('عرض كل البطولات'));
    await tester.pump();
    expect(cardNames(tester), hasLength(3));
  });

  testWidgets('opens filtered from the route query', (tester) async {
    await seed();
    await app.pump(
      tester,
      location: '${AppRoutes.tournaments}?status=finished',
    );
    await tester.pumpAndSettle();

    expect(cardNames(tester), ['بطولة الصيف']);
  });

  testWidgets('empty list offers to create; a new tournament opens', (
    tester,
  ) async {
    await app.pump(tester, location: AppRoutes.tournaments);
    await tester.pumpAndSettle();

    expect(find.text('لسه مفيش بطولات'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'إنشاء بطولة'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'دوري الجمعة');
    await tester.tap(find.text('إنشاء'));
    await tester.pumpAndSettle();

    expect(find.byType(TournamentDetailsPage), findsOneWidget);
    expect(find.text('دوري الجمعة'), findsOneWidget);
  });

  testWidgets('a tournament with an unknown status is shown read-only', (
    tester,
  ) async {
    final id = await app.addTournament('قديمة', createdAt: DateTime(2026));
    await app.setRawTournamentStatus(id, 'archived');

    await app.pump(tester, location: AppRoutes.tournaments);
    await tester.pumpAndSettle();
    expect(find.text('غير معروفة'), findsOneWidget);

    await tester.tap(find.text('قديمة'));
    await tester.pumpAndSettle();

    expect(find.byType(TournamentDetailsPage), findsOneWidget);
    final addPlayers = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('إضافة لاعبين'),
        matching: find.byWidgetPredicate((w) => w is OutlinedButton),
      ),
    );
    expect(addPlayers.onPressed, isNull);
    expect(find.text('إنهاء البطولة'), findsNothing);
  });
}
