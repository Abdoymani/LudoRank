import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:ludo_rank/app/app_routes.dart';
import 'package:ludo_rank/core/database/database.dart';
import 'package:ludo_rank/core/dependency_injection/injection_container.dart';

class SplashPage extends StatefulWidget {
  /// Work the splash waits for before opening home. Defaults to opening
  /// the database (which runs any schema upgrade), so home's first query
  /// does not pay for it.
  final Future<void> Function() warmUp;

  /// Shortest time the splash stays, so it does not just flash.
  final Duration minimumDuration;

  const SplashPage({
    super.key,
    this.warmUp = openDatabase,
    this.minimumDuration = const Duration(milliseconds: 600),
  });

  static Future<void> openDatabase() async {
    await sl<AppDatabase>().customSelect('SELECT 1').get();
  }

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  static const Color navy = Color(0xFF06183A);
  static const Color gold = Color(0xFFD9B45F);
  static const Color frameGold = Color(0xFFAD805F);

  late final AnimationController _logoAnimationController;
  late final Animation<double> _logoFadeAnimation;

  @override
  void initState() {
    super.initState();

    _logoAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _logoFadeAnimation = CurvedAnimation(
      parent: _logoAnimationController,
      curve: Curves.easeIn,
    );

    _logoAnimationController.forward();

    unawaited(_openHomeWhenReady());
  }

  Future<void> _openHomeWhenReady() async {
    await Future.wait([
      _warmUp(),
      Future<void>.delayed(widget.minimumDuration),
    ]);

    if (mounted) {
      context.go(AppRoutes.home);
    }
  }

  Future<void> _warmUp() async {
    try {
      await widget.warmUp();
    } catch (error) {
      // Home shows its own error and retry if the database is unusable.
      debugPrint('Splash warm-up failed: $error');
    }
  }

  @override
  void dispose() {
    _logoAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: navy,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: navy,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: navy,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double logoWidth = math.min(
                constraints.maxWidth * 0.72,
                155,
              );

              final double gameLogoSize = math.min(
                constraints.maxWidth * 0.88,
                350,
              );

              final pixelRatio = MediaQuery.devicePixelRatioOf(context);

              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Iso Developers brand
                        FadeTransition(
                          opacity: _logoFadeAnimation,
                          child: Image.asset(
                            'assets/images/branding/iso_developers.png',
                            width: logoWidth,
                            fit: BoxFit.contain,
                          ),
                        ),

                        const SizedBox(height: 28),

                        // LudoRank logo frame
                        Container(
                          width: gameLogoSize,
                          height: gameLogoSize,
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: frameGold,
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.asset(
                              'assets/images/branding/ludorank_logo.png',
                              fit: BoxFit.cover,
                              // The asset is 512px; decode no larger than
                              // what is shown.
                              cacheWidth: math.min(
                                512,
                                (gameLogoSize * pixelRatio).round(),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Game name
                        const Text(
                          'LudoRank',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: gold,
                            fontSize: 48,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Tagline
                        const Text(
                          'PLAY • COMPETE • RANK',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),

                        const SizedBox(height: 28),

                        // Loading indicator
                        Column(
                          children: [
                            SizedBox(
                              width: 150,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: const LinearProgressIndicator(
                                  minHeight: 9,
                                  backgroundColor: Color(0xFF23375B),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    gold,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 14),

                            const Text(
                              'Loading...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 25,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
