/// MarioLoader — the app's waiting indicator.
///
/// Wraps `LoadingAnimationWidget.fourRotatingDots` so the colour and the size
/// choices live in one place rather than being re-picked at every call site.
///
/// The size guidance matters more than it looks: four dots rotating around a
/// circle need room to read as an animation. Below ~16px each dot is barely a
/// pixel or two and the whole thing reads as a smudge, so the small inline
/// cases — a 12px spinner inside a button, say — deliberately keep Material's
/// `CircularProgressIndicator`, which is designed to stay legible that small.
library;

import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

import '../colors.dart';

class MarioLoader extends StatelessWidget {
  const MarioLoader({super.key, this.size = 32, this.color});

  final double size;

  /// Defaults to the brand yellow, which reads on every theme's surface.
  final Color? color;

  /// The smallest size at which four rotating dots still read as four dots.
  static const minLegibleSize = 16.0;

  @override
  Widget build(BuildContext context) {
    return LoadingAnimationWidget.fourRotatingDots(
      color: color ?? MarioColors.primary,
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
