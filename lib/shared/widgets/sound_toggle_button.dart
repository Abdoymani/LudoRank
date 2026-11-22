import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ludo_rank/core/audio/sound_controller.dart';

/// App bar button that turns game sounds on or off (saved across restarts).
class SoundToggleButton extends StatelessWidget {
  const SoundToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SoundController>(
      builder: (context, sound, _) {
        final enabled = sound.enabled;

        return IconButton(
          tooltip: enabled ? 'كتم الصوت' : 'تشغيل الصوت',
          icon: Icon(
            enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          ),
          onPressed: sound.toggle,
        );
      },
    );
  }
}
