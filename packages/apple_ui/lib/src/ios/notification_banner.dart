import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/adaptive.dart';
import '../core/glass.dart';
import '../core/theme.dart';
import '../core/typography.dart';
import '_presentation_support.dart' show PresentationGlass;

/// Where a notification is shown (kit page "Notifications").
enum IosNotificationStyle {
  /// Lock Screen and Notification Center: the Regular blur material ([AppleGlassStyle.regular]) with the label
  /// colours (dark text in Light, white in Dark), over the wallpaper or a photo.
  lockScreen,

  /// Over an app's content (in-app banner): the Thick blur material ([AppleGlassStyle.panel]) and label colours
  /// (Light and Dark).
  banner,
}

/// One notification (banner) of the kit page "Notifications": app icon, title, message, time, optional thumbnail.
///
///     IosNotificationBanner(
///       appIcon: Image.asset('assets/icon.png'),
///       title: 'Anna Haro',
///       message: 'Are we still on for lunch tomorrow?',
///       time: 'now',
///       onTap: openConversation,
///     )
///     IosNotificationBanner(title: 'Weather', message: 'Rain in 20 minutes.', time: '9:41 AM', stackCount: 3)
///
/// Lock Screen style by default (Regular material: put it over a wallpaper or photo). For an in-app banner use
/// [IosNotificationStyle.banner], or call [showIosNotificationBanner] to slide one in from the top.
class IosNotificationBanner extends StatefulWidget {
  const IosNotificationBanner({
    super.key,
    required this.title,
    this.message,
    this.time,
    this.appIcon,
    this.image,
    this.style = IosNotificationStyle.lockScreen,
    this.stackCount = 1,
    this.onTap,
  }) : assert(stackCount >= 1);

  /// Bold first line: the app name or the sender.
  final String title;

  /// The text, up to 4 lines.
  final String? message;

  /// "9:41 AM", "now", "2m ago".
  final String? time;

  /// The app icon (any widget; it is sized 38.33 × 38.33 and clipped to the app icon shape).
  final Widget? appIcon;

  /// Optional 32 × 32 thumbnail under the time (a photo in the message).
  final Widget? image;
  final IosNotificationStyle style;

  /// Notifications grouped in this stack. 2 = one card peeks out below, 3 or more = two cards.
  final int stackCount;

  /// Tap: open the related content. Null = not tappable.
  final VoidCallback? onTap;

  @override
  State<IosNotificationBanner> createState() => _IosNotificationBannerState();
}

class _IosNotificationBannerState extends State<IosNotificationBanner> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final lock = widget.style == IosNotificationStyle.lockScreen;
    // Label colours on both materials (Lock Screen: Regular, in-app banner: Thick), like the classic notifications.
    final label = c.labelPrimary;
    final secondary = c.labelSecondary;
    final stacked = widget.stackCount > 1;
    final glassStyle = lock ? AppleGlassStyle.regular : AppleGlassStyle.panel;

    final card = AppleGlass(
      style: glassStyle,
      radius: 24,
      child: Padding(
        // Kit: 14 all round (66.33 tall); a stacked front card is 63 tall (12 / 12.67).
        padding: EdgeInsets.fromLTRB(14, stacked ? 12 : 14, 14, stacked ? 12.67 : 14),
        child: _NotificationRow(
          appIcon: widget.appIcon,
          title: widget.title,
          message: widget.message,
          time: widget.time,
          image: widget.image,
          label: label,
          secondary: secondary,
          iconGap: 10,
        ),
      ),
    );

    Widget body = card;
    if (stacked) {
      final depth = widget.stackCount >= 3 ? 2 : 1;
      body = Padding(
        padding: EdgeInsets.only(bottom: depth == 2 ? 14.33 : 8.33),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = depth; i >= 1; i--)
              Positioned(
                left: 10.0 * i,
                right: 10.0 * i,
                top: 8.0 * i,
                bottom: -8.0 * i,
                // Only the 8 px strip below the card in front shows (no material on top of material).
                child: ClipRect(
                  clipper: const _PeekClipper(),
                  child: AppleGlass(style: glassStyle, radius: 24, child: const SizedBox.expand()),
                ),
              ),
            card,
          ],
        ),
      );
    }

    if (widget.onTap != null) {
      body = AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 200),
        child: body,
      );
      body = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: body,
      );
    }
    return Semantics(
      container: true,
      button: widget.onTap != null,
      label: [widget.title, widget.message, widget.time].whereType<String>().join(', '),
      excludeSemantics: true,
      child: body,
    );
  }
}

class _PeekClipper extends CustomClipper<Rect> {
  const _PeekClipper();
  @override
  Rect getClip(Size size) => Rect.fromLTRB(-4, size.height - 8.5, size.width + 4, size.height + 24);
  @override
  bool shouldReclip(_PeekClipper oldClipper) => false;
}

/// Icon + title/message + time/thumbnail (shared by the collapsed and expanded notification).
class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.appIcon,
    required this.title,
    required this.message,
    required this.time,
    required this.image,
    required this.label,
    required this.secondary,
    required this.iconGap,
  });

  final Widget? appIcon;
  final String title;
  final String? message;
  final String? time;
  final Widget? image;
  final Color label;
  final Color secondary;
  final double iconGap;

  @override
  Widget build(BuildContext context) {
    final base = IosTypography.of(context).subheadline; // 15 pt at the default Dynamic Type size
    TextStyle style(FontWeight w, double lineRatio, Color color) => base.copyWith(
          fontWeight: w,
          height: lineRatio,
          color: color,
        );
    final titleRow = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 0.5),
            child: Text(title, style: style(FontWeight.w600, 17 / 15, label), maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false),
          ),
        ),
        if (time != null) ...[
          const SizedBox(width: 10),
          Text(time!, style: style(FontWeight.w400, 17 / 15, secondary), maxLines: 1, softWrap: false),
        ],
      ],
    );
    Widget? messageText =
        message == null ? null : Text(message!, style: style(FontWeight.w400, 18 / 15, label), maxLines: 4, overflow: TextOverflow.ellipsis);
    if (image != null) {
      // Thumbnail 32 × 32 (radius 6) under the time; the message runs beside it.
      messageText = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: messageText ?? const SizedBox()),
        Padding(
          padding: const EdgeInsets.only(left: 10, top: 5),
          child: ClipRSuperellipse(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(width: 32, height: 32, child: FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: image)),
          ),
        ),
      ]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _IosAppIconBox(size: 38.33, child: appIcon),
        SizedBox(width: iconGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [titleRow, ?messageText],
          ),
        ),
      ],
    );
  }
}

/// An app icon box: [size] square, clipped to the iOS app icon shape (continuous corners, 26 % radius).
class _IosAppIconBox extends StatelessWidget {
  const _IosAppIconBox({required this.size, this.child});
  final double size;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ClipRSuperellipse(
      borderRadius: BorderRadius.circular(size * 0.2237),
      child: SizedBox(
        width: size,
        height: size,
        child: child == null
            ? ColoredBox(color: AppleTheme.of(context).ios.fillSecondary)
            : FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: child),
      ),
    );
  }
}

/// A list of notifications: 8 apart, 14 from the sides (Lock Screen / Notification Center, kit "Notification - Collapsed - List").
///
///     IosNotificationList(children: [IosNotificationBanner(...), IosNotificationBanner(..., stackCount: 2)])
class IosNotificationList extends StatelessWidget {
  const IosNotificationList({super.key, required this.children, this.padding = const EdgeInsets.fromLTRB(14, 16, 14, 16)});
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: children,
      ),
    );
  }
}

/// One action of an expanded notification.
@immutable
class IosNotificationAction {
  const IosNotificationAction({required this.label, this.icon, this.destructive = false, this.onPressed});
  final String label;
  final IconData? icon;

  /// Red: the action deletes or removes something.
  final bool destructive;
  final VoidCallback? onPressed;
}

/// The expanded notification (long press; kit "Notification - Expanded"): a card with the header and your custom
/// content, and a menu of actions on the Thick blur material (label colours) below it. Show it over a dimmed,
/// blurred screen.
///
///     IosExpandedNotification(
///       title: 'Anna Haro', message: 'Lunch tomorrow?', time: '9:41 AM',
///       body: Padding(padding: EdgeInsets.all(14), child: Text('Let me know by 11.')),
///       actions: [IosNotificationAction(label: 'Reply', icon: AppleIcons.bubbleLeft, onPressed: reply)],
///     )
class IosExpandedNotification extends StatelessWidget {
  const IosExpandedNotification({
    super.key,
    required this.title,
    this.message,
    this.time,
    this.appIcon,
    this.body,
    this.actions = const [],
  });

  final String title;
  final String? message;
  final String? time;
  final Widget? appIcon;

  /// Your custom content under the header (Notification Content Extension on iOS).
  final Widget? body;
  final List<IosNotificationAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final t = IosTypography.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 10,
      children: [
        ClipRSuperellipse(
          borderRadius: BorderRadius.circular(26),
          child: ColoredBox(
            color: c.bgPrimaryElevated,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: _NotificationRow(
                    appIcon: appIcon,
                    title: title,
                    message: message,
                    time: time,
                    image: null,
                    label: c.labelPrimary,
                    secondary: c.labelSecondary,
                    iconGap: 12,
                  ),
                ),
                ?body,
              ],
            ),
          ),
        ),
        if (actions.isNotEmpty)
          SizedBox(
            width: 250,
            // Thick material with the small control shadow (ios.css `.ios-notification__actions`).
            child: PresentationGlass(
              radius: BorderRadius.circular(26),
              shadows: GlassRecipe.of(
                AppleGlassStyle.regular,
                dark: theme.isDark,
                accent: theme.accentColor,
                quaternaryFill: c.fillQuaternary,
              ).shadows,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final a in actions)
                      Semantics(
                        button: true,
                        label: a.label,
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: a.onPressed,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
                            child: Row(children: [
                              SizedBox(
                                width: 20,
                                child: a.icon == null
                                    ? null
                                    : Icon(a.icon, size: 20, color: a.destructive ? c.red : c.labelPrimary),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(a.label,
                                    style: t.body.copyWith(color: a.destructive ? c.red : c.labelPrimary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ]),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Slides an in-app notification banner in from the top of the screen (Thick blur material, Light/Dark). It hides
/// itself after [duration] or when swiped up; tapping it calls [onTap] and hides it. Returns a function that hides it
/// early.
///
///     showIosNotificationBanner(context, title: 'Anna Haro', message: 'Lunch tomorrow?', time: 'now',
///         appIcon: Image.asset('assets/icon.png'), onTap: openChat);
VoidCallback showIosNotificationBanner(
  BuildContext context, {
  required String title,
  String? message,
  String? time,
  Widget? appIcon,
  Widget? image,
  VoidCallback? onTap,
  Duration duration = const Duration(seconds: 4),
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  final key = GlobalKey<_BannerHostState>();
  var removed = false;
  void remove() {
    if (removed) return;
    removed = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (context) => _BannerHost(
      key: key,
      duration: duration,
      onDismissed: remove,
      child: IosNotificationBanner(
        style: IosNotificationStyle.banner,
        title: title,
        message: message,
        time: time,
        appIcon: appIcon,
        image: image,
        onTap: () {
          onTap?.call();
          key.currentState?.hide();
        },
      ),
    ),
  );
  overlay.insert(entry);
  return () => key.currentState?.hide();
}

class _BannerHost extends StatefulWidget {
  const _BannerHost({super.key, required this.child, required this.duration, required this.onDismissed});
  final Widget child;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_BannerHost> createState() => _BannerHostState();
}

class _BannerHostState extends State<_BannerHost> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  Timer? _timer;
  double _drag = 0;

  @override
  void initState() {
    super.initState();
    _c.forward();
    if (widget.duration > Duration.zero) _timer = Timer(widget.duration, hide);
  }

  Future<void> hide() async {
    _timer?.cancel();
    if (!mounted) return;
    await _c.reverse();
    widget.onDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final regular = IosLayout.isRegular(context);
    final top = MediaQuery.paddingOf(context).top + 8;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final curved = CurvedAnimation(parent: _c, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
    return Positioned(
      top: top,
      left: 8,
      right: 8,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: regular ? 374 : 402),
          child: GestureDetector(
            onVerticalDragUpdate: (d) => setState(() => _drag = (_drag + d.delta.dy).clamp(-200.0, 0.0)),
            onVerticalDragEnd: (_) {
              if (_drag < -24) {
                hide();
              } else {
                setState(() => _drag = 0);
              }
            },
            child: AnimatedBuilder(
              animation: curved,
              builder: (context, child) {
                final v = curved.value;
                return Opacity(
                  opacity: v.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, reduceMotion ? _drag : (1 - v) * -(top + 100) + _drag),
                    child: child,
                  ),
                );
              },
              child: Semantics(liveRegion: true, child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}
