import 'package:flutter/material.dart';

import 'package:ludo_rank/shared/widgets/sound_toggle_button.dart';
import 'package:ludo_rank/shared/widgets/theme_mode_button.dart';

class AppAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool centerTitle;

  const AppAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.centerTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      centerTitle: centerTitle,
      leading: leading,
      actions: [
        ...?actions,

        const SoundToggleButton(),

        const ThemeModeButton(),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
