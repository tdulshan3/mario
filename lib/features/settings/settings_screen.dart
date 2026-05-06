/// Settings — appearance, editor, voice, AI key, account.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../auth/auth_notifier.dart';
import 'settings_state.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  bool _apiKeyHidden = true;
  bool _apiKeyLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final notifier = ref.read(settingsProvider.notifier);
    final key = await notifier.getApiKey();
    if (!mounted) return;
    setState(() {
      _apiKeyController.text = key ?? '';
      _apiKeyLoaded = true;
    });
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final notifier = ref.read(settingsProvider.notifier);
    final user = ref.watch(authStateProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Settings'),
      ),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Section(title: 'Appearance', children: [
                  _DropdownTile<ThemeMode>(
                    label: 'Theme',
                    value: settings.themeMode,
                    items: const [
                      ('System', ThemeMode.system),
                      ('Light', ThemeMode.light),
                      ('Dark', ThemeMode.dark),
                    ],
                    onChanged: (v) =>
                        notifier.change((s) => s.copyWith(themeMode: v)),
                  ),
                  _SliderTile(
                    label: 'Font scale',
                    value: settings.fontScale,
                    min: 0.8,
                    max: 1.3,
                    divisions: 10,
                    onChanged: (v) =>
                        notifier.change((s) => s.copyWith(fontScale: v)),
                  ),
                  _DropdownTile<CanvasWidth>(
                    label: 'Canvas width',
                    value: settings.canvasWidth,
                    items: const [
                      ('Narrow', CanvasWidth.narrow),
                      ('Medium', CanvasWidth.medium),
                      ('Full', CanvasWidth.full),
                    ],
                    onChanged: (v) =>
                        notifier.change((s) => s.copyWith(canvasWidth: v)),
                  ),
                ]),
                _Section(title: 'Editor', children: [
                  _SwitchTile(
                    label: 'Auto-correct math symbols',
                    value: settings.autoCorrectMath,
                    onChanged: (v) =>
                        notifier.change((s) => s.copyWith(autoCorrectMath: v)),
                  ),
                  _SwitchTile(
                    label: 'Spell check',
                    value: settings.spellCheck,
                    onChanged: (v) =>
                        notifier.change((s) => s.copyWith(spellCheck: v)),
                  ),
                ]),
                _Section(title: 'Voice', children: [
                  _SwitchTile(
                    label: 'Hold-to-record (off = tap-to-record)',
                    value: settings.holdToRecord,
                    onChanged: (v) =>
                        notifier.change((s) => s.copyWith(holdToRecord: v)),
                  ),
                  _DropdownTile<String>(
                    label: 'Language',
                    value: settings.voiceLocale,
                    items: const [
                      ('English (US)', 'en_US'),
                      ('English (UK)', 'en_GB'),
                      ('Spanish', 'es_ES'),
                      ('French', 'fr_FR'),
                      ('German', 'de_DE'),
                      ('Japanese', 'ja_JP'),
                    ],
                    onChanged: (v) =>
                        notifier.change((s) => s.copyWith(voiceLocale: v)),
                  ),
                ]),
                _Section(title: 'AI features', children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Add an Anthropic API key to enable inline AI suggestions and /summary. Get one at console.anthropic.com.',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6)),
                    ),
                  ),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: _apiKeyHidden,
                    enabled: _apiKeyLoaded,
                    decoration: InputDecoration(
                      labelText: 'Anthropic API key',
                      hintText: 'sk-ant-…',
                      suffixIcon: IconButton(
                        icon: Icon(_apiKeyHidden
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () =>
                            setState(() => _apiKeyHidden = !_apiKeyHidden),
                      ),
                    ),
                    onSubmitted: (v) async {
                      final messenger = ScaffoldMessenger.of(context);
                      await notifier.setApiKey(v.trim());
                      if (!mounted) return;
                      messenger.showSnackBar(const SnackBar(
                        content: Text('API key saved'),
                      ));
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () async {
                          await notifier.setApiKey(null);
                          if (!mounted) return;
                          setState(() => _apiKeyController.text = '');
                        },
                        child: const Text('Clear'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await notifier
                              .setApiKey(_apiKeyController.text.trim());
                          if (!mounted) return;
                          messenger.showSnackBar(const SnackBar(
                              content: Text('API key saved')));
                        },
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ]),
                _Section(title: 'Sync', children: [
                  _SwitchTile(
                    label: 'Offline mode',
                    value: settings.offlineMode,
                    onChanged: (v) =>
                        notifier.change((s) => s.copyWith(offlineMode: v)),
                  ),
                ]),
                _Section(title: 'Account', children: [
                  ListTile(
                    title: Text(user?.email ?? 'Not signed in'),
                    subtitle: Text(user?.displayName ?? ''),
                    contentPadding: EdgeInsets.zero,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.logout, size: 16),
                      label: const Text('Sign out'),
                      onPressed: () =>
                          ref.read(authNotifierProvider.notifier).signOut(),
                    ),
                  ),
                ]),
                _Section(title: 'About', children: [
                  ListTile(
                    title: const Text('Version'),
                    subtitle: const Text('1.0.0+1'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ]),
              ],
            ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.55),
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _DropdownTile<T> extends StatelessWidget {
  const _DropdownTile({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String label;
  final T value;
  final List<(String, T)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 13))),
          DropdownButton<T>(
            value: value,
            items: items
                .map((e) =>
                    DropdownMenuItem<T>(value: e.$2, child: Text(e.$1)))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 13))),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 13))),
          SizedBox(
            width: 200,
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: '${(value * 100).toStringAsFixed(0)}%',
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
