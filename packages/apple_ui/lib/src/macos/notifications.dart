import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../core/theme.dart';
import '../core/typography.dart';
import '_panel_support.dart';

final PanelShapeBuilder _bannerShape = roundedPanelShape(20);

/// The banner's classic Ultra Thick blur material: 0.5 px hairline + the kit's drop shadow (0 8 48), no rims.
/// [drop] false = the hairline only (the card peeking out behind a stack).
({Color fill, ui.ImageFilter backdrop, List<PanelShadow> shadows}) _bannerMaterial(bool dark, {bool drop = true}) =>
    panelMaterial(dark, drop: [if (drop) panelDropShadow(dark)]);

/// A notification banner (kit "Notification"): Ultra Thick blur material, 344 px wide, radius 20; the app icon (32 px,
/// centred), a bold title, a body of 1–4 lines, the time at the top right and an optional 32 px thumbnail.
/// Native apps post system notifications instead; use this for in-app banners and mockups (with
/// [showMacNotification] for the top-right placement, timing and slide-in).
///
///     MacNotificationBanner(
///       icon: Image.asset('assets/app_icon.png'),
///       title: 'Export complete',
///       body: '“Report.pdf” was saved to Downloads.',
///       time: 'now',
///       onPressed: openDownloads,
///     )
///     MacNotificationBanner(title: 'Home', body: 'Outdoor Light was turned off', stacked: true)   // a thread
///
/// No hover effects in this version (macOS shows a close button on hover).
class MacNotificationBanner extends StatelessWidget {
  const MacNotificationBanner({
    super.key,
    required this.title,
    this.body,
    this.time,
    this.icon,
    this.image,
    this.stacked = false,
    this.onPressed,
  });

  /// Short and specific ("Dinner in Timber Cove"), not the app name. One line.
  final String title;

  /// The details, 1–4 lines.
  final String? body;

  /// "now", "5m ago" (11 px, top right).
  final String? time;

  /// 32 × 32 app icon (an Image, or any widget such as an `Icon`).
  final Widget? icon;

  /// Optional 32 × 32 thumbnail under the time (radius 6).
  final Widget? image;

  /// More notifications of the same thread are behind it: a second card peeks out 8 px below.
  final bool stacked;

  /// Clicking the banner (open the related content).
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final dark = theme.isDark;
    final c = theme.mac;
    final label = c.labelVibrantPrimary; // #1A1A1A · #F5F5F5
    final timeColor = dark ? const Color(0x47FFFFFF) : const Color(0x4D000000); // white 28 % · black 30 %
    final material = _bannerMaterial(dark);
    final base = appleFont(size: 13);
    final titleStyle = panelText(base, size: 13, lineHeight: 16, weight: FontWeight.w700, color: label);
    final bodyStyle = panelText(base, size: 13, lineHeight: 16, color: label);
    final timeStyle = panelText(appleFont(size: 11), size: 11, lineHeight: 14, color: timeColor);

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 14, 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 40,
                child: Center(child: SizedBox(width: 32, height: 32, child: icon)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.topStart,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: titleStyle,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (body != null)
                        Text(body!, style: bodyStyle, maxLines: 4, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ),
              if (time != null || image != null) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (time != null) Text(time!, style: timeStyle, maxLines: 1, softWrap: false),
                    if (image != null) ...[
                      SizedBox(height: time != null ? 7 : 0),
                      ClipRSuperellipse(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(width: 32, height: 32, child: image),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );

    Widget banner = PanelSurface(
      shape: _bannerShape,
      fill: material.fill,
      backdrop: material.backdrop,
      shadows: material.shadows,
      child: content,
    );
    if (stacked) {
      // A second card 16 px narrower on each side; only the 8 px below the banner show (kit "BG - Banner - Stack").
      banner = Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 16,
              right: 16,
              top: 8,
              bottom: -8,
              child: ClipRect(
                clipper: _BottomStrip(),
                child: PanelSurface(
                  shape: _bannerShape,
                  fill: material.fill,
                  backdrop: material.backdrop,
                  shadows: _bannerMaterial(dark, drop: false).shadows,
                ),
              ),
            ),
            banner,
          ],
        ),
      );
    }
    banner = SizedBox(
      width: 344,
      child: DefaultTextStyle(style: bodyStyle, child: banner),
    );
    return Semantics(
      container: true,
      liveRegion: true,
      button: onPressed != null,
      label: [title, ?body, ?time].join(', '),
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: MouseRegion(cursor: SystemMouseCursors.basic, child: banner),
      ),
    );
  }
}

class _BottomStrip extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) => Rect.fromLTRB(-60, size.height - 8, size.width + 60, size.height + 60);
  @override
  bool shouldReclip(_BottomStrip old) => false;
}

// --- In-app banners: top right, newest on top, 16 px apart, at most 3, gone after a few seconds ---------------

class _Center {
  _Center(this.overlay);
  final OverlayState overlay;
  final List<_Entry> entries = [];
  OverlayEntry? layer;
}

class _Entry {
  _Entry(this.banner, this.onClose);
  final Widget banner;
  final VoidCallback onClose;
  Timer? timer;
}

final Map<OverlayState, _Center> _centers = {};

/// Shows an in-app notification [banner] in the top-right corner of the window: it slides in from the right
/// (0.4 s; none with reduced motion), stays [duration] (default 5 s; at least 5 s so people can read it), and
/// a click closes it (after the banner's own `onPressed`). Newest on top, 16 px apart, at most 3 on screen.
/// [top] = gap from the top of the window (16; below a 52 px toolbar use 68).
///
///     showMacNotification(context, MacNotificationBanner(
///       icon: const Icon(AppleIcons.checkmarkCircleFill, size: 32),
///       title: 'Export complete',
///       body: '“Report.pdf” was saved to Downloads.',
///       time: 'now',
///     ));
///
/// Returns a function that closes the banner early.
VoidCallback showMacNotification(
  BuildContext context,
  MacNotificationBanner banner, {
  Duration duration = const Duration(seconds: 5),
  double top = 16,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final center = _centers.putIfAbsent(overlay, () => _Center(overlay));
  final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  final theme = AppleTheme.of(context);
  late final _Entry entry;
  void close() {
    entry.timer?.cancel();
    if (!center.entries.remove(entry)) return;
    if (center.entries.isEmpty) {
      center.layer?.remove();
      center.layer = null;
      _centers.remove(overlay);
    } else {
      center.layer?.markNeedsBuild();
    }
  }

  entry = _Entry(
    MacNotificationBanner(
      title: banner.title,
      body: banner.body,
      time: banner.time,
      icon: banner.icon,
      image: banner.image,
      stacked: banner.stacked,
      onPressed: () {
        banner.onPressed?.call();
        close();
      },
    ),
    close,
  );
  center.entries.insert(0, entry);
  while (center.entries.length > 3) {
    center.entries.last.onClose();
  }
  entry.timer = Timer(duration, close);
  if (center.layer == null) {
    center.layer = OverlayEntry(
      builder: (context) => AppleTheme(
        data: theme,
        child: Positioned(
          top: top,
          right: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < center.entries.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                _SlideIn(key: ObjectKey(center.entries[i]), animate: !reduceMotion, child: center.entries[i].banner),
              ],
            ],
          ),
        ),
      ),
    );
    overlay.insert(center.layer!);
  } else {
    center.layer!.markNeedsBuild();
  }
  return close;
}

class _SlideIn extends StatefulWidget {
  const _SlideIn({super.key, required this.child, required this.animate});
  final Widget child;
  final bool animate;
  @override
  State<_SlideIn> createState() => _SlideInState();
}

class _SlideInState extends State<_SlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: const Cubic(0.2, 0.8, 0.2, 1));
    return AnimatedBuilder(
      animation: curve,
      // translateX(calc(100% + 16px)) → 0
      builder: (context, child) => Transform.translate(offset: Offset((1 - curve.value) * (344 + 16), 0), child: child),
      child: widget.child,
    );
  }
}
