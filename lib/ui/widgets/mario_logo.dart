/// MarioLogo — the app mark.
///
/// Until now the toolbar and the login screen each drew their own placeholder:
/// a letter "M" in a rounded yellow square, duplicated, and unrelated to
/// `assets/logo/mario_logo_v2.svg`, which was in the repo and used nowhere.
/// This renders the real artwork, in one place, so the two never drift apart
/// again.
///
/// The SVG already carries its own rounded-square background, so the widget
/// adds nothing but an optional shadow — a second background behind it would
/// show as a mismatched halo at the corners.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The logo asset. One constant so a future revision is a one-line change.
const String kMarioLogoAsset = 'assets/logo/mario_logo_v2.svg';

class MarioLogo extends StatelessWidget {
  const MarioLogo({super.key, this.size = 28, this.shadow = false});

  final double size;

  /// A soft drop shadow, for the login screen where the mark stands alone.
  /// Off in the toolbar, where it would muddy a 28px icon.
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    // Corner radius tracks the artwork's own 58/256 ratio, so the shadow and
    // any clip follow the shape rather than squaring it off.
    final radius = size * (58 / 256);

    final art = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SvgPicture.asset(
        kMarioLogoAsset,
        width: size,
        height: size,
        // The asset is a fixed-size square; letting it letterbox would leave
        // transparent edges inside the clip.
        fit: BoxFit.cover,
      ),
    );

    if (!shadow) return art;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: size * 0.25,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: art,
    );
  }
}
