part of 'settings_screen.dart';

/// Settings on the desktop builds: a macOS System Settings window.
///
///   sidebar     every pane, each with its coloured icon square, in three
///               groups (how Mario looks and writes · where answers and
///               notes go · who and what version); the window's lights in
///               its header where Mario draws its own frame
///   toolbar     Back (and Escape) to return to the notes, then the pane's
///               name as the window title
///   content     the pane as a grouped form, at most 640 wide and centred:
///               a header row (icon, name, what the pane is for), then its
///               sections. Settings apply at once; nothing needs saving.
///
/// It keeps every pane and every setting of the Material screen, with these
/// differences of the look rather than of what can be set:
///
/// * **Appearance** is Auto / Light / Dark, the three appearances macOS has.
///   The desktop draws one Light and one Dark (see [macThemeModeFor]), so a
///   stored White shows as Light and Black as Dark. Picking the appearance
///   that is already shown writes nothing, so those grounds survive for the
///   Material look; picking another stores System, Light or Calm night.
///   "Match the system" is the Auto segment, not a separate switch.
/// * The version, which the Material rail repeats at its foot, is in About
///   only: a sidebar on macOS lists places, not facts.
///
/// There are no accent or density pickers to hide: neither look offers
/// them as settings.
class MacSettingsScreen extends ConsumerStatefulWidget {
  const MacSettingsScreen({super.key});

  @override
  ConsumerState<MacSettingsScreen> createState() => _MacSettingsScreenState();
}

/// The sidebar's groups, in the order of the Material rail.
const _macPaneGroups = [
  [_Pane.appearance, _Pane.editor, _Pane.voice],
  [_Pane.ai, _Pane.sync],
  [_Pane.account, _Pane.about],
];

/// A pane's System Settings–style icon square.
extension on _Pane {
  MacFormIcon macIcon(MacColors c, {bool large = false}) {
    final (IconData icon, Color color) = switch (this) {
      _Pane.appearance => (CupertinoIcons.circle_lefthalf_fill, c.accentIndigo),
      _Pane.editor => (AppleIcons.pencil, c.accentOrange),
      _Pane.voice => (AppleIcons.mic, c.accentRed),
      _Pane.ai => (CupertinoIcons.sparkles, c.accentPurple),
      _Pane.sync => (AppleIcons.icloud, c.accentCyan),
      _Pane.account => (AppleIcons.personFill, c.accentBlue),
      _Pane.about => (AppleIcons.infoCircle, c.gray),
    };
    return MacFormIcon(icon, color: color, large: large);
  }
}

class _MacSettingsScreenState extends ConsumerState<MacSettingsScreen> {
  _Pane _pane = _Pane.appearance;

  /// Holds the keyboard focus when no control has it, so Escape always
  /// reaches the window.
  final _focus = FocusNode(debugLabel: 'MacSettingsScreen');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Back to the notes.
  ///
  /// The shell opens Settings with `context.push`, the AI panel with a plain
  /// route; popping the navigator undoes either. A window that opened
  /// straight on /settings has nothing under it, so it goes home instead.
  void _back() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      GoRouter.maybeOf(context)?.go('/');
    }
  }

  /// Escape inside a text field only leaves the field — a half-typed key is
  /// not thrown away by a reflex — and the next Escape goes back.
  void _onEscape() {
    final focused = FocusManager.instance.primaryFocus;
    final inField =
        focused?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (inField) {
      _focus.requestFocus();
      return;
    }
    _back();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final c = context.macColors;
    final lights = macWindowLights();

    final sidebar = MacSidebar(
      width: 220,
      semanticLabel: 'Settings',
      // A header row only to hold macOS's own traffic lights; on Linux and
      // Windows the system title bar has the window buttons and the list
      // starts at the top.
      header: lights == null
          ? null
          : [
              MacWindowDragArea(
                child: SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: lights,
                  ),
                ),
              ),
            ],
      children: [
        for (final (i, group) in _macPaneGroups.indexed) ...[
          // System Settings sets its groups apart with space, not titles.
          if (i > 0) const SizedBox(height: 10),
          MacSidebarSection(
            children: [
              for (final p in group)
                MacSidebarItem(
                  image: p.macIcon(c),
                  label: p.label,
                  selected: p == _pane,
                  onPressed: () => setState(() => _pane = p),
                ),
            ],
          ),
        ],
      ],
    );

    final titlebar = MacWindowDragArea(
      child: MacTitlebar(
        title: _pane.label,
        leading: [
          MacToolbarButton(
            icon: AppleIcons.chevronLeft,
            label: 'Back',
            onPressed: _back,
          ),
        ],
      ),
    );

    final Widget content;
    if (settings == null) {
      content = const MacContent(
        scroll: false,
        child: Center(
          child: MacSpinner(large: true, semanticLabel: 'Loading settings'),
        ),
      );
    } else {
      content = MacContent(
        // A new pane starts at its top, not at the last pane's offset.
        key: ValueKey(_pane),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            // Label and value rows stop being readable as pairs when they
            // run the width of a wide window (the kit's form rule).
            constraints: const BoxConstraints(maxWidth: 640),
            child: _MacPaneBody(pane: _pane, settings: settings),
          ),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _onEscape,
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: MacWindow(sidebar: sidebar, titlebar: titlebar, child: content),
      ),
    );
  }
}

/// One pane: its header row, then its sections.
class _MacPaneBody extends ConsumerWidget {
  const _MacPaneBody({required this.pane, required this.settings});

  final _Pane pane;
  final SettingsState settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(settingsProvider.notifier);
    final user = ref.watch(authStateProvider).valueOrNull;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The header System Settings puts at the top of a pane: what this
        // pane is for, next to its icon.
        MacForm(
          children: [
            MacFormSection(
              children: [
                MacFormRow(
                  label: pane.label,
                  subtitle: pane.blurb,
                  icon: pane.macIcon(context.macColors, large: true),
                ),
              ],
            ),
          ],
        ),
        ...switch (pane) {
          _Pane.appearance => _appearance(context, notifier),
          _Pane.editor => _editor(notifier),
          _Pane.voice => _voice(notifier),
          _Pane.ai => const [AiSettingsSection()],
          _Pane.sync => _sync(notifier),
          _Pane.account => _account(ref, user?.email, user?.displayName),
          _Pane.about => _about(),
        },
      ],
    );
  }

  List<Widget> _appearance(BuildContext context, SettingsNotifier notifier) {
    final c = context.macColors;
    final t = MacTypography.of(context);
    final shown = macThemeModeFor(settings.themeMode);
    return [
      MacSettingsGroup(
        sections: [
          MacFormSection(
            footer: 'Auto switches between Light and Dark with the system.',
            children: [
              MacFormRow(
                label: 'Appearance',
                child: MacSegmentedControl<ThemeMode>(
                  segments: const [
                    MacSegment(value: ThemeMode.system, label: 'Auto'),
                    MacSegment(value: ThemeMode.light, label: 'Light'),
                    MacSegment(value: ThemeMode.dark, label: 'Dark'),
                  ],
                  value: shown,
                  equal: true,
                  onChanged: (mode) {
                    // The appearance already shown is no change, even when
                    // the stored ground is White or Black: keep it.
                    if (mode == shown) return;
                    notifier.change(
                      (s) => s.copyWith(
                        themeMode: switch (mode) {
                          ThemeMode.system => MarioThemeMode.system,
                          ThemeMode.light => MarioThemeMode.light,
                          ThemeMode.dark => MarioThemeMode.night,
                        },
                      ),
                    );
                  },
                  semanticLabel: 'Appearance',
                ),
              ),
            ],
          ),
          MacFormSection(
            children: [
              MacFormRow(
                label: 'Text size',
                subtitle: 'Applies to the page, not the interface.',
                value: '${(settings.fontScale * 100).round()}%',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8,
                  children: [
                    // A small and a large A name the slider's two ends.
                    ExcludeSemantics(
                      child: Text(
                        'A',
                        style: t.subheadline.copyWith(color: c.labelSecondary),
                      ),
                    ),
                    SizedBox(
                      width: 160,
                      child: MacSlider(
                        value: settings.fontScale.clamp(0.8, 1.3),
                        min: 0.8,
                        max: 1.3,
                        // 0.80, 0.85 … 1.30: the Material slider's ten steps.
                        ticks: 11,
                        onChanged: (v) => notifier.change(
                          (s) => s.copyWith(fontScale: (v * 100).round() / 100),
                        ),
                        semanticLabel: 'Text size',
                      ),
                    ),
                    ExcludeSemantics(
                      child: Text(
                        'A',
                        style: t.title3.copyWith(color: c.labelSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              MacFormRow(
                label: 'Page width',
                subtitle: 'How wide the writing surface runs.',
                child: MacSegmentedControl<CanvasWidth>(
                  segments: const [
                    MacSegment(value: CanvasWidth.narrow, label: 'Narrow'),
                    MacSegment(value: CanvasWidth.medium, label: 'Medium'),
                    MacSegment(value: CanvasWidth.full, label: 'Full'),
                  ],
                  value: settings.canvasWidth,
                  equal: true,
                  onChanged: (v) =>
                      notifier.change((s) => s.copyWith(canvasWidth: v)),
                  semanticLabel: 'Page width',
                ),
              ),
            ],
          ),
        ],
      ),
    ];
  }

  List<Widget> _editor(SettingsNotifier notifier) => [
        MacSettingsGroup(
          sections: [
            MacFormSection(
              children: [
                MacFormRow(
                  label: 'Auto-correct math symbols',
                  child: MacSwitch(
                    value: settings.autoCorrectMath,
                    onChanged: (v) =>
                        notifier.change((s) => s.copyWith(autoCorrectMath: v)),
                    semanticLabel: 'Auto-correct math symbols',
                  ),
                ),
                MacFormRow(
                  label: 'Spell check',
                  child: MacSwitch(
                    value: settings.spellCheck,
                    onChanged: (v) =>
                        notifier.change((s) => s.copyWith(spellCheck: v)),
                    semanticLabel: 'Spell check',
                  ),
                ),
              ],
            ),
          ],
        ),
      ];

  List<Widget> _voice(SettingsNotifier notifier) {
    // A locale stored by an older build stays choosable rather than
    // leaving the pop-up without a current value.
    final locales = [
      for (final l in _kVoiceLocales) l.$2,
      if (!_kVoiceLocales.any((l) => l.$2 == settings.voiceLocale))
        settings.voiceLocale,
    ];
    return [
      MacSettingsGroup(
        sections: [
          MacFormSection(
            children: [
              MacFormRow(
                label: 'Hold to record',
                subtitle: 'Off means tap to start, tap again to stop.',
                child: MacSwitch(
                  value: settings.holdToRecord,
                  onChanged: (v) =>
                      notifier.change((s) => s.copyWith(holdToRecord: v)),
                  semanticLabel: 'Hold to record',
                ),
              ),
              MacFormRow(
                label: 'Language',
                child: MacFormPopUp<String>(
                  options: locales,
                  value: settings.voiceLocale,
                  labelOf: (code) => _kVoiceLocales
                      .firstWhere((l) => l.$2 == code,
                          orElse: () => (code, code))
                      .$1,
                  onChanged: (v) =>
                      notifier.change((s) => s.copyWith(voiceLocale: v)),
                  semanticLabel: 'Language',
                ),
              ),
            ],
          ),
        ],
      ),
    ];
  }

  List<Widget> _sync(SettingsNotifier notifier) => [
        MacSettingsGroup(
          sections: [
            MacFormSection(
              children: [
                MacFormRow(
                  label: 'Offline mode',
                  subtitle: 'Keep everything on this machine.',
                  child: MacSwitch(
                    value: settings.offlineMode,
                    onChanged: (v) =>
                        notifier.change((s) => s.copyWith(offlineMode: v)),
                    semanticLabel: 'Offline mode',
                  ),
                ),
              ],
            ),
          ],
        ),
      ];

  List<Widget> _account(WidgetRef ref, String? email, String? displayName) => [
        MacSettingsGroup(
          sections: [
            MacFormSection(
              children: [
                MacFormRow(
                  label: email ?? 'Not signed in',
                  subtitle: (displayName == null || displayName.isEmpty)
                      ? null
                      : displayName,
                  child: MacButton(
                    label: 'Sign Out',
                    onPressed: () =>
                        ref.read(authNotifierProvider.notifier).signOut(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ];

  List<Widget> _about() => const [
        MacSettingsGroup(
          sections: [
            MacFormSection(
              children: [MacFormRow(label: 'Version', value: _kVersion)],
            ),
          ],
        ),
      ];
}
