import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ludo_rank/app/theme_controller.dart';
import 'package:ludo_rank/core/settings/app_settings.dart';
import 'package:ludo_rank/shared/widgets/theme_mode_button.dart';

void main() {
  testWidgets('picks system, light or dark and saves it', (tester) async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
    final settings = await AppSettings.load();
    final controller = ThemeController(settings: settings);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: Scaffold(appBar: AppBar(actions: const [ThemeModeButton()])),
        ),
      ),
    );
    expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);

    await tester.tap(find.byTooltip('المظهر'));
    await tester.pumpAndSettle();
    expect(find.text('حسب النظام'), findsOneWidget);
    expect(find.text('فاتح'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<ThemeMode>, 'حسب النظام'),
    );
    await tester.pumpAndSettle();

    expect(controller.themeMode, ThemeMode.system);
    expect(find.byIcon(Icons.brightness_auto_rounded), findsOneWidget);
    expect((await AppSettings.load()).themeMode, 'system');
  });
}
