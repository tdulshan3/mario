// The menu-style suggestions list of the combo box (combo-boxes.css `.mac-combobox__list`), on the Ultra Thick blur
// material: 12 px corners, 5 px inner padding, menu-height rows (24 at medium), 8 px highlight corners, accent
// highlight with white text. Private to apple_ui (not exported).
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/mac_support.dart';
import '../core/macos_tokens.dart';
import '../core/theme.dart';
import '_text_input.dart';

/// The highlighted-row colour of menus: the accent a little darker (macos.css `oklch(l × 0.88, c × 1.12)`,
/// #0069F9-ish for the default blue).
Color macMenuHighlight(Color accent) {
  double lin(double c) => c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double gam(double c) => c <= 0.0031308 ? 12.92 * c : 1.055 * math.pow(c, 1 / 2.4) - 0.055;
  final r = lin(accent.r), g = lin(accent.g), b = lin(accent.b);
  final l_ = math.pow(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 1 / 3).toDouble();
  final m_ = math.pow(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 1 / 3).toDouble();
  final s_ = math.pow(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 1 / 3).toDouble();
  var L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_;
  var A = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_;
  var B = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_;
  L *= 0.88;
  A *= 1.12;
  B *= 1.12;
  final l2 = math.pow(L + 0.3963377774 * A + 0.2158037573 * B, 3).toDouble();
  final m2 = math.pow(L - 0.1055613458 * A - 0.0638541728 * B, 3).toDouble();
  final s2 = math.pow(L - 0.0894841775 * A - 1.2914855480 * B, 3).toDouble();
  final r2 = 4.0767416621 * l2 - 3.3077115913 * m2 + 0.2309699292 * s2;
  final g2 = -1.2684380046 * l2 + 2.6097574011 * m2 - 0.3413193965 * s2;
  final b2 = -0.0041960863 * l2 - 0.7034186147 * m2 + 1.7076147010 * s2;
  return Color.from(
    alpha: accent.a,
    red: gam(r2.clamp(0.0, 1.0)).clamp(0.0, 1.0),
    green: gam(g2.clamp(0.0, 1.0)).clamp(0.0, 1.0),
    blue: gam(b2.clamp(0.0, 1.0)).clamp(0.0, 1.0),
  );
}

/// One row of a [MacPopupList].
class MacPopupListEntry {
  const MacPopupListEntry(this.label, {this.enabled = true});
  final String label;
  final bool enabled;
}

/// The material list panel. [highlighted] = the row drawn in the accent colour (keyboard or pointer).
class MacPopupList extends StatefulWidget {
  const MacPopupList({
    super.key,
    required this.entries,
    required this.highlighted,
    required this.onHighlight,
    required this.onSelect,
    this.width,
    this.size = MacControlSize.medium,
    this.maxRows = 8,
  });

  final List<MacPopupListEntry> entries;
  final int? highlighted;
  final ValueChanged<int?> onHighlight;
  final ValueChanged<int> onSelect;
  final double? width;
  final MacControlSize size;
  final int maxRows;

  @override
  State<MacPopupList> createState() => _MacPopupListState();
}

class _MacPopupListState extends State<MacPopupList> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(MacPopupList old) {
    super.didUpdateWidget(old);
    final i = widget.highlighted;
    if (i != null && i != old.highlighted && _scroll.hasClients) {
      // Keep the highlighted row visible (keyboard navigation).
      final rowH = MacSizes.of(widget.size).menuHeight;
      final top = i * rowH;
      final view = _scroll.position.viewportDimension;
      if (top < _scroll.offset) {
        _scroll.jumpTo(top);
      } else if (top + rowH > _scroll.offset + view) {
        _scroll.jumpTo(top + rowH - view);
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.mac;
    final s = MacSizes.of(widget.size);
    final rowH = s.menuHeight;
    final highlight = macMenuHighlight(theme.accentColor);
    final base = macFieldTextStyle(context, fontSize: s.menuFontSize, color: c.labelPrimary);

    Widget row(int i) {
      final e = widget.entries[i];
      final hi = i == widget.highlighted && e.enabled;
      final color = !e.enabled ? c.labelTertiary : (hi ? c.labelWhite : c.labelPrimary);
      return MouseRegion(
        onEnter: (_) {
          if (e.enabled) widget.onHighlight(i);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: e.enabled ? () => widget.onSelect(i) : null,
          child: Container(
            height: rowH,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: hi ? BoxDecoration(color: highlight, borderRadius: BorderRadius.circular(8)) : null,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              e.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: base.copyWith(color: color),
            ),
          ),
        ),
      );
    }

    final count = widget.entries.length;
    final maxH = rowH * widget.maxRows + 10;
    return Semantics(
      container: true,
      child: SizedBox(
        width: widget.width,
        child: MacGlass(
          style: MacGlassStyle.panel,
          radius: 12,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: MouseRegion(
              onExit: (_) => widget.onHighlight(null),
              child: ListView.builder(
                controller: _scroll,
                shrinkWrap: true,
                padding: const EdgeInsets.all(5),
                itemCount: count,
                itemExtent: rowH,
                itemBuilder: (context, i) =>
                    Semantics(selected: i == widget.highlighted, enabled: widget.entries[i].enabled, child: row(i)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
