import 'package:flutter/widgets.dart';

import '../core/theme.dart';
import '../core/typography.dart';

/// Small 32 tall (the default) · Large 50 tall (kit Size).
enum IosSegmentedControlSize { small, large }

/// One segment of an [IosSegmentedControl]: a text label, a symbol, or both.
class IosSegment<T> {
  const IosSegment({required this.value, this.label, this.icon, this.semanticLabel, this.enabled = true})
    : assert(label != null || icon != null, 'IosSegment needs a label, an icon, or both');

  final T value;
  final String? label;
  final IconData? icon;

  /// Accessible name. Required for an icon-only segment.
  final String? semanticLabel;
  final bool enabled;
}

/// An iOS segmented control (kit page "Segmented Controls"): equal segments in a Fills/Tertiary capsule; the selected
/// one sits on a white pill (Semibold), the others are Medium. Use it to switch between 2–5 views of the same content.
///
///     IosSegmentedControl<String>(
///       segments: const [IosSegment(value: 'day', label: 'Day'), IosSegment(value: 'week', label: 'Week')],
///       value: view,
///       onChanged: (v) => setState(() => view = v),
///     )
/// [onChanged] null = disabled (50% opacity). The control fills the width it gets.
class IosSegmentedControl<T> extends StatelessWidget {
  const IosSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.size = IosSegmentedControlSize.small,
    this.semanticLabel,
  });

  final List<IosSegment<T>> segments;

  /// The selected segment's value.
  final T value;

  /// Receives the newly selected value. Null = disabled.
  final ValueChanged<T>? onChanged;
  final IosSegmentedControlSize size;

  /// Accessible name of the whole control, e.g. "View".
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final enabled = onChanged != null;
    final height = size == IosSegmentedControlSize.large ? 50.0 : 32.0;
    final footnote = IosTypography.of(context).footnote;
    // Kit: 13.33 pt (Medium; Semibold selected), 18 line: Footnote × 1.0256 so it follows Dynamic Type.
    final fontSize = footnote.fontSize! * 1.0256;
    final selectedIndex = segments.indexWhere((s) => s.value == value);

    Widget control = LayoutBuilder(
      builder: (context, constraints) {
        final n = segments.length;
        final segW = n == 0 ? 0.0 : (constraints.maxWidth - 4 - (n - 1) * 4) / n;
        final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
        double leftOf(int i) => 2 + (rtl ? n - 1 - i : i) * (segW + 4);
        return Container(
          height: height,
          decoration: BoxDecoration(color: c.fillTertiary, borderRadius: BorderRadius.circular(height / 2)),
          child: Stack(
            children: [
              if (selectedIndex >= 0)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  left: leftOf(selectedIndex),
                  top: 2,
                  width: segW,
                  height: height - 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.segmentedSelectedFill,
                      borderRadius: BorderRadius.circular((height - 4) / 2),
                      boxShadow: const [BoxShadow(color: Color(0x0F000000), offset: Offset(0, 2), blurRadius: 20)],
                    ),
                  ),
                ),
              for (var i = 0; i < n; i++)
                Positioned(
                  left: leftOf(i),
                  top: 2,
                  width: segW,
                  height: height - 4,
                  child: _SegmentButton<T>(
                    segment: segments[i],
                    selected: i == selectedIndex,
                    enabled: enabled && segments[i].enabled,
                    fontSize: fontSize,
                    lineHeight: footnote.fontSize! / 13 * 18,
                    labelColor: enabled && !segments[i].enabled ? c.labelTertiary : c.labelPrimary,
                    onTap: () => onChanged?.call(segments[i].value),
                  ),
                ),
            ],
          ),
        );
      },
    );
    if (!enabled) control = Opacity(opacity: 0.5, child: control);
    return Semantics(container: true, label: semanticLabel, child: control);
  }
}

class _SegmentButton<T> extends StatefulWidget {
  const _SegmentButton({
    required this.segment,
    required this.selected,
    required this.enabled,
    required this.fontSize,
    required this.lineHeight,
    required this.labelColor,
    required this.onTap,
  });

  final IosSegment<T> segment;
  final bool selected;
  final bool enabled;
  final double fontSize;
  final double lineHeight;
  final Color labelColor;
  final VoidCallback onTap;

  @override
  State<_SegmentButton<T>> createState() => _SegmentButtonState<T>();
}

class _SegmentButtonState<T> extends State<_SegmentButton<T>> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.segment;
    final style = appleFont(size: widget.fontSize).copyWith(
      fontSize: widget.fontSize,
      height: widget.lineHeight / widget.fontSize,
      letterSpacing: -0.08,
      fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
      color: widget.labelColor,
      leadingDistribution: TextLeadingDistribution.even,
      decoration: TextDecoration.none,
    );
    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (s.icon != null)
            SizedBox(
              width: 15,
              height: 15,
              child: OverflowBox(maxWidth: 18, maxHeight: 18, child: Icon(s.icon, size: 18, color: widget.labelColor)),
            ),
          if (s.icon != null && s.label != null) const SizedBox(width: 4),
          if (s.label != null)
            Flexible(
              child: Text(s.label!, style: style, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false),
            ),
        ],
      ),
    );
    if (_pressed && !widget.selected) content = Opacity(opacity: 0.55, child: content);
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: widget.selected,
      enabled: widget.enabled,
      label: s.semanticLabel ?? s.label,
      onTap: widget.enabled ? widget.onTap : null,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: widget.enabled ? () => setState(() => _pressed = false) : null,
          onTap: widget.enabled ? widget.onTap : null,
          child: content,
        ),
      ),
    );
  }
}
