import 'package:flutter/widgets.dart';

import '../core/icons.dart';
import '../core/theme.dart';
import '_chrome.dart';
import 'scroll_views.dart';

/// The inspector: the details pane on the right of a window (SwiftUI `.inspector`), drawn with the window
/// background and a separator on its left. 280 px wide (220–340). Put it in `MacWindow(inspector: …)` and show or
/// hide it from a toolbar button (`AppleIcons.sidebarRight`, `pressed: showInspector`) and the View menu.
///
///     MacWindow(
///       titlebar: MacTitlebar(title: 'Photos', actions: [
///         MacToolbarButton(icon: AppleIcons.sidebarRight, label: 'Show Inspector', pressed: showInspector,
///                          onPressed: () => setState(() => showInspector = !showInspector)),
///       ]),
///       inspector: !showInspector ? null
///           : selected == null ? const MacInspector.noSelection()
///           : MacInspector(child: MacForm(children: [ … ])),          // usually a grouped form (forms.md)
///       child: MacContent(child: grid),
///     )
/// The child scrolls and gets 12 px padding (forms sit closer to the edges than in a window).
class MacInspector extends StatelessWidget {
  const MacInspector({
    super.key,
    required Widget this.child,
    this.width = 280,
    this.padding = const EdgeInsets.all(12),
    this.semanticLabel = 'Inspector',
  }) : icon = null,
       title = null,
       message = null;

  /// Nothing selected: a centred icon, "No Selection" and a hint instead of the form.
  const MacInspector.noSelection({
    super.key,
    IconData this.icon = AppleIcons.doc,
    String this.title = 'No Selection',
    this.message = 'Select an item to see its details.',
    this.width = 280,
    this.semanticLabel = 'Inspector',
  }) : child = null,
       padding = const EdgeInsets.all(20);

  final Widget? child;

  /// Default 280 (SwiftUI range 220–340).
  final double width;
  final EdgeInsetsGeometry padding;
  final String semanticLabel;

  /// [MacInspector.noSelection] only.
  final IconData? icon;
  final String? title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.mac;
    Widget content;
    if (child != null) {
      content = MacScrollView(padding: padding, fillViewport: false, child: child!);
    } else {
      // `.mac-inspector__empty`: icon 32 tertiary, title 15 Semibold primary, message 13 secondary, 6 px apart.
      content = Padding(
        padding: padding,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              if (icon != null) Icon(icon, size: 32, color: c.labelTertiary),
              if (title != null)
                Text(
                  title!,
                  textAlign: TextAlign.center,
                  style: macChromeText(15, 16, c.labelPrimary, weight: FontWeight.w600),
                ),
              if (message != null) Text(message!, textAlign: TextAlign.center, style: macChromeText(13, 16, c.labelSecondary)),
            ],
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      label: semanticLabel,
      explicitChildNodes: true,
      child: SizedBox(
        width: width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.windowBg,
            border: Border(left: BorderSide(color: c.separator)),
          ),
          child: Padding(padding: const EdgeInsets.only(left: 1), child: content),
        ),
      ),
    );
  }
}
