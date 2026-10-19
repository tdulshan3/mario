/// Building blocks shared by the desktop Settings panes: the general panes
/// (mac_settings_screen.dart) and the AI pane (mac_ai_settings_section.dart).
///
/// A pane is a column of these, not one [MacForm]: a [MacForm] boxes every
/// child that is not a [MacFormSection], so a widget that builds its own
/// sections (the AI pane's model list, the web search block) or a row of
/// buttons under a section would land inside a second box. Each block here
/// brings its own gap above it, so a pane can stack them without knowing
/// which ones a widget left out.
library;

import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/widgets.dart';

/// Grouped sections, 20 px below whatever came before them (the kit's gap
/// between sections).
class MacSettingsGroup extends StatelessWidget {
  const MacSettingsGroup({super.key, required this.sections});

  final List<MacFormSection> sections;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: MacForm(children: sections),
    );
  }
}

/// Buttons under a section, at its right edge — where System Settings puts
/// "Add Account…" and "Advanced…".
///
/// A [Wrap], so a narrow window moves a button to a second line rather than
/// clipping it.
class MacSettingsButtons extends StatelessWidget {
  const MacSettingsButtons({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: children,
      ),
    );
  }
}

/// The symbol before a test result: a green check when it worked, a red
/// warning when it did not.
///
/// The kit has no red field or red row; the result is said in words, and the
/// symbol's colour only repeats it.
Widget macStatusSymbol(BuildContext context, {required bool ok}) {
  final c = context.macColors;
  return Icon(
    ok ? AppleIcons.checkmarkCircleFill : AppleIcons.exclamationmarkTriangle,
    size: 15,
    color: ok ? c.accentGreen : c.accentRed,
  );
}

/// A test result as a line of text after [macStatusSymbol], for places that
/// are not a grouped row (a sheet's classic form).
class MacStatusLine extends StatelessWidget {
  const MacStatusLine({super.key, required this.ok, required this.message});

  final bool ok;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          macStatusSymbol(context, ok: ok),
          const SizedBox(width: 6),
          Expanded(
            child: Text(message, style: MacTypography.of(context).body),
          ),
        ],
      ),
    );
  }
}
