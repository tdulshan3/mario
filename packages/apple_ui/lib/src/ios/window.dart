import 'package:flutter/widgets.dart';

import '../core/glass.dart';
import '../core/theme.dart';
import 'app_shell.dart';

/// Tells an [IosSidebar] inside an [IosWindow] to show the window controls in its toolbar row.
class IosWindowScope extends InheritedWidget {
  const IosWindowScope({super.key, required this.active, required this.showControls, required super.child});
  final bool active;
  final bool showControls;

  static IosWindowScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<IosWindowScope>();

  @override
  bool updateShouldNotify(IosWindowScope old) => old.active != active || old.showControls != showControls;
}

/// An iPadOS 27 window (kit "Window" / "Window with Sidebar"): radius 34 (continuous corners), Backgrounds/Primary,
/// drop shadow 0 30 140 black 30%, window controls at the top-left, resize grabber at the bottom-right.
/// A MOCKUP for previews, onboarding and screenshots: a real iPad app gets its window from the system.
///
///     IosWindow(
///       width: 720, height: 400,
///       sidebar: IosSidebar(sections: …),
///       child: NotesList(),
///     )
class IosWindow extends StatelessWidget {
  const IosWindow({
    super.key,
    required this.child,
    this.sidebar,
    this.active = true,
    this.showControls = true,
    this.resizable = true,
    this.width,
    this.height,
  });

  final Widget child;

  /// An [IosSidebar]: the window gets a sidebar column; the window controls go into its toolbar row.
  final Widget? sidebar;

  /// The focused window. False = grey window controls, lighter sidebar (kit Mode = Inactive).
  final bool active;
  final bool showControls;

  /// Show the resize grabber.
  final bool resizable;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    const shape = RoundedSuperellipseBorder(borderRadius: BorderRadius.all(Radius.circular(34)));
    Widget content = sidebar != null ? IosSplitView(sidebar: sidebar!, detail: child) : child;
    content = Stack(children: [
      Positioned.fill(child: MediaQuery.removePadding(context: context, removeTop: true, removeBottom: true, removeLeft: true, removeRight: true, child: content)),
      if (showControls && sidebar == null) Positioned(left: 21, top: 21, child: IosWindowControls(active: active)),
      if (resizable) const Positioned(right: 0, bottom: 0, child: IosWindowResizeGrabber()),
    ]);
    return IosWindowScope(
      active: active,
      showControls: showControls && sidebar != null,
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: shape,
            color: theme.ios.bgPrimary,
            shadows: const [BoxShadow(offset: Offset(0, 30), blurRadius: 140, color: Color(0x4D000000))],
          ),
          child: ClipRSuperellipse(borderRadius: const BorderRadius.all(Radius.circular(34)), child: content),
        ),
      ),
    );
  }
}

/// Window controls (kit "_Window Controls"): close, minimize, full screen — three 6 pt dots, 4.5 apart, in a 41 × 22
/// capsule of Regular blur material. Inactive: flat quaternary fill, grey dots. Decorative (excluded from semantics).
class IosWindowControls extends StatelessWidget {
  const IosWindowControls({super.key, this.active = true});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = AppleTheme.of(context).ios;
    Widget dot(Color color) => Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
    final dots = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: SizedBox(
        height: 22,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          dot(active ? const Color(0xFFFF5F57) : c.labelSecondary),
          const SizedBox(width: 4.5),
          dot(active ? const Color(0xFFFEBC2F) : c.labelSecondary),
          const SizedBox(width: 4.5),
          dot(active ? const Color(0xFF27C840) : c.labelSecondary),
        ]),
      ),
    );
    return ExcludeSemantics(
      child: AppleGlass(style: active ? AppleGlassStyle.regular : AppleGlassStyle.inactive, child: dots),
    );
  }
}

/// The window's resize grabber (kit "_Window Resize"): a 3.5 pt round-capped arc following the corner, Labels/Primary.
/// [fullScreen] = the smaller grabber of a full-screen app.
class IosWindowResizeGrabber extends StatelessWidget {
  const IosWindowResizeGrabber({super.key, this.fullScreen = false});
  final bool fullScreen;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(size: const Size(32, 32), painter: _GrabberPainter(AppleTheme.of(context).ios.labelPrimary, fullScreen)),
    );
  }
}

class _GrabberPainter extends CustomPainter {
  _GrabberPainter(this.color, this.fullScreen);
  final Color color;
  final bool fullScreen;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    // Floating: a 19.93 arc centred on (5.4, 5.4); full screen: a 12 arc centred on (14, 14).
    final path = fullScreen
        ? (Path()
          ..moveTo(26, 14)
          ..arcToPoint(const Offset(14, 26), radius: const Radius.circular(12)))
        : (Path()
          ..moveTo(25.33, 5.4)
          ..arcToPoint(const Offset(5.4, 25.33), radius: const Radius.circular(19.93)));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_GrabberPainter old) => old.color != color || old.fullScreen != fullScreen;
}
