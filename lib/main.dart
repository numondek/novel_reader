import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'features/reader/data/services/audio_service_media_session.dart';
import 'features/reader/data/services/audio_session_playback_interruptions.dart';
import 'features/reader/presentation/providers/reader_tts_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final mediaSession = await createAudioServiceMediaSession();
  final playbackInterruptions =
      await AudioSessionPlaybackInterruptions.create();

  runApp(
    ProviderScope(
      overrides: [
        mediaSessionProvider.overrideWithValue(mediaSession),
        playbackInterruptionsProvider.overrideWithValue(
          playbackInterruptions,
        ),
      ],
      child: const NovelFlowApp(),
    ),
  );
}
