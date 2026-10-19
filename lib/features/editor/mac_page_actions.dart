/// The page actions at the end of the macOS format bar.
///
/// The desktop counterpart of the Material `_PageActions` in
/// `editor_screen.dart`: the save state, Export…, dictation, Draw and a More
/// pull-down with the two actions that have no button of their own. Same
/// callbacks, same words, macOS controls.
library;

import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

import 'save_status.dart';

class MacPageActions extends StatelessWidget {
  const MacPageActions({
    super.key,
    required this.status,
    required this.lastSavedAt,
    required this.pendingImages,
    required this.pendingChanges,
    required this.drawMode,
    required this.previewMode,
    required this.onExport,
    required this.onToggleDraw,
    required this.onTogglePreview,
    required this.onSaveNow,
    required this.dictate,
  });

  final SaveStatus status;
  final DateTime? lastSavedAt;

  /// Images in this page that haven't reached Drive yet.
  final int pendingImages;

  /// Changes made on this device that the server has not heard about yet.
  final int pendingChanges;

  final bool drawMode;
  final bool previewMode;
  final VoidCallback onExport;
  final VoidCallback onToggleDraw;
  final VoidCallback onTogglePreview;
  final VoidCallback onSaveNow;

  /// The app's single dictation control (one instance: two would fight over
  /// the same VoiceService session).
  final Widget dictate;

  @override
  Widget build(BuildContext context) {
    final c = context.macColors;
    final label = saveStatusLabel(
      status: status,
      lastSavedAt: lastSavedAt,
      pendingImages: pendingImages,
      pendingChanges: pendingChanges,
    );
    final drawLabel = drawMode ? 'Exit drawing mode' : 'Draw on this page';

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        // The one part that may give way: with every suffix the line is
        // longer than a narrow window has room for, and the tooltip still
        // carries all of it.
        Flexible(
          child: MacTooltip(
            message: pendingImages > 0
                ? '$pendingImages image(s) still uploading'
                : label,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: MacTypography.of(context).subheadline.copyWith(
                    color: status == SaveStatus.error
                        ? c.accentRed
                        : c.labelSecondary,
                  ),
            ),
          ),
        ),
        MacTooltip(
          message: 'Export this page',
          child: MacButton(label: 'Export…', onPressed: onExport),
        ),
        dictate,
        MacTooltip(
          message: drawLabel,
          child: MacButton(
            icon: CupertinoIcons.hand_draw,
            semanticLabel: drawLabel,
            isOn: drawMode,
            onPressed: onToggleDraw,
          ),
        ),
        MacTooltip(
          message: 'More',
          child: MacPullDownButton(
            icon: AppleIcons.ellipsis,
            semanticLabel: 'More',
            items: [
              MacMenuItem(
                label: previewMode ? 'Hide HTML Preview' : 'Show HTML Preview',
                onSelected: onTogglePreview,
              ),
              MacMenuItem(
                label: 'Save Now',
                shortcut: 'Ctrl+S',
                onSelected: onSaveNow,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
