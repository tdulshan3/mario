/// A tooltip per segment of an icon-only `MacSegmentedControl`.
///
/// apple_ui takes a segmented control's segments as data, so there is no
/// widget per segment to hang a `MacTooltip` on — and the format bar's
/// segments are exactly the controls that need one most: "Bold (Ctrl+B)" is
/// how anyone finds the shortcut. Icon segments of one control are all as
/// wide as each other (`equal: true`), so the segment under the pointer is
/// simply which n-th of the control it is over.
library;

import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/widgets.dart';

/// Shows [messages]`[i]` as a macOS tooltip while the pointer rests on the
/// i-th of [child]'s equal-width segments.
///
/// The tooltip is keyed by the segment, so moving to the next segment starts
/// a fresh tooltip (as macOS does) instead of relabelling the open one where
/// it stands. The control itself sits under a [GlobalKey] so that swapping
/// the tooltip around it never rebuilds it: its focus and press state live
/// through the move.
class MacSegmentTooltips extends StatefulWidget {
  const MacSegmentTooltips({
    super.key,
    required this.messages,
    required this.child,
  });

  /// One message per segment, in segment order.
  final List<String> messages;

  /// A `MacSegmentedControl` whose segments are all the same width.
  final Widget child;

  @override
  State<MacSegmentTooltips> createState() => _MacSegmentTooltipsState();
}

class _MacSegmentTooltipsState extends State<MacSegmentTooltips> {
  final GlobalKey _controlKey = GlobalKey();
  int? _hovered;

  void _track(Offset local) {
    final box = context.findRenderObject();
    final count = widget.messages.length;
    if (box is! RenderBox || !box.hasSize || count == 0) return;
    final width = box.size.width;
    if (width <= 0) return;
    final index = (local.dx / width * count).floor().clamp(0, count - 1);
    if (index != _hovered) setState(() => _hovered = index);
  }

  void _leave() {
    if (_hovered != null) setState(() => _hovered = null);
  }

  @override
  Widget build(BuildContext context) {
    Widget control = KeyedSubtree(key: _controlKey, child: widget.child);
    final index = _hovered;
    if (index != null && index < widget.messages.length) {
      control = MacTooltip(
        key: ValueKey<int>(index),
        message: widget.messages[index],
        child: control,
      );
    }
    return MouseRegion(
      opaque: false,
      hitTestBehavior: HitTestBehavior.deferToChild,
      onEnter: (e) => _track(e.localPosition),
      onHover: (e) => _track(e.localPosition),
      onExit: (_) => _leave(),
      child: control,
    );
  }
}
