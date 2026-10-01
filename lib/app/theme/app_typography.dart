import 'package:flutter/material.dart';

import 'app_text_styles.dart';

abstract final class AppTypography {
  static const TextStyle heading = AppTextStyles.titleLarge;

  static const TextStyle title = AppTextStyles.titleMedium;

  static const TextStyle body = AppTextStyles.bodyLarge;

  static const TextStyle bodySecondary = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: Color(0xFF6E6E78),
  );

  static const TextStyle caption = AppTextStyles.labelMedium;
}
