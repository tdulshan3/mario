import 'package:flutter/widgets.dart';

import '../core/adaptive.dart';
import '../core/theme.dart';
import '../core/typography.dart';
import 'button.dart';

/// The symbol above an empty state's text (kit "Empty States").
enum IosEmptyStateSymbolStyle {
  /// Semibold 41 in the accent colour (kit "Large Symbol").
  large,

  /// Semibold 22 in a 50 pt circle filled with the accent at 15% (kit "Symbol in Circle").
  circle,
}

/// An empty state (kit "Empty States"; SwiftUI ContentUnavailableView): a message centred where the content would
/// be, an optional symbol above it and optionally ONE action at the bottom. It fills its parent.
///
///     IosEmptyState(
///       icon: AppleIcons.starFill,
///       title: 'No Favorites',
///       description: 'Tap the star on a recipe to add it here.',
///       actionLabel: 'Browse Recipes',
///       onAction: browse,
///     )
/// [accent] tints the symbol and the button (default: the app accent).
class IosEmptyState extends StatelessWidget {
  const IosEmptyState({
    super.key,
    required this.title,
    this.description,
    this.icon,
    this.symbolStyle = IosEmptyStateSymbolStyle.large,
    this.secondaryTitle = false,
    this.accent,
    this.actionLabel,
    this.onAction,
    this.action,
  });

  /// What is missing, in a few words: "No Favorites", "No Results" (Semibold 22).
  final String title;

  /// One sentence: why it is empty or what to do (Medium 22, secondary).
  final String? description;
  final IconData? icon;
  final IosEmptyStateSymbolStyle symbolStyle;

  /// The title in secondary colour too (kit Examples "No Notes").
  final bool secondaryTitle;
  final Color? accent;

  /// The one action: a large prominent button (solid accent fill) at the bottom.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Your own action widget instead of [actionLabel].
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final t = IosTypography.of(context);
    final tint = accent ?? theme.accentColor;
    // Kit: Semibold 22 / Medium 22, line height 26 (title2 size, Dynamic Type).
    final base = t.title2;
    final lineHeight = (base.fontSize! * base.height! - 2) / base.fontSize!;
    final titleStyle = base.copyWith(
      height: lineHeight,
      fontWeight: FontWeight.w600,
      color: secondaryTitle ? c.labelSecondary : c.labelPrimary,
    );
    final descriptionStyle = base.copyWith(height: lineHeight, fontWeight: FontWeight.w500, color: c.labelSecondary);
    final regular = IosLayout.isRegular(context);

    Widget? symbol;
    if (icon != null) {
      symbol = symbolStyle == IosEmptyStateSymbolStyle.circle
          ? Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(shape: BoxShape.circle, color: tint.withValues(alpha: 0.15)),
              child: Center(
                child: Icon(icon, size: 22 * 1.2, color: tint),
              ),
            )
          : SizedBox(
              height: 49,
              child: Center(
                child: Icon(icon, size: 41 * 1.2, color: tint),
              ),
            );
    }

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (symbol != null) ...[ExcludeSemantics(child: symbol), const SizedBox(height: 16)],
          Semantics(
            header: true,
            child: Text(title, style: titleStyle, textAlign: TextAlign.center),
          ),
          if (description != null) Text(description!, style: descriptionStyle, textAlign: TextAlign.center),
        ],
      ),
    );

    Widget? bottom = action;
    if (bottom == null && actionLabel != null) {
      bottom = SizedBox(
        width: double.infinity,
        child: AppleTheme(
          data: theme.copyWith(accent: tint),
          child: IosButton(
            label: actionLabel,
            style: IosButtonStyle.glassProminent,
            size: IosButtonSize.large,
            onPressed: onAction,
          ),
        ),
      );
    }
    final maxWidth = regular ? 330.0 : double.infinity; // iPad: keep the iPhone measure
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 0, 36, 36),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: content,
              ),
            ),
          ),
          if (bottom != null)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: bottom,
            ),
        ],
      ),
    );
  }
}
