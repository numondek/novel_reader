import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_typography.dart';
import '../../../settings/presentation/providers/settings_provider.dart';

/// Bottom sheet with the reader's font size slider.
void showFontSizeSettings(BuildContext context, WidgetRef ref) {
  var fontSize = ref.read(settingsProvider).fontSize;

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
                const Text('Font Size', style: AppTypography.heading),
                Slider(
                  min: 14,
                  max: 32,
                  divisions: 18,
                  value: fontSize.toDouble(),
                  onChanged: (value) {
                    setModalState(() {
                      fontSize = value.round();
                    });

                    ref
                        .read(settingsProvider.notifier)
                        .setFontSize(value.round());
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
