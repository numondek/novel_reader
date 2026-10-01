import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../reader/domain/services/text_to_speech.dart';
import '../../../reader/presentation/providers/reader_tts_controller.dart';
import '../providers/settings_provider.dart';

@RoutePage()
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  List<TtsVoice> _voices = const [];
  bool _loadingVoices = true;
  bool _spokeTest = false;

  @override
  void initState() {
    super.initState();

    Future.microtask(_loadVoices);
  }

  @override
  void dispose() {
    if (_spokeTest) {
      ref.read(ttsServiceProvider).stop();
    }

    super.dispose();
  }

  Future<void> _loadVoices() async {
    try {
      final voices = [
        ...await ref.read(ttsServiceProvider).getVoices(),
      ];

      voices.sort(
        (a, b) => a.label
            .toLowerCase()
            .compareTo(b.label.toLowerCase()),
      );

      if (!mounted) return;
      setState(() {
        _voices = voices;
        _loadingVoices = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingVoices = false);
    }
  }

  Future<void> _testVoice() async {
    final tts = ref.read(ttsServiceProvider);
    final settings = ref.read(settingsProvider);

    try {
      await tts.stop();

      const language = 'en-US';
      await tts.setLanguage(language);
      await tts.setSpeechRate(settings.speechRate);

      final name = settings.voiceName;
      if (name != null && name.isNotEmpty) {
        final locale = settings.voiceLocale ?? '';
        if (locale.isEmpty || _startsWithEn(locale)) {
          await tts.setVoice(name, locale);
        }
      }

      _spokeTest = true;
      await tts.speak(
        'This is how your reading voice sounds.',
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not play a test voice.'),
          ),
        );
    }
  }

  bool _startsWithEn(String locale) =>
      locale.toLowerCase().startsWith('en');

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    final selectedVoice = _voices.any(
      (voice) => voice.name == settings.voiceName,
    )
        ? settings.voiceName
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _sectionHeader(context, 'Reading'),
          _sliderTile(
            title: 'Font size',
            valueText: '${settings.fontSize} px',
            value: settings.fontSize
                .toDouble()
                .clamp(
                  SettingsController.minFontSize.toDouble(),
                  SettingsController.maxFontSize.toDouble(),
                ),
            min: SettingsController.minFontSize.toDouble(),
            max: SettingsController.maxFontSize.toDouble(),
            divisions:
                SettingsController.maxFontSize -
                    SettingsController.minFontSize,
            onChanged: (value) => ref
                .read(settingsProvider.notifier)
                .setFontSize(value.round()),
          ),
          SwitchListTile(
            title: const Text('Auto-scroll'),
            subtitle: const Text(
              'Follow the narration automatically',
            ),
            value: settings.autoScroll,
            onChanged: (value) => ref
                .read(settingsProvider.notifier)
                .setAutoScroll(value),
          ),
          _sectionHeader(context, 'Voice (Text-to-speech)'),
          _sliderTile(
            title: 'Speech rate',
            valueText:
                '${settings.speechRate.toStringAsFixed(2)}\u00d7',
            value: settings.speechRate.clamp(
              SettingsController.minSpeechRate,
              SettingsController.maxSpeechRate,
            ),
            min: SettingsController.minSpeechRate,
            max: SettingsController.maxSpeechRate,
            divisions: 18,
            onChanged: (value) => ref
                .read(settingsProvider.notifier)
                .setSpeechRate(value),
          ),
          ListTile(
            title: const Text('Voice'),
            subtitle: Text(
              settings.voiceName == null
                  ? 'System default'
                  : settings.voiceName!,
            ),
            trailing: _loadingVoices
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 220,
                    ),
                    child: DropdownButton<String?>(
                    value: selectedVoice,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('System default'),
                      ),
                      for (final voice in _voices)
                        DropdownMenuItem<String?>(
                          value: voice.name,
                          child: Text(
                            voice.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _voices.isEmpty
                        ? null
                        : (value) {
                            if (value == null) {
                              ref
                                  .read(settingsProvider.notifier)
                                  .setVoice(null, null);
                              return;
                            }

                            final voice = _voices.firstWhere(
                              (item) => item.name == value,
                            );

                            ref
                                .read(settingsProvider.notifier)
                                .setVoice(voice.name, voice.locale);
                          },
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: FilledButton.tonalIcon(
              onPressed: _testVoice,
              icon: const Icon(Icons.volume_up_outlined),
              label: const Text('Test voice'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    final color = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _sliderTile({
    required String title,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title)),
              Text(
                valueText,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: valueText,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
