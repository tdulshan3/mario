/// The keyboard shortcuts help (Ctrl+/) on the desktop builds: a sheet that
/// lists every shortcut as a form row — what it does on the left, its keys
/// on the right in the secondary label colour — with Done.
///
/// The rows are [kShortcutHelp], the list the Material dialog shows. All ten
/// fit a sheet in the smallest window Mario allows (800 × 600), so the list
/// does not scroll; `test/mac_shortcuts_help_test.dart` holds it to that.
library;

import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/widgets.dart';

import 'keyboard_shortcuts.dart';

/// Wide enough for the longest action and its keys side by side.
const double _kSheetWidth = 440;

Future<void> showMacShortcutsHelp(BuildContext context) => showMacSheet<void>(
      context: context,
      builder: (_) => const MacShortcutsSheet(),
    );

class MacShortcutsSheet extends StatelessWidget {
  const MacShortcutsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    void done() => Navigator.of(context).pop();
    // Nothing to confirm or cancel: Return and Escape both just close it.
    return MacSheet(
      title: 'Keyboard Shortcuts',
      width: _kSheetWidth,
      onSubmit: done,
      onCancel: done,
      actions: [
        MacButton(
          label: 'Done',
          style: MacButtonStyle.prominent,
          onPressed: done,
        ),
      ],
      child: MacForm(
        children: [
          MacFormSection(
            children: [
              for (final s in kShortcutHelp)
                MacFormRow(label: s.label, value: s.keys),
            ],
          ),
        ],
      ),
    );
  }
}
