import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_typography.dart';
import '../../../settings/presentation/providers/settings_provider.dart';

/// Bottom sheet with the speed slider of the continuous auto-scroll,
/// the pace at which a picture chapter moves past on its own.
void showScrollSpeedSettings(BuildContext context, WidgetRef ref) {
  var speed = ref.read(settingsProvider).autoScrollSpeed;

  showModalBottomSheet(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Scroll Speed', style: AppTypography.heading),
                const SizedBox(height: 4),
                Text('${speed.round()} px/s'),
                Slider(
                  min: SettingsController.minAutoScrollSpeed,
                  max: SettingsController.maxAutoScrollSpeed,
                  divisions: 38,
                  value: speed.clamp(
                    SettingsController.minAutoScrollSpeed,
                    SettingsController.maxAutoScrollSpeed,
                  ),
                  onChanged: (value) {
                    setModalState(() {
                      speed = value;
                    });

                    ref
                        .read(settingsProvider.notifier)
                        .setAutoScrollSpeed(value);
                  },
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
