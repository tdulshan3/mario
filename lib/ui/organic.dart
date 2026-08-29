/// Organic — the design system's own components, as Flutter widgets.
///
/// The stylesheet this comes from is plain CSS on plain HTML: a handful of
/// classes (`.btn`, `.tag`, `.card`, `.seg`) composed from the tokens in
/// [MarioColors]. These are those classes, one widget each, so a screen reads
/// like the design does instead of re-deriving padding and radii at every site.
///
/// The one piece that needs real work in Flutter is the glass. The design puts
/// `backdrop-filter: blur(26px) saturate(1.7)` on the top bar, the sidebar, the
/// search pill and the composer — chrome is a translucent veil over the ground,
/// not an opaque panel. That is what makes one layout work across four very
/// different grounds, so [MarioGlass] implements it properly rather than
/// faking it with a flat colour.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'colors.dart';
import 'theme.dart';

/// A translucent, blurred surface — the design's chrome.
///
/// [opacity] is the veil strength the design gives each surface (0.62 for the
/// sidebar, 0.72 for the top bar, 0.66 for the composer). On the dark grounds
/// the veil is white-alpha instead of a tint of the surface colour, because a
/// darker veil over navy or black reads as a hole rather than as glass.
class MarioGlass extends StatelessWidget {
  const MarioGlass({
    super.key,
    required this.child,
    this.opacity = 0.66,
    this.blur = 26,
    this.borderRadius,
    this.border,
    this.tint,
    this.padding,
    this.strength,
  });

  final Widget child;
  final double opacity;
  final double blur;
  final BorderRadius? borderRadius;
  final BoxBorder? border;

  /// Overrides the veil colour. Defaults to the theme's chrome.
  final Color? tint;
  final EdgeInsetsGeometry? padding;

  /// Overrides the computed veil opacity outright.
  ///
  /// [opacity] is tuned for chrome, and on the dark grounds it is scaled right
  /// down — a heavy veil over navy or black reads as a hole rather than as
  /// glass. That is wrong for a surface you have to READ through, like a
  /// dialog floating over a page: there the veil has to carry the text, so the
  /// caller states the strength it needs and the ground-dependent scaling is
  /// skipped.
  final double? strength;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = marioMode(context).isDark;

    // Dark grounds veil with white; light grounds veil with their own chrome.
    final veil = tint ?? (dark ? Colors.white : scheme.surfaceContainerHighest);
    final veilStrength = strength ?? (dark ? opacity * 0.09 : opacity);

    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: veil.withValues(alpha: veilStrength),
        borderRadius: borderRadius,
        border: border,
      ),
      child: child,
    );

    // `blur: 0` keeps the veil and drops the filter. Not a style choice — a
    // BackdropFilter over a flat opaque fill produces byte-identical output,
    // and one nested inside another blurs already-blurred pixels. Both are a
    // saveLayer and a two-pass Gaussian per frame for a result indistinguishable
    // from doing nothing, and they re-run whenever they fall inside the damage
    // rect: a panel resize, a sidebar hover, and — for anything over the AI
    // panel — every streamed token.
    //
    // The clip stays either way. Callers with no borderRadius rely on the
    // ClipRect to bound their content.
    final surface = blur > 0
        ? BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: blur / 3, sigmaY: blur / 3),
            child: content,
          )
        : content;

    if (borderRadius == null) {
      return ClipRect(child: surface);
    }
    return ClipRRect(borderRadius: borderRadius!, child: surface);
  }
}

/// Elevation, the way this system does it.
///
/// Light and White get soft navy-tinted shadows. Black gets none at all — a
/// drop shadow against #000 is invisible, so there the alpha step off the
/// ground is the depth. Night sits in between with a much softer shadow.
List<BoxShadow> marioShadow(BuildContext context, {int level = 1}) {
  if (marioMode(context) == MarioThemeMode.black) return const [];
  final dark = marioMode(context).isDark;
  final base = dark ? 0.40 : 1.0;
  switch (level) {
    case 0:
      return [
        BoxShadow(
          color: MarioColors.navy.withValues(alpha: 0.16 * base),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];
    case 2:
      return [
        BoxShadow(
          color: MarioColors.navy.withValues(alpha: 0.24 * base),
          blurRadius: 32,
          offset: const Offset(0, 12),
        ),
      ];
    default:
      return [
        BoxShadow(
          color: MarioColors.navy.withValues(alpha: 0.18 * base),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ];
  }
}

/// `.tag` — a small pill label. Four tones, matching the stylesheet.
enum MarioTagTone { accent, accent2, neutral, outline }

class MarioTag extends StatelessWidget {
  const MarioTag(this.label, {super.key, this.tone = MarioTagTone.neutral});

  final String label;
  final MarioTagTone tone;

  @override
  Widget build(BuildContext context) {
    final dark = marioMode(context).isDark;
    final scheme = Theme.of(context).colorScheme;

    late final Color bg;
    late final Color fg;
    Border? border;
    switch (tone) {
      case MarioTagTone.accent:
        bg = dark
            ? MarioColors.accent400.withValues(alpha: 0.20)
            : MarioColors.accent100;
        fg = dark ? MarioColors.accent200 : MarioColors.accent800;
      case MarioTagTone.accent2:
        bg = dark
            ? MarioColors.accent2400.withValues(alpha: 0.20)
            : MarioColors.accent2100;
        fg = dark ? MarioColors.accent2200 : MarioColors.accent2800;
      case MarioTagTone.neutral:
        bg = dark
            ? Colors.white.withValues(alpha: 0.08)
            : MarioColors.neutral200;
        fg = dark ? MarioColors.neutral200 : MarioColors.neutral800;
      case MarioTagTone.outline:
        bg = Colors.transparent;
        fg = scheme.primary;
        border = Border.all(color: scheme.primary);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        border: border,
        borderRadius: BorderRadius.circular(MarioRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          height: 1.4,
          letterSpacing: 0.02 * 11,
          color: fg,
        ),
      ),
    );
  }
}

/// The small count pill that trails a section name.
class MarioCountBadge extends StatelessWidget {
  const MarioCountBadge(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final dark = marioMode(context).isDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.08)
            : MarioColors.neutral200,
        borderRadius: BorderRadius.circular(MarioRadius.pill),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w600,
          color: dark ? MarioColors.neutral300 : MarioColors.neutral700,
        ),
      ),
    );
  }
}

/// The 4×18 rounded bar that marks a section, tinted by its notebook colour.
class MarioSectionBar extends StatelessWidget {
  const MarioSectionBar({super.key, required this.color, this.height = 18});

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        width: 4,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(MarioRadius.pill),
        ),
      );
}

/// An uppercase, tracked-out section label — `h6` in the stylesheet.
class MarioKicker extends StatelessWidget {
  const MarioKicker(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.12 * 11,
          color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
}

/// The circular identity chip — gold, with initials in the display face.
class MarioAvatar extends StatelessWidget {
  const MarioAvatar({super.key, required this.initials, this.size = 38});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: MarioColors.accent2400,
          shape: BoxShape.circle,
        ),
        child: Text(
          initials,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: size * 0.39,
                color: MarioColors.navy,
              ),
        ),
      );
}

/// A keyboard hint pill, as on the search field's ⌘K.
class MarioKeyHint extends StatelessWidget {
  const MarioKeyHint(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = marioMode(context).isDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.08)
            : MarioColors.neutral200,
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.12)
              : MarioColors.neutral300,
        ),
        borderRadius: BorderRadius.circular(MarioRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w600,
          color: dark ? MarioColors.neutral300 : MarioColors.neutral700,
        ),
      ),
    );
  }
}

/// A hairline in the theme's divider tone, matching `--color-divider`
/// (the ink at 16%) rather than a flat grey.
Color marioDivider(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return marioMode(context).isDark
      ? Colors.white.withValues(alpha: 0.10)
      : scheme.onSurface.withValues(alpha: 0.16);
}
