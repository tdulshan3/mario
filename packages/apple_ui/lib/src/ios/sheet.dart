import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/adaptive.dart';
import '../core/glass.dart';
import '../core/ios_tokens.dart';
import '../core/theme.dart';
import '../core/typography.dart';
import '_presentation_support.dart';

/// Sheet heights on iPhone (kit "Sheet - iPhone" Detent). iPad ignores detents (a centred card).
enum IosSheetDetent {
  /// A floating card of Thick blur material, 6 from the screen edges, about half the screen (kit: 459 of 874).
  medium,

  /// From the status bar down, opaque, top corners 38.
  large,
}

/// A 44 pt button on the Regular blur material for a sheet's own toolbar (kit "_Buttons - 44pt"): a text label
/// (Medium 17, 14 side padding) or a symbol in a 44 circle. [prominent] = a solid accent fill (Done / Add).
///
///     IosSheetButton(icon: AppleIcons.xmark, semanticLabel: 'Cancel', onPressed: () => Navigator.pop(context))
///     IosSheetButton(icon: AppleIcons.checkmark, semanticLabel: 'Done', prominent: true, onPressed: save)
///     IosSheetButton(label: 'Cancel', onPressed: () => Navigator.pop(context))
class IosSheetButton extends StatefulWidget {
  const IosSheetButton({
    super.key,
    this.label,
    this.icon,
    required this.onPressed,
    this.prominent = false,
    this.semanticLabel,
  }) : assert(label != null || icon != null, 'IosSheetButton needs a label or an icon');

  final String? label;
  final IconData? icon;

  /// null = disabled.
  final VoidCallback? onPressed;
  final bool prominent;

  /// Accessible name. Required for an icon-only button.
  final String? semanticLabel;

  @override
  State<IosSheetButton> createState() => _IosSheetButtonState();
}

class _IosSheetButtonState extends State<IosSheetButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final enabled = widget.onPressed != null;
    final prominent = widget.prominent && enabled;
    final color = !enabled ? c.labelControlTertiary : (prominent ? const Color(0xFFFFFFFF) : c.labelControlPrimary);
    final iconOnly = widget.label == null;
    Widget content = iconOnly
        ? SizedBox(
            width: 17,
            height: 17,
            child: OverflowBox(maxWidth: 20.4, maxHeight: 20.4, child: Icon(widget.icon, size: 20.4, color: color)),
          )
        : Text(
            widget.label!,
            maxLines: 1,
            softWrap: false,
            style: appleFont(size: 17).copyWith(
              fontSize: 17,
              height: 22 / 17,
              letterSpacing: -0.43,
              fontWeight: FontWeight.w500,
              color: color,
              leadingDistribution: TextLeadingDistribution.even,
              decoration: TextDecoration.none,
            ),
          );
    content = SizedBox(
      height: 44,
      width: iconOnly ? 44 : null,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : 14),
        child: Center(widthFactor: 1, child: content),
      ),
    );
    // Pressed: darker (lighter in Dark Mode), drawn inside the material so the backdrop blur stays.
    final tint = _pressed && enabled
        ? (AppleTheme.of(context).isDark ? const Color(0x33FFFFFF) : const Color(0x1F000000))
        : const Color(0x00000000);
    final Widget button = AppleGlass(
      style: prominent ? AppleGlassStyle.prominent : AppleGlassStyle.regular,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(color: tint),
        child: content,
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTap: widget.onPressed,
          child: button,
        ),
      ),
    );
  }
}

bool _isRegular(BuildContext context, IosSizeClass? sizeClass) =>
    sizeClass != null ? sizeClass == IosSizeClass.regular : IosLayout.isRegular(context);

/// The sheet itself (kit "Sheet - iPhone" / "Sheet - iPad"): the surface, the grabber, the sheet's own toolbar
/// (leading button, title, trailing button) and the content. It fills the space it is given: [showIosSheet] places
/// it for you; for a static mockup put it in an [IosSheetLayout].
///
///     IosSheet(
///       title: 'New Event',
///       leading: IosSheetButton(icon: AppleIcons.xmark, semanticLabel: 'Cancel', onPressed: cancel),
///       trailing: IosSheetButton(icon: AppleIcons.checkmark, semanticLabel: 'Add', prominent: true, onPressed: add),
///       child: const Text('…'),
///     )
class IosSheet extends StatelessWidget {
  const IosSheet({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.detent = IosSheetDetent.large,
    this.fullScreen = false,
    this.showGrabber = true,
    this.scrollable = true,
    this.sizeClass,
    this.onGrabberTap,
  });

  /// The content under the toolbar.
  final Widget child;

  /// Toolbar title: Semibold 17 (iPhone) / 15 (iPad).
  final String? title;

  /// iPad two-line toolbar: a subtitle under the title (Medium 12, secondary).
  final String? subtitle;

  /// Toolbar left, usually an [IosSheetButton] (Cancel / xmark).
  final Widget? leading;

  /// Toolbar right, usually a prominent [IosSheetButton] (Done / checkmark).
  final Widget? trailing;

  /// medium = a floating material card (iPhone), large = opaque from the status bar down.
  final IosSheetDetent detent;

  /// Full-screen cover: opaque, no grabber, no corners.
  final bool fullScreen;
  final bool showGrabber;

  /// Wrap [child] in a scroll view with the side margins (16 iPhone / 20 iPad). Set false when [child] is a
  /// ListView or another scroll view: it then gets the whole area under the toolbar (add your own padding).
  final bool scrollable;

  /// Force iPhone (compact) or iPad (regular) looks. Null = from the screen size.
  final IosSizeClass? sizeClass;

  /// Grabber pressed (VoiceOver / keyboard): [showIosSheet] switches detents.
  final VoidCallback? onGrabberTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final regular = _isRegular(context, sizeClass);
    final dims = regular ? IosDimensions.ipad : IosDimensions.iphone;
    final floating = !regular && !fullScreen && detent == IosSheetDetent.medium;
    final hasToolbar = title != null || leading != null || trailing != null;
    final margin = dims.margin;

    // Toolbar: iPhone 16 below the top edge, 16 side padding; iPad 10 / 10. Buttons 44, 10 below.
    final toolbarTop = fullScreen
        ? (MediaQuery.paddingOf(context).top > 0 ? MediaQuery.paddingOf(context).top : dims.statusBarHeight)
        : (regular ? 10.0 : 16.0);
    final pad = regular ? 10.0 : 16.0;
    final titleStyle = (regular ? IosTypography.of(context).subheadlineEmphasized : IosTypography.of(context).headline)
        .copyWith(color: c.labelVibrantPrimary);
    Widget? toolbar;
    if (hasToolbar) {
      toolbar = Padding(
        padding: EdgeInsets.fromLTRB(pad, toolbarTop, pad, 10),
        child: SizedBox(
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 92),
                  child: Semantics(
                    header: true,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title!,
                          style: titleStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              subtitle!,
                              style: IosTypography.of(
                                context,
                              ).caption1.copyWith(color: c.labelVibrantSecondary, fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              Row(children: [?leading, const Spacer(), ?trailing]),
            ],
          ),
        ),
      );
    }

    Widget content = scrollable
        ? SingleChildScrollView(padding: EdgeInsets.fromLTRB(margin, 0, margin, margin), child: child)
        : child;
    Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?toolbar,
        if (!hasToolbar && showGrabber && !fullScreen && scrollable) const SizedBox(height: 24),
        Expanded(child: content),
      ],
    );
    if (showGrabber && !fullScreen) {
      body = Stack(
        children: [
          Positioned.fill(child: body),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: _Grabber(onTap: onGrabberTap, width: dims.grabberWidth, height: dims.grabberHeight),
            ),
          ),
        ],
      );
    }

    // The surface.
    if (fullScreen) return ColoredBox(color: c.bgPrimary, child: body);
    // Content of a (non full-screen) sheet uses the "Elevated" background colours, like iOS (they differ in Dark).
    body = AppleTheme(data: AppleTheme.of(context).copyWith(elevated: true), child: body);
    if (floating) {
      return PresentationGlass(
        radius: BorderRadius.vertical(top: const Radius.circular(34), bottom: Radius.circular(dims.sheetBottomRadius)),
        child: body,
      );
    }
    return PresentationSurface(
      color: c.bgPrimaryElevated,
      radius: regular
          ? BorderRadius.vertical(
              top: Radius.circular(dims.sheetTopRadius),
              bottom: Radius.circular(dims.sheetBottomRadius),
            )
          : BorderRadius.vertical(top: Radius.circular(dims.sheetTopRadius)),
      shadows: const [GlassShadow(0, 15, 75, 0, Color(0x2E000000))],
      child: body,
    );
  }
}

/// Kit "Grabber": 60 × 4 capsule, 6 below the sheet's top edge; a 84 × 44 tap area. The tertiary label colour
/// reproduces the kit's "plus darker" vibrant fill on white, on the material and in Dark Mode.
class _Grabber extends StatelessWidget {
  const _Grabber({required this.onTap, required this.width, required this.height});
  final VoidCallback? onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Sheet Grabber',
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: width + 24,
          height: 44,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: width,
                height: height,
                decoration: ShapeDecoration(
                  color: AppleTheme.of(context).ios.labelTertiary,
                  shape: const StadiumBorder(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where a sheet sits on the screen for [detent] (kit numbers): iPhone medium = 6 from the edges, 52.5% of the
/// screen tall; large = from the status bar down; iPad = a centred card min(936, width − 40) × min(852, height − 64).
Rect iosSheetRect({
  required Size screen,
  required IosSheetDetent detent,
  required bool regular,
  bool fullScreen = false,
  bool stacked = false,
  double topInset = 62,
}) {
  if (fullScreen) return Offset.zero & screen;
  if (regular) {
    final w = math.min(936.0, screen.width - 40);
    final h = math.min(852.0, screen.height - 64);
    return Rect.fromLTWH((screen.width - w) / 2, (screen.height - h) / 2 + (stacked ? 10 : 0), w, h);
  }
  if (detent == IosSheetDetent.medium) {
    final h = screen.height * 0.525;
    return Rect.fromLTWH(6, screen.height - 6 - h, screen.width - 12, h);
  }
  final top = topInset + (stacked ? 10 : 0);
  return Rect.fromLTWH(0, top, screen.width, screen.height - top);
}

/// Places a sheet on the screen like iOS does for [detent] (see [iosSheetRect]). [showIosSheet] uses it; use it
/// directly only for static mockups (a screenshot of an open sheet), with the dimming layer under it yourself.
///
///     Stack(children: [
///       Positioned.fill(child: ColoredBox(color: context.iosColors.overlay)),
///       IosSheetLayout(detent: IosSheetDetent.medium, child: IosSheet(detent: IosSheetDetent.medium, title: 'Title', child: …)),
///     ])
class IosSheetLayout extends StatelessWidget {
  const IosSheetLayout({
    super.key,
    required this.child,
    this.detent = IosSheetDetent.large,
    this.fullScreen = false,
    this.stacked = false,
    this.sizeClass,
    this.topInset,
  });

  final Widget child;
  final IosSheetDetent detent;
  final bool fullScreen;

  /// Opened over another large sheet: 10 lower (kit "Large (Stacked)").
  final bool stacked;
  final IosSizeClass? sizeClass;

  /// Top of a large sheet. Null = the status bar (safe area top, or the kit's 62 when there is none).
  final double? topInset;

  @override
  Widget build(BuildContext context) {
    final regular = _isRegular(context, sizeClass);
    final padTop = MediaQuery.paddingOf(context).top;
    final top =
        topInset ?? (padTop > 0 ? padTop : (regular ? IosDimensions.ipad : IosDimensions.iphone).statusBarHeight);
    return LayoutBuilder(
      builder: (context, box) {
        final rect = iosSheetRect(
          screen: box.biggest,
          detent: detent,
          regular: regular,
          fullScreen: fullScreen,
          stacked: stacked,
          topInset: top,
        );
        return Stack(
          children: [Positioned.fromRect(rect: rect, child: child)],
        );
      },
    );
  }
}

/// Presents a sheet (kit page "Sheets") and returns what it was popped with (`Navigator.pop(context, value)`).
/// iPhone: [detents] the user can drag between (medium = floating material card, large = from the status bar), drag
/// down to dismiss. iPad: a centred card (detents ignored). Uses a Material-free [PopupRoute].
///
///     final saved = await showIosSheet<bool>(context,
///       title: 'New Event',
///       detents: const [IosSheetDetent.medium, IosSheetDetent.large],
///       leading: IosSheetButton(icon: AppleIcons.xmark, semanticLabel: 'Cancel', onPressed: () => Navigator.pop(context)),
///       trailing: IosSheetButton(icon: AppleIcons.checkmark, semanticLabel: 'Add', prominent: true,
///           onPressed: () => Navigator.pop(context, true)),
///       builder: (context) => const EventForm(),
///     );
Future<T?> showIosSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  String? subtitle,
  Widget? leading,
  Widget? trailing,
  List<IosSheetDetent> detents = const [IosSheetDetent.large],
  IosSheetDetent? initialDetent,
  ValueChanged<IosSheetDetent>? onDetentChanged,
  bool dismissible = true,
  bool fullScreen = false,
  bool showGrabber = true,
  bool scrollable = true,
  RouteSettings? settings,
  /// Present on the app's root navigator (default), so it covers the tab bar even from inside a tab's own stack.
  bool useRootNavigator = true,
}) {
  final theme = AppleTheme.of(context);
  final below = ModalRoute.of(context);
  final stacked = below is IosSheetRoute && below.detent.value == IosSheetDetent.large;
  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    IosSheetRoute<T>(
      builder: builder,
      title: title,
      subtitle: subtitle,
      leading: leading,
      trailing: trailing,
      detents: detents.isEmpty ? const [IosSheetDetent.large] : detents,
      initialDetent: initialDetent,
      onDetentChanged: onDetentChanged,
      dismissible: dismissible && !fullScreen,
      fullScreen: fullScreen,
      showGrabber: showGrabber,
      scrollable: scrollable,
      stacked: stacked,
      dim: fullScreen || stacked ? null : theme.ios.overlay,
      settings: settings,
    ),
  );
}

/// The route behind [showIosSheet] (a [PopupRoute], no Material). Use [showIosSheet] instead of creating it.
class IosSheetRoute<T> extends PopupRoute<T> {
  IosSheetRoute({
    required this.builder,
    this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    required this.detents,
    IosSheetDetent? initialDetent,
    this.onDetentChanged,
    this.dismissible = true,
    this.fullScreen = false,
    this.showGrabber = true,
    this.scrollable = true,
    this.stacked = false,
    this.dim,
    super.settings,
  }) : detent = ValueNotifier(initialDetent ?? detents.first);

  final WidgetBuilder builder;
  final String? title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final List<IosSheetDetent> detents;
  final ValueChanged<IosSheetDetent>? onDetentChanged;
  final bool dismissible;
  final bool fullScreen;
  final bool showGrabber;
  final bool scrollable;
  final bool stacked;
  final Color? dim;

  /// The current detent (changes when the user drags).
  final ValueNotifier<IosSheetDetent> detent;

  @override
  Color? get barrierColor => dim;
  @override
  bool get barrierDismissible => dismissible;
  @override
  String? get barrierLabel => 'Dismiss';
  @override
  Duration get transitionDuration => const Duration(milliseconds: 420);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 320);

  // Only a sheet opened on top makes this one step back (kit "Large (Stacked)").
  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) => nextRoute is IosSheetRoute;

  @override
  void dispose() {
    detent.dispose();
    super.dispose();
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    return _IosSheetBody(route: this);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final curve = CurvedAnimation(parent: animation, curve: const Cubic(0.32, 0.72, 0, 1), reverseCurve: Curves.easeIn);
    Widget page = reduceMotion
        ? FadeTransition(opacity: animation, child: child)
        : SlideTransition(
            position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curve),
            child: child,
          );
    // Stepping back when another sheet opens on top: 16 narrower each side (scaled from the top), dimmed 10%.
    return AnimatedBuilder(
      animation: secondaryAnimation,
      child: page,
      builder: (context, page) {
        final t = secondaryAnimation.value;
        if (t == 0) return page!;
        final width = MediaQuery.sizeOf(context).width;
        return Transform.scale(
          scale: 1 - (32 / width) * t,
          alignment: Alignment.topCenter,
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(Color.fromRGBO(0, 0, 0, 0.1 * t), BlendMode.srcATop),
            child: page,
          ),
        );
      },
    );
  }
}

class _IosSheetBody extends StatefulWidget {
  const _IosSheetBody({required this.route});
  final IosSheetRoute<dynamic> route;

  @override
  State<_IosSheetBody> createState() => _IosSheetBodyState();
}

class _IosSheetBodyState extends State<_IosSheetBody> with SingleTickerProviderStateMixin {
  late final AnimationController _settle;
  double _dy = 0; // + = moved down (translate), − = grown up (top moves, bottom stays)
  double _settleFrom = 0;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 380))
      ..addListener(() => setState(() => _dy = _settleFrom * (1 - Curves.easeOutCubic.transform(_settle.value))));
  }

  IosSheetRoute<dynamic> get route => widget.route;

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _setDetent(IosSheetDetent d) {
    if (route.detent.value == d) return;
    setState(() => route.detent.value = d);
    route.onDetentChanged?.call(d);
  }

  void _cycle() {
    final list = route.detents;
    if (list.length < 2 || IosLayout.isRegular(context)) return;
    _setDetent(list[(list.indexOf(route.detent.value) + 1) % list.length]);
  }

  @override
  Widget build(BuildContext context) {
    final regular = IosLayout.isRegular(context);
    final padTop = MediaQuery.paddingOf(context).top;
    final topInset = padTop > 0 ? padTop : (regular ? IosDimensions.ipad : IosDimensions.iphone).statusBarHeight;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return LayoutBuilder(
      builder: (context, box) {
        final screen = Size(box.maxWidth, box.maxHeight - keyboard);
        final detent = route.detent.value;
        final rect = iosSheetRect(
          screen: screen,
          detent: detent,
          regular: regular,
          fullScreen: route.fullScreen,
          stacked: route.stacked,
          topInset: topInset,
        );
        Rect place = rect;
        Offset shift = Offset.zero;
        if (_dy >= 0 || regular) {
          shift = Offset(0, math.max(_dy, 0));
        } else {
          place = Rect.fromLTRB(rect.left, rect.top + _dy, rect.right, rect.bottom);
        }

        Rect detentRect(IosSheetDetent d) => iosSheetRect(
          screen: screen,
          detent: d,
          regular: regular,
          fullScreen: route.fullScreen,
          stacked: route.stacked,
          topInset: topInset,
        );

        void onUpdate(DragUpdateDetails d) {
          if (route.fullScreen) return;
          _settle.stop();
          setState(() {
            var next = _dy + d.delta.dy;
            final minTop = !regular && route.detents.contains(IosSheetDetent.large)
                ? detentRect(IosSheetDetent.large).top
                : rect.top;
            final top = rect.top + next;
            if (top < minTop) next = minTop - rect.top - math.sqrt(minTop - top) * 2; // rubber band
            if (!route.dismissible && next > 0) next = math.sqrt(next) * 2;
            if (regular && next < 0) next = 0;
            _dy = next;
          });
        }

        void onEnd(DragEndDetails d) {
          if (route.fullScreen) return;
          final visualTop = rect.top + _dy;
          final projected = visualTop + d.velocity.pixelsPerSecond.dy * 0.22;
          final candidates = <(double, IosSheetDetent?)>[
            if (regular) (rect.top, detent) else for (final dt in route.detents) (detentRect(dt).top, dt),
            if (route.dismissible) (box.maxHeight, null),
          ];
          candidates.sort((a, b) => (a.$1 - projected).abs().compareTo((b.$1 - projected).abs()));
          final target = candidates.isEmpty ? (rect.top, detent) : candidates.first;
          if (target.$2 == null) {
            Navigator.of(context).pop(); // the slide-out continues from where the finger left the sheet
            return;
          }
          final newTop = detentRect(target.$2!).top;
          _setDetent(target.$2!);
          _settleFrom = visualTop - newTop;
          _dy = _settleFrom;
          _settle.forward(from: 0);
        }

        Widget sheet = IosSheet(
          title: route.title,
          subtitle: route.subtitle,
          leading: route.leading,
          trailing: route.trailing,
          detent: detent,
          fullScreen: route.fullScreen,
          showGrabber: route.showGrabber,
          scrollable: route.scrollable,
          onGrabberTap: _cycle,
          child: Builder(builder: route.builder),
        );
        // Drag anywhere that doesn't scroll (grabber, toolbar, short content): an inner scroll view wins the gesture.
        sheet = GestureDetector(
          onVerticalDragUpdate: onUpdate,
          onVerticalDragEnd: onEnd,
          behavior: HitTestBehavior.translucent,
          child: sheet,
        );
        return Stack(
          children: [Positioned.fromRect(rect: place.shift(shift), child: sheet)],
        );
      },
    );
  }
}
