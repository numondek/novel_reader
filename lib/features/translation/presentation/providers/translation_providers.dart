import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/google_translate_service.dart';
import '../../domain/services/translation_service.dart';

final translationServiceProvider = Provider<TranslationService>(
  (ref) {
    return GoogleTranslateService();
  },
);
