/// The Simple design system's components, as Flutter widgets.
///
/// The stylesheet this comes from is plain CSS on plain HTML, and the remodel
/// made it plainer still: flat fills, 1px rules, small radii, and one accent
/// spent on two 2px bars. There is no glass left — chrome is separated from
/// the page by a LINE, so [MarioSurface] is an opaque fill and nothing more.
///
/// That is the substantive change from the previous system. `backdrop-filter`
/// is gone, which means no `saveLayer` and no two-pass Gaussian per frame on
/// the sidebar, the top bar, and every surface sitting over the AI panel
/// while it streams.
///
/// Two shapes recur often enough to be worth naming: the selected row, marked
/// by a 2px accent bar *inset* on the leading edge, and the live tab, marked
/// by the same bar along the bottom. Both are inset shadows in the design —
/// they do not displace their content — so both are drawn as an overlay here
/// rather than as a `Border`, which would.
library;

import 'package:flutter/material.dart';

import 'colors.dart';
import 'theme.dart';

/// A flat surface — the design's chrome.
///
/// Was `MarioGlass`. The name changed with the paint: this no longer veils
/// what is behind it, it covers it. Callers name the token they want
/// ([MarioTokens.bg], `.side`, `.paper`, `.fill`) instead of a veil strength.
class MarioSurface extends StatelessWidget {
  const MarioSurface({
    super.key,
    required this.child,
    this.color,
    this.borderRadius,
    this.border,
    this.padding,
    this.shadow,
  });

  final Widget child;

  /// Defaults to the sidebar tone, which is what most chrome in this system
  /// is. Pass [MarioTokens.paper] for a writing surface or a floating panel.
  final Color? color;

  final BorderRadius? borderRadius;
  final BoxBorder? border;
  final EdgeInsetsGeometry? padding;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? t.side,
        borderRadius: borderRadius,
        border: border,
        boxShadow: shadow,
      ),
      child: child,
    );
  }
}

/// Elevation, the way this system does it.
///
/// The design only lifts three things off the page, and states each shadow
/// outright: a segmented chip (`0 1px 2px / 10%`), a slider thumb (`0 1px 3px
/// / 20%`), and the command palette (`0 28px 70px / 24%`). Black gets none at
/// all — a drop shadow against #000 is invisible, so there the alpha step off
/// the ground is the depth. Night keeps a much softer version.
List<BoxShadow> marioShadow(BuildContext context, {int level = 1}) {
  if (marioMode(context) == MarioThemeMode.black) return const [];
  final base = marioMode(context).isDark ? 0.40 : 1.0;
  switch (level) {
    // A chip lifted off a segmented track.
    case 0:
      return [
        BoxShadow(
          color: MarioColors.navy.withValues(alpha: 0.10 * base),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];
    // The command palette, and dialogs.
    case 2:
      return [
        BoxShadow(
          color: MarioColors.navy.withValues(alpha: 0.24 * base),
          blurRadius: 70,
          offset: const Offset(0, 28),
        ),
      ];
    // A slider thumb, a menu.
    default:
      return [
        BoxShadow(
          color: MarioColors.navy.withValues(alpha: 0.20 * base),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
      ];
  }
}

/// The 2px accent bar that marks a selected row or the live tab.
///
/// An inset shadow in the design, so it must not displace the content it
/// marks — which rules out a `Border`. Painted as an overlay on the given
/// edge instead.
class MarioAccentEdge extends StatelessWidget {
  const MarioAccentEdge({
    super.key,
    required this.child,
    this.edge = AxisDirection.left,
    this.active = true,
    this.thickness = 2,
    this.color,
  });

  final Widget child;
  final AxisDirection edge;
  final bool active;
  final double thickness;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    final bar = ColoredBox(color: color ?? marioTokens(context).accentBase);
    return Stack(
      children: [
        child,
        switch (edge) {
          AxisDirection.left => Positioned(
              left: 0, top: 0, bottom: 0, width: thickness, child: bar),
          AxisDirection.right => Positioned(
              right: 0, top: 0, bottom: 0, width: thickness, child: bar),
          AxisDirection.up => Positioned(
              left: 0, right: 0, top: 0, height: thickness, child: bar),
          AxisDirection.down => Positioned(
              left: 0, right: 0, bottom: 0, height: thickness, child: bar),
        },
      ],
    );
  }
}

/// A tab in the notebook bar — 13px, secondary when idle, ink and w600 with a
/// 2px accent underline when live.
class MarioTab extends StatelessWidget {
  const MarioTab({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.onSecondaryTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    return MarioAccentEdge(
      edge: AxisDirection.down,
      active: selected,
      child: InkWell(
        onTap: onTap,
        onSecondaryTap: onSecondaryTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                height: 1.2,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? t.ink : t.sec,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The segmented control — Theme, Page width, and the like.
///
/// A `--fill` track with 2px of padding; the live segment is a [paper] chip
/// with a 1px lift under it.
class MarioSegmented<T> extends StatelessWidget {
  const MarioSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.labelOf,
  });

  final List<T> options;

  /// Nullable, because a segmented control can legitimately have nothing
  /// chosen — the Theme row is in exactly that state while "match the system"
  /// is on, and highlighting a ground there would be a lie.
  final T? value;
  final ValueChanged<T> onChanged;
  final String Function(T) labelOf;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: t.fill,
        borderRadius: BorderRadius.circular(MarioRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: _Segment(
                label: labelOf(o),
                selected: o == value,
                onTap: () => onChanged(o),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? t.paper : Colors.transparent,
          borderRadius: BorderRadius.circular(MarioRadius.xs),
          boxShadow: selected ? marioShadow(context, level: 0) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.2,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? t.ink : t.sec,
          ),
        ),
      ),
    );
  }
}

/// The 38×22 toggle. Material's own `Switch` cannot be squeezed to this size,
/// and the design's is a plain track-and-knob with no ripple.
class MarioToggle extends StatelessWidget {
  const MarioToggle({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    return Semantics(
      toggled: value,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          width: 38,
          height: 22,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: value ? t.accentBase : t.fill,
            borderRadius: BorderRadius.circular(MarioRadius.pill),
            border: Border.all(color: value ? t.accentBase : t.line),
          ),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: t.paper,
              borderRadius: BorderRadius.circular(MarioRadius.pill),
              boxShadow: marioShadow(context, level: 0),
            ),
          ),
        ),
      ),
    );
  }
}

/// A settings row — label, optional description, control on the right, with a
/// rule along the top. The design runs these in a stack where each row draws
/// its own top border and the last one closes the group with a bottom border.
class MarioSettingRow extends StatelessWidget {
  const MarioSettingRow({
    super.key,
    required this.label,
    required this.child,
    this.description,
    this.last = false,
  });

  final String label;
  final String? description;
  final Widget child;

  /// Draws the closing rule under the group.
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: t.line),
          bottom: last ? BorderSide(color: t.line) : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    description!,
                    style: TextStyle(fontSize: 12.5, height: 1.3, color: t.mut),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: MarioSpace.x6),
          child,
        ],
      ),
    );
  }
}

/// The `--fill` search field in the top bar, and its bordered cousin in the
/// sidebar. [hint] is placeholder text, never a value.
class MarioSearchField extends StatelessWidget {
  const MarioSearchField({
    super.key,
    required this.hint,
    this.trailing,
    this.onTap,
    this.height = 28,
    this.bordered = false,
  });

  final String hint;

  /// A keyboard hint, set plain — the design has no key pills.
  final String? trailing;
  final VoidCallback? onTap;
  final double height;

  /// The sidebar variant: [paper] with a 1px rule, rather than `--fill`.
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: bordered ? 9 : 10),
        decoration: BoxDecoration(
          color: bordered ? t.paper : t.fill,
          borderRadius: BorderRadius.circular(MarioRadius.sm),
          border: bordered ? Border.all(color: t.line) : null,
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 16, color: t.mut),
            const SizedBox(width: MarioSpace.x2),
            Expanded(
              child: Text(
                hint,
                style: TextStyle(fontSize: 12.5, height: 1.2, color: t.mut),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: TextStyle(fontSize: 11, height: 1.2, color: t.mut),
              ),
          ],
        ),
      ),
    );
  }
}

/// `.tag` — a small flat label. Four tones, matching the stylesheet.
enum MarioTagTone { accent, accent2, neutral, outline }

class MarioTag extends StatelessWidget {
  const MarioTag(this.label, {super.key, this.tone = MarioTagTone.neutral});

  final String label;
  final MarioTagTone tone;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);

    late final Color bg;
    late final Color fg;
    Border? border;
    switch (tone) {
      case MarioTagTone.accent:
        bg = t.accentBase.withValues(alpha: t.isDark ? 0.20 : 0.16);
        fg = t.accentText;
      case MarioTagTone.accent2:
        bg = t.fill;
        fg = t.sec;
      case MarioTagTone.neutral:
        bg = t.fill;
        fg = t.sec;
      case MarioTagTone.outline:
        bg = Colors.transparent;
        fg = t.accentText;
        border = Border.all(color: t.line);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        border: border,
        borderRadius: BorderRadius.circular(MarioRadius.xs),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

/// The small count that trails a section name.
class MarioCountBadge extends StatelessWidget {
  const MarioCountBadge(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: t.fill,
        borderRadius: BorderRadius.circular(MarioRadius.xs),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: t.mut,
        ),
      ),
    );
  }
}

/// The 4×18 bar that marks a section, tinted by its notebook colour.
class MarioSectionBar extends StatelessWidget {
  const MarioSectionBar({super.key, required this.color, this.height = 18});

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        width: 3,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(MarioRadius.pill),
        ),
      );
}

/// An uppercase, tracked-out section label — 10.5px, w700, muted.
class MarioKicker extends StatelessWidget {
  const MarioKicker(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          height: 1,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1 * 10.5,
          color: color ?? marioTokens(context).mut,
        ),
      );
}

/// The circular identity chip — 24px, `--fill`, initials in secondary.
///
/// It was gold with navy initials in the previous system. The remodel spends
/// the accent on the two 2px bars and nothing else, so the avatar drops to
/// the same neutral fill as the search pill.
class MarioAvatar extends StatelessWidget {
  const MarioAvatar({super.key, required this.initials, this.size = 24});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: t.fill, shape: BoxShape.circle),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.44,
          height: 1,
          fontWeight: FontWeight.w600,
          color: t.sec,
        ),
      ),
    );
  }
}

/// A keyboard hint.
///
/// Plain muted text, not a pill — the design sets `Ctrl ⇧ F`, `esc` and `⏎`
/// at 11px in the muted tone with no box around them.
class MarioKeyHint extends StatelessWidget {
  const MarioKeyHint(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: TextStyle(
          fontSize: 11,
          height: 1.2,
          color: marioTokens(context).mut,
        ),
      );
}

/// A hairline in the theme's rule tone — the ink at 10% on the light grounds,
/// white-alpha on the dark ones.
Color marioDivider(BuildContext context) => marioTokens(context).line;
