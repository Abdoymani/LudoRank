import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ludo_rank/app/app_routes.dart';
import 'package:ludo_rank/features/splash/presentation/pages/splash_page.dart';

void main() {
  Future<void> pumpSplash(
    WidgetTester tester,
    Future<void> Function() warmUp,
  ) async {
    final router = GoRouter(
      initialLocation: AppRoutes.splash,
      routes: [
        GoRoute(
          path: AppRoutes.splash,
          builder: (_, _) => SplashPage(warmUp: warmUp),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (_, _) => const Scaffold(body: Text('home')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  }

  testWidgets('opens home after the minimum time once warm-up is done', (
    tester,
  ) async {
    await pumpSplash(tester, () async {});

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('home'), findsNothing);

    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('waits for a slow warm-up, and still opens home if it fails', (
    tester,
  ) async {
    final warmUp = Completer<void>();
    await pumpSplash(tester, () => warmUp.future);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('home'), findsNothing);

    warmUp.completeError(StateError('disk'));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });
}
