/// MarioLoader — the app's one waiting indicator.
///
/// Wraps `LoadingAnimationWidget.fourRotatingDots` so the colour and the size
/// choices live in one place rather than being re-picked at every call site.
/// Every indeterminate wait in the app goes through here; the only indicators
/// left outside it are the two *determinate* `LinearProgressIndicator`s (audio
/// playback position, quiz score), which show real values rather than waiting.
///
/// The size guidance matters more than it looks: four dots rotating around a
/// circle need room to read as an animation. Below ~16px each dot is barely a
/// pixel or two and the whole thing reads as a smudge, so [size] is clamped up
/// to [minLegibleSize]. A caller that wants a loader in a smaller slot should
/// widen the slot rather than shrink the loader — a MarioLoader inside a box
/// under 16x16 overflows.
///
/// [minLegibleSize] is the floor, not the target. The tight in-line slots use
/// 18 so they sit clear of that floor rather than exactly on it, and a loader
/// that swaps places with an icon takes that icon's size — otherwise the
/// button visibly resizes the moment it starts loading.
///
/// The colour defaults to the *active theme's* `colorScheme.primary`, not a
/// hardcoded constant. That matters for the Book theme, whose primary is a warm
/// brown (`primaryBook`); the brand amber it replaces is nearly invisible on
/// Book's cream paper. Passing an explicit [color] overrides this — but think
/// twice before doing so on a button that is *disabled* while it loads, which
/// is the common case: a disabled Material button paints
/// `onSurface.withOpacity(0.12)`, not `primary`, so `onPrimary` is the wrong
/// on-colour there and the theme default is what actually reads.
library;

import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

class MarioLoader extends StatelessWidget {
  const MarioLoader({super.key, this.size = 32, this.color});

  final double size;

  /// Defaults to the active theme's `colorScheme.primary`, so the loader stays
  /// legible on Light, Dark and Book surfaces alike.
  final Color? color;

  /// The smallest size at which four rotating dots still read as four dots.
  static const minLegibleSize = 16.0;

  @override
  Widget build(BuildContext context) {
    return LoadingAnimationWidget.fourRotatingDots(
      color: color ?? Theme.of(context).colorScheme.primary,
      size: size < minLegibleSize ? minLegibleSize : size,
    );
  }
}

/// A loader with a line of text under it, for a wait long enough to need
/// explaining — reading a section, marking a paper.
class MarioLoaderWithLabel extends StatelessWidget {
  const MarioLoaderWithLabel({
    super.key,
    required this.label,
    this.size = 36,
    this.trailing,
  });

  final String label;
  final double size;

  /// Anything below the label — a Stop button, usually.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MarioLoader(size: size),
          const SizedBox(height: 14),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(height: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}
