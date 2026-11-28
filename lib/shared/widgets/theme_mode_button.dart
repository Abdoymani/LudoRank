import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ludo_rank/app/theme_controller.dart';

/// App bar menu that picks the theme: follow the system, light or dark
/// (saved across restarts).
class ThemeModeButton extends StatelessWidget {
  const ThemeModeButton({super.key});

  static const Map<ThemeMode, String> labels = {
    ThemeMode.system: 'حسب النظام',
    ThemeMode.light: 'فاتح',
    ThemeMode.dark: 'داكن',
  };

  static const Map<ThemeMode, IconData> icons = {
    ThemeMode.system: Icons.brightness_auto_rounded,
    ThemeMode.light: Icons.light_mode_rounded,
    ThemeMode.dark: Icons.dark_mode_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeController>(
      builder: (context, themeController, _) {
        final current = themeController.themeMode;

        return PopupMenuButton<ThemeMode>(
          tooltip: 'المظهر',
          icon: Icon(icons[current]),
          initialValue: current,
          onSelected: themeController.setThemeMode,
          itemBuilder: (_) => [
            for (final mode in ThemeMode.values)
              CheckedPopupMenuItem<ThemeMode>(
                value: mode,
                checked: mode == current,
                child: Row(
                  children: [
                    Icon(icons[mode], size: 20),
                    const SizedBox(width: 10),
                    Text(labels[mode]!),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
