import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ludo_rank/core/audio/sound_controller.dart';
import 'package:ludo_rank/core/settings/app_settings.dart';

import 'package:ludo_rank/core/dependency_injection/injection_container.dart';
import 'package:ludo_rank/features/ludo_game/presentation/pages/match_game_page.dart';
import 'package:ludo_rank/features/matches/domain/Use-cases/cancel_match.dart';
import 'package:ludo_rank/features/matches/domain/entities/match.dart';
import 'package:ludo_rank/features/matches/domain/entities/match_status.dart';
import 'package:ludo_rank/features/matches/presentation/providers/match_game_provider.dart';

import '../../matches/domain/services/match_game_service_test.dart'
    show
        FakeMatchRepository,
        FakeMatchPlayerRepository,
        FakeMatchGameStateRepository;
import '../../matches/presentation/providers/match_game_provider_test.dart'
    show createSession, createStartedState, FakeMatchGameService;
import '../../matches/presentation/providers/match_game_provider_timing_test.dart'
    show ScriptedRandom;
import 'package:ludo_rank/features/ludo_game/domain/services/ludo_game_engine.dart';

void main() {
  late FakeMatchRepository matchRepository;
  late FakeMatchGameService service;
  late SoundController sounds;

  setUp(() async {
    await sl.reset();
    SharedPreferences.setMockInitialValues({'sound_enabled': false});
    sounds = SoundController(await AppSettings.load());
    matchRepository = FakeMatchRepository();
    final gameStates = FakeMatchGameStateRepository();
    service = FakeMatchGameService(
      matchRepository: matchRepository,
      matchPlayerRepository: FakeMatchPlayerRepository(),
      gameStateRepository: gameStates,
    );
    final now = DateTime(2026, 1, 1);
    final match = Match(
      id: 'match-1',
      tournamentId: 't1',
      playersCount: 2,
      status: MatchStatus.playing,
      createdAt: now,
      updatedAt: now,
    );
    matchRepository.seed(match);
    service.resumeSession = createSession(match: match);
    sl.registerFactory<MatchGameProvider>(
      () => MatchGameProvider(service: service),
    );
    sl.registerSingleton<CancelMatch>(
      CancelMatch(
        matchRepository: matchRepository,
        gameStateRepository: gameStates,
      ),
    );
  });

  tearDown(() => sl.reset());

  Future<List<Object?>> pumpGame(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final results = <Object?>[];
    await tester.pumpWidget(
      ChangeNotifierProvider<SoundController>.value(
        value: sounds,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    results.add(
                      await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MatchGamePage(
                            matchId: 'match-1',
                            playerNames: {'player-1': 'A', 'player-2': 'B'},
                            resumeExisting: true,
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(MatchGamePage), findsOneWidget);
    return results;
  }

  testWidgets('Android back asks first, then pause leaves a resumable match', (
    tester,
  ) async {
    final results = await pumpGame(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // Still on the game, with the leave choices.
    expect(find.byType(MatchGamePage), findsOneWidget);
    expect(find.text('كمّل اللعب'), findsOneWidget);

    await tester.tap(find.text('إيقاف مؤقت والخروج (تكملها بعدين)'));
    await tester.pumpAndSettle();

    expect(find.byType(MatchGamePage), findsNothing);
    expect(results, <Object?>[true]);
    expect(
      (await matchRepository.getById('match-1'))!.status,
      MatchStatus.playing,
    );
  });

  testWidgets('keep playing closes the sheet and stays in the match', (
    tester,
  ) async {
    await pumpGame(tester);

    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('كمّل اللعب'));
    await tester.pumpAndSettle();

    expect(find.byType(MatchGamePage), findsOneWidget);
  });

  testWidgets('cancel asks to confirm, then cancels the match', (tester) async {
    final results = await pumpGame(tester);

    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلغاء المباراة نهائيًا'));
    await tester.pumpAndSettle();
    expect(find.text('إلغاء المباراة نهائيًا؟'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'إلغاء المباراة'));
    await tester.pumpAndSettle();

    expect(find.byType(MatchGamePage), findsNothing);
    expect(results, <Object?>[true]);
    expect(
      (await matchRepository.getById('match-1'))!.status,
      MatchStatus.cancelled,
    );
  });

  testWidgets('a roll with no legal move is shown before the turn passes', (
    tester,
  ) async {
    service.resumeSession = createSession(
      match: (await matchRepository.getById('match-1'))!,
      engine: LudoGameEngine(
        initialState: createStartedState(),
        random: ScriptedRandom([3]),
      ),
    );
    await pumpGame(tester);

    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();

    expect(find.text('مفيش حركة متاحة'), findsOneWidget);

    await tester.pump(MatchGameProvider.rollNoticeDuration);
    await tester.pump();
    expect(find.text('مفيش حركة متاحة'), findsNothing);
  });
}
