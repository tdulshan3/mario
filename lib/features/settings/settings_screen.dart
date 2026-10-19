/// Settings — the redesign's two-pane layout (artboard 2f).
///
/// Categories on the left, one pane at a time on the right; the old single
/// scroll put six unrelated groups in one column and made the theme picker
/// hard to find. On a narrow window the rail collapses to a scrolling list of
/// every pane, so nothing becomes unreachable.
///
/// The design also shows a "Reduce motion" switch. Nothing in the app reads
/// such a setting yet, so it is not here — a persisted toggle that changes
/// nothing is worse than an honest omission. Wiring it means threading a flag
/// through the panel and tray animations first.
///
/// The desktop builds draw a macOS System Settings window instead
/// (mac_settings_screen.dart), a part of this library so both looks list the
/// same panes from the one [_Pane] enum.
library;

import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ui/colors.dart';
import '../../ui/mac/mac_look.dart';
import '../../ui/organic.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/mario_loader.dart';
import '../ai/ai_settings_section.dart';
import '../auth/auth_notifier.dart';
import '../shell/mac/mac_window_frame.dart';
import 'mac_settings_widgets.dart';
import 'settings_state.dart';

part 'mac_settings_screen.dart';

/// Kept in step with `version:` in pubspec.yaml by hand — the app has no
/// package_info dependency, so there is nothing to read it from at runtime.
const _kVersion = '1.3.3+15';

/// The dictation languages offered, as (name, locale code).
const _kVoiceLocales = [
  ('English (US)', 'en_US'),
  ('English (UK)', 'en_GB'),
  ('Spanish', 'es_ES'),
  ('French', 'fr_FR'),
  ('German', 'de_DE'),
  ('Japanese', 'ja_JP'),
];

enum _Pane {
  appearance(
      'Appearance', Icons.palette_outlined, 'How Mario looks while you write.'),
  editor('Editor', Icons.edit_outlined, 'How the writing surface behaves.'),
  voice('Voice', Icons.mic_none, 'Dictation and recording.'),
  ai('AI models', Icons.auto_awesome_outlined,
      'Which model answers, and with whose key.'),
  sync('Sync', Icons.sync, 'What leaves this machine.'),
  account('Account', Icons.person_outline, 'Who you are signed in as.'),
  about('About', Icons.info_outline, 'Version and build.');

  const _Pane(this.label, this.icon, this.blurb);
  final String label;
  final IconData icon;
  final String blurb;
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // The old single Anthropic-key field lived here. It is now one entry in the
  // backend list owned by AiSettingsSection; any key already in secure storage
  // is migrated into that list on first load by LlmProviderStore.
  _Pane _pane = _Pane.appearance;

  /// Below this the rail would leave the panes too narrow to read, so every
  /// pane is stacked into one scroll instead.
  static const _railBreakpoint = 780.0;

  @override
  Widget build(BuildContext context) {
    if (useMacLook) return const MacSettingsScreen();
    final settings = ref.watch(settingsProvider).valueOrNull;

    final t = marioTokens(context);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(43),
        child: Container(
          height: 43,
          decoration: BoxDecoration(
            color: t.bg,
            border: Border(bottom: BorderSide(color: t.line)),
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                const SizedBox(width: 14),
                GestureDetector(
                  onTap: () => context.pop(),
                  behavior: HitTestBehavior.opaque,
                  child: Icon(Icons.arrow_back, size: 18, color: t.sec),
                ),
                const SizedBox(width: 12),
                Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: settings == null
          ? const Center(child: MarioLoader())
          : LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < _railBreakpoint) {
                  return ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      for (final p in _Pane.values) ...[
                        _PaneBody(pane: p, settings: settings),
                        const SizedBox(height: 32),
                      ],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CategoryRail(
                      selected: _pane,
                      onSelect: (p) => setState(() => _pane = p),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(48, 44, 48, 48),
                        child: _PaneBody(pane: _pane, settings: settings),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({required this.selected, required this.onSelect});

  final _Pane selected;
  final ValueChanged<_Pane> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    return SizedBox(
      width: 220,
      child: MarioSurface(
        border: Border(right: BorderSide(color: t.line)),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final p in _Pane.values)
              _RailRow(
                pane: p,
                selected: p == selected,
                onTap: () => onSelect(p),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                'Mario $_kVersion',
                style: TextStyle(fontSize: 11.5, height: 1.2, color: t.mut),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailRow extends StatelessWidget {
  const _RailRow({
    required this.pane,
    required this.selected,
    required this.onTap,
  });

  final _Pane pane;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);

    // The artboard sets the live row apart three ways at once — a `--fill`
    // wash, a 2px accent bar, and w600 — and inset the row by 6px so the
    // rounded corners read. Idle rows carry no box at all and sit at the
    // deeper 18px indent.
    final row = SizedBox(
      height: t.row,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: selected ? 12 : 18),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            pane.label,
            style: TextStyle(
              fontSize: t.rowFontSize,
              height: 1.2,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? t.ink : t.sec,
            ),
          ),
        ),
      ),
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: selected
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(MarioRadius.xs),
                child: MarioAccentEdge(
                  child: ColoredBox(color: t.fill, child: row),
                ),
              ),
            )
          : row,
    );
  }
}

class _PaneBody extends ConsumerWidget {
  const _PaneBody({required this.pane, required this.settings});

  final _Pane pane;
  final SettingsState settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(settingsProvider.notifier);
    final user = ref.watch(authStateProvider).valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(pane.label, style: theme.textTheme.displaySmall),
        const SizedBox(height: 6),
        Text(
          pane.blurb,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.3,
            color: marioTokens(context).mut,
          ),
        ),
        const SizedBox(height: 30),
        ...switch (pane) {
          _Pane.appearance => _appearance(context, notifier),
          _Pane.editor => _editor(notifier),
          _Pane.voice => _voice(notifier),
          _Pane.ai => const [AiSettingsSection()],
          _Pane.sync => _sync(notifier),
          _Pane.account => _account(context, ref, user),
          _Pane.about => _about(context),
        },
      ],
    );
  }

  List<Widget> _appearance(BuildContext context, SettingsNotifier notifier) {
    final matchSystem = settings.themeMode == MarioThemeMode.system;
    return [
      _Row(
        label: 'Theme',
        child: _Segmented<MarioThemeMode>(
          // With "match the system" on there is no explicit ground selected,
          // so nothing is highlighted until the user picks one.
          value: matchSystem ? null : settings.themeMode,
          items: const [
            ('Light', Icons.wb_sunny_outlined, MarioThemeMode.light),
            ('White', Icons.light_mode_outlined, MarioThemeMode.white),
            ('Calm night', Icons.nightlight_outlined, MarioThemeMode.night),
            ('Black', Icons.nights_stay_outlined, MarioThemeMode.black),
          ],
          onChanged: (v) => notifier.change((s) => s.copyWith(themeMode: v)),
        ),
      ),
      _Row(
        label: 'Match the system',
        description: 'Light by day, Calm night after dark.',
        child: MarioToggle(
          value: matchSystem,
          onChanged: (on) => notifier.change(
            // Turning it off has to land on a real ground; Light is the
            // documented default and the daytime half of the system pair.
            (s) => s.copyWith(
              themeMode: on ? MarioThemeMode.system : MarioThemeMode.light,
            ),
          ),
        ),
      ),
      _Row(
        label: 'Text size',
        description: 'Applies to the page, not the interface.',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('A',
                style:
                    TextStyle(fontSize: 11.5, color: marioTokens(context).mut)),
            const SizedBox(width: 12),
            SizedBox(
              width: 200,
              child: Slider(
                value: settings.fontScale,
                min: 0.8,
                max: 1.3,
                divisions: 10,
                label: '${(settings.fontScale * 100).round()}%',
                onChanged: (v) =>
                    notifier.change((s) => s.copyWith(fontScale: v)),
              ),
            ),
            const SizedBox(width: 12),
            const Text('A', style: TextStyle(fontSize: 17)),
          ],
        ),
      ),
      _Row(
        label: 'Page width',
        description: 'How wide the writing surface runs.',
        child: _Segmented<CanvasWidth>(
          value: settings.canvasWidth,
          items: const [
            ('Narrow', null, CanvasWidth.narrow),
            ('Medium', null, CanvasWidth.medium),
            ('Full', null, CanvasWidth.full),
          ],
          onChanged: (v) => notifier.change((s) => s.copyWith(canvasWidth: v)),
        ),
      ),
    ];
  }

  List<Widget> _editor(SettingsNotifier notifier) => [
        _Row(
          label: 'Auto-correct math symbols',
          child: MarioToggle(
            value: settings.autoCorrectMath,
            onChanged: (v) =>
                notifier.change((s) => s.copyWith(autoCorrectMath: v)),
          ),
        ),
        _Row(
          label: 'Spell check',
          child: MarioToggle(
            value: settings.spellCheck,
            onChanged: (v) => notifier.change((s) => s.copyWith(spellCheck: v)),
          ),
        ),
      ];

  List<Widget> _voice(SettingsNotifier notifier) => [
        _Row(
          label: 'Hold to record',
          description: 'Off means tap to start, tap again to stop.',
          child: MarioToggle(
            value: settings.holdToRecord,
            onChanged: (v) =>
                notifier.change((s) => s.copyWith(holdToRecord: v)),
          ),
        ),
        _Row(
          label: 'Language',
          child: DropdownButton<String>(
            value: settings.voiceLocale,
            underline: const SizedBox.shrink(),
            items: _kVoiceLocales
                .map((e) => DropdownMenuItem(value: e.$2, child: Text(e.$1)))
                .toList(),
            onChanged: (v) => v == null
                ? null
                : notifier.change((s) => s.copyWith(voiceLocale: v)),
          ),
        ),
      ];

  List<Widget> _sync(SettingsNotifier notifier) => [
        _Row(
          label: 'Offline mode',
          description: 'Keep everything on this machine.',
          child: MarioToggle(
            value: settings.offlineMode,
            onChanged: (v) =>
                notifier.change((s) => s.copyWith(offlineMode: v)),
          ),
        ),
      ];

  List<Widget> _account(BuildContext context, WidgetRef ref, dynamic user) => [
        _Row(
          label: user?.email as String? ?? 'Not signed in',
          description: user?.displayName as String? ?? '',
          child: const SizedBox.shrink(),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.logout, size: 16),
            label: const Text('Sign out'),
            onPressed: () => ref.read(authNotifierProvider.notifier).signOut(),
          ),
        ),
      ];

  List<Widget> _about(BuildContext context) => [
        _Row(
            label: 'Version',
            description: _kVersion,
            child: const SizedBox.shrink()),
      ];
}

/// One setting: a label, an optional line of explanation, and its control.
///
/// The remodel turns these into a ruled stack — each row draws a hairline
/// along its top edge, so a group of them reads as a table rather than as
/// paragraphs separated by air. [MarioSettingRow] is the shared shape; this
/// only caps the control's width, which the design system has no opinion on.
class _Row extends StatelessWidget {
  const _Row({required this.label, this.description, required this.child});

  final String label;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hasDescription = description != null && description!.isNotEmpty;
    return MarioSettingRow(
      label: label,
      description: hasDescription ? description : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: child,
      ),
    );
  }
}

/// `.seg` — the design's segmented control.
///
/// A thin adapter over [MarioSegmented]: the call sites here carry an icon
/// per option, which the remodel drops (the artboard's segments are text
/// only), and a nullable value, which the design system now models directly.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  /// Null when nothing is explicitly chosen — the theme row uses this while
  /// "match the system" is on.
  final T? value;
  final List<(String, IconData?, T)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    // Scrolls rather than overflows. Four labelled options fit at the sheet's
    // full width and do not in a narrow window — and an option clipped behind
    // an overflow banner is one nobody can reach.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: MarioSegmented<T>(
        options: [for (final i in items) i.$3],
        value: value,
        onChanged: onChanged,
        labelOf: (v) => items.firstWhere((i) => i.$3 == v).$1,
      ),
    );
  }
}
