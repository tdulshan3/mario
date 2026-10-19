import 'package:flutter/widgets.dart';

import '../core/theme.dart';
import '../core/typography.dart';

/// A macOS group box (kit page "Group Boxes"): a rounded (12 px), very lightly filled box (black 1.5 % /
/// white 1.5 %) around a few related controls, with an optional small title above it. No border, no shadow,
/// not interactive. Don't nest group boxes; leave 20 px between a group box and the next group.
///
///     MacGroupBox(
///       title: 'Playback',                         // optional: 11 px title, 6 px in, 4 px above the box
///       child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
///         MacCheckbox(label: 'Loop', value: loop, onChanged: (v) => setState(() => loop = v)),
///         const SizedBox(height: 8),
///         MacCheckbox(label: 'Shuffle', value: shuffle, onChanged: (v) => setState(() => shuffle = v)),
///       ]),
///     )
///
/// For label + control rows in a settings window use `MacForm` instead; for dashboard tiles use `MacTile`.
class MacGroupBox extends StatelessWidget {
  const MacGroupBox({super.key, this.title, required this.child, this.padding = const EdgeInsets.all(12)});

  /// Short Title Case name without a colon ("Audio Output"). Null = no title.
  final String? title;
  final Widget child;

  /// Space between the box edge and the content (12 by default, like macOS).
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    // Kit: Fills-Opaque/Quaternary (black 3 % · white 3 %) at 50 % layer opacity = black 1.5 % · white 1.5 %.
    final q = theme.mac.fillQuaternary;
    final box = DecoratedBox(
      decoration: ShapeDecoration(
        color: q.withValues(alpha: q.a * 0.5),
        shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(12)),
      ),
      // Like a block element: as wide as the space it gets (or as its content when the width is unbounded).
      child: Align(
        alignment: AlignmentDirectional.topStart,
        heightFactor: 1,
        child: Padding(
          padding: padding,
          child: DefaultTextStyle(style: MacTypography.of(context).body, child: child),
        ),
      ),
    );
    if (title == null) return box;
    final t = MacTypography.of(context);
    return Semantics(
      container: true,
      label: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: ExcludeSemantics(
              child: Text(title!, style: t.subheadline.copyWith(fontWeight: FontWeight.w500)), // 11 / 14 Medium, label primary
            ),
          ),
          const SizedBox(height: 4),
          box,
        ],
      ),
    );
  }
}
