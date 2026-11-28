import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ludo_rank/app/app.dart';

import 'initialize.dart';

Future<void> bootstrap() async {
  await initialize();

  // Draw behind the status and navigation bars (Android 15+ does this
  // anyway); AppSystemBars keeps both transparent over the app's own
  // background, so there is no grey system bar at the bottom.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const LudoRankApp());
}
