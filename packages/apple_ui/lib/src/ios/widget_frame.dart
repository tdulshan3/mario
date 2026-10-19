import 'package:flutter/widgets.dart';

import '../core/adaptive.dart';
import '../core/glass.dart';
import '../core/theme.dart';
import '../core/typography.dart';

/// Home Screen widget sizes (kit page "Widgets").
enum IosWidgetSize {
  /// iPhone 164.67 × 164.67 · iPad 136 × 136.
  small,

  /// iPhone 349.67 × 164.33 · iPad 300 × 136.
  medium,

  /// iPhone 349.67 × 365 · iPad 300 × 300.
  large,

  /// iPhone 349.67 × 565.67 · iPad 628 × 300.
  extraLarge,
}

/// A Home Screen widget FRAME (kit page "Widgets") for mockups, onboarding and previews of your widget inside the app.
/// Real widgets are SwiftUI (WidgetKit). Radius 28 (continuous), content margin 18, inner radius 11. A plain
/// background (no sheen, no edge highlights: those were Liquid Glass).
///
///     IosWidgetFrame(
///       size: IosWidgetSize.small,
///       name: 'Weather',
///       background: IosColors.light.blue,
///       child: Text('21°', style: TextStyle(fontSize: 42, color: Color(0xFFFFFFFF))),
///     )
///     IosWidgetFrame(size: IosWidgetSize.large, fullBleed: true, child: Image.asset('photo.jpg', fit: BoxFit.cover))
class IosWidgetFrame extends StatelessWidget {
  const IosWidgetFrame({
    super.key,
    this.size = IosWidgetSize.small,
    this.name,
    this.background,
    this.fullBleed = false,
    this.clear = false,
    this.ipad,
    this.onTap,
    this.child,
  });

  final IosWidgetSize size;

  /// The label under the widget on the Home Screen (usually the app name).
  final String? name;

  /// Background colour. Null = Backgrounds/Primary - Elevated (white / #1C1C1E).
  final Color? background;

  /// No 18 pt content margin: photos and maps that fill the widget.
  final bool fullBleed;

  /// See-through Home Screen appearance: the Thin blur material ([AppleGlassStyle.clear]), content in the label
  /// colours (dark in Light, white in Dark).
  final bool clear;

  /// iPad sizes (true) or iPhone sizes (false). Null = from the screen size ([IosLayout.isRegular]).
  final bool? ipad;
  final VoidCallback? onTap;
  final Widget? child;

  /// The kit size of a widget in points.
  static Size sizeOf(IosWidgetSize size, {required bool ipad}) => ipad
      ? switch (size) {
          IosWidgetSize.small => const Size(136, 136),
          IosWidgetSize.medium => const Size(300, 136),
          IosWidgetSize.large => const Size(300, 300),
          IosWidgetSize.extraLarge => const Size(628, 300),
        }
      : switch (size) {
          IosWidgetSize.small => const Size(164.67, 164.67),
          IosWidgetSize.medium => const Size(349.67, 164.33),
          IosWidgetSize.large => const Size(349.67, 365),
          IosWidgetSize.extraLarge => const Size(349.67, 565.67),
        };

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final s = sizeOf(size, ipad: ipad ?? IosLayout.isRegular(context));
    final content = Padding(padding: EdgeInsets.all(fullBleed ? 0 : 18), child: child);

    Widget tile;
    if (clear) {
      tile = AppleGlass(
        style: AppleGlassStyle.clear,
        radius: 28,
        child: DefaultTextStyle.merge(
          style: TextStyle(color: theme.ios.labelPrimary),
          child: IconTheme.merge(data: IconThemeData(color: theme.ios.labelPrimary), child: content),
        ),
      );
    } else {
      tile = ClipRSuperellipse(
        borderRadius: BorderRadius.circular(28),
        child: ColoredBox(color: background ?? theme.ios.bgPrimaryElevated, child: content),
      );
    }
    tile = SizedBox(width: s.width, height: s.height, child: tile);

    if (name != null) {
      tile = Stack(
        clipBehavior: Clip.none,
        children: [
          tile,
          Positioned(
            left: -20,
            right: -20,
            top: s.height + 5.67,
            child: Text(
              name!,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: IosTypography.of(context).caption1.copyWith(
                fontWeight: FontWeight.w500,
                height: 14 / 12,
                letterSpacing: 0,
                color: const Color(0xFFFFFFFF),
                shadows: const [Shadow(color: Color(0x59000000), offset: Offset(0, 1), blurRadius: 6)],
              ),
            ),
          ),
        ],
      );
    }
    if (onTap != null) {
      tile = GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: tile);
    }
    return Semantics(container: true, button: onTap != null, label: name, child: tile);
  }
}
