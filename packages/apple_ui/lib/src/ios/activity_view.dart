import 'package:flutter/widgets.dart';

import '../core/adaptive.dart';
import '../core/glass.dart';
import '../core/icons.dart';
import '../core/ios_tokens.dart';
import '../core/theme.dart';
import '../core/typography.dart';
import '_presentation_support.dart';
import 'button.dart';
import 'sheet.dart';

/// A person (suggested conversation) in the first row of an [IosActivityView] (kit "_Contact").
@immutable
class IosActivityViewPerson {
  const IosActivityViewPerson({required this.name, this.detail, this.image, this.images, this.badge, this.onPressed});

  /// "First Last": shown on two lines (first name, last name), like iOS.
  final String name;

  /// A second line instead of the last name, e.g. "2 People" for a group.
  final String? detail;

  /// The photo (70 circle). Null = initials on grey.
  final ImageProvider? image;

  /// A group: two photos (37 and 22) in a grey circle.
  final List<ImageProvider>? images;

  /// The app of the conversation (kit: Messages), 20 × 20, corner 5, bottom right.
  final ImageProvider? badge;
  final VoidCallback? onPressed;
}

/// An app in the second row (kit "App Icon Row": 66 × 66 icon, corner 15).
@immutable
class IosActivityViewApp {
  const IosActivityViewApp({required this.name, required this.icon, this.onPressed});
  final String name;
  final ImageProvider icon;
  final VoidCallback? onPressed;
}

/// An action: a round button in the third row (kit "_Action") or a row in an action group (kit "_Actions").
@immutable
class IosActivityViewAction {
  const IosActivityViewAction({required this.label, required this.icon, this.onPressed, this.destructive = false});
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool destructive;
}

/// The share sheet's content (kit page "Activity Views", "_Activity View"): header (thumbnail, title, subtitle,
/// optional options button and note, close button), rows of people, apps and round actions, then lists of actions
/// and "Edit Actions". Present it with [showIosActivityView] (a sheet on iPhone, a popover on iPad).
///
///     IosActivityView(
///       title: 'Trip to Rome', subtitle: '12 Photos', thumbnail: const AssetImage('assets/rome.jpg'),
///       apps: [IosActivityViewApp(name: 'Messages', icon: const AssetImage('assets/messages.png'), onPressed: send)],
///       actions: [IosActivityViewAction(label: 'Copy', icon: AppleIcons.docOnDoc, onPressed: copy)],
///       actionGroups: [[IosActivityViewAction(label: 'Print', icon: AppleIcons.printer, onPressed: print)]],
///       onClose: () => Navigator.pop(context),
///     )
class IosActivityView extends StatelessWidget {
  const IosActivityView({
    super.key,
    required this.title,
    this.subtitle,
    this.thumbnail,
    this.options,
    this.note,
    this.onNoteTap,
    this.people = const [],
    this.apps = const [],
    this.actions = const [],
    this.actionGroups = const [],
    this.onEditActions,
    this.onClose,
    this.scrollable = true,
  });

  final String title;
  final String? subtitle;
  final ImageProvider? thumbnail;

  /// Optional material button under the title (kit: "Collaborate ›").
  final IosActivityViewAction? options;

  /// Optional secondary line with a chevron (kit: "Only invited people can edit. ›").
  final String? note;
  final VoidCallback? onNoteTap;
  final List<IosActivityViewPerson> people;
  final List<IosActivityViewApp> apps;
  final List<IosActivityViewAction> actions;

  /// Lists of actions, one rounded group each.
  final List<List<IosActivityViewAction>> actionGroups;

  /// Shows the "Edit Actions" material button at the end.
  final VoidCallback? onEditActions;

  /// The close button (44 circle of Regular blur material, top right). Null = no close button.
  final VoidCallback? onClose;

  /// Scrolls by itself (true) or lays out at its full height inside your own scroll view (false).
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final t = IosTypography.of(context);
    final caption = t.caption2;
    final separator = Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Container(height: 1, color: c.separator));

    Widget row(EdgeInsets padding, List<Widget> items) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: padding,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < items.length; i++) ...[if (i > 0) const SizedBox(width: 14), SizedBox(width: 78, child: items[i])],
          ]),
        );
    Widget tap(VoidCallback? onPressed, String label, Widget child) => Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onPressed, child: child),
        );

    final children = <Widget>[
      _Header(
        title: title,
        subtitle: subtitle,
        thumbnail: thumbnail,
        options: options,
        note: note,
        onNoteTap: onNoteTap,
        onClose: onClose,
      ),
      if (people.isNotEmpty) ...[
        separator,
        row(const EdgeInsets.fromLTRB(24, 14, 24, 16), [
          for (final p in people)
            tap(
              p.onPressed,
              p.detail != null ? '${p.name}, ${p.detail}' : p.name,
              Column(children: [
                _Avatar(person: p),
                const SizedBox(height: 5),
                SizedBox(
                  height: 29,
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: p.detail != null ? p.name : p.name.split(' ').first),
                      const TextSpan(text: '\n'),
                      p.detail != null
                          ? TextSpan(text: p.detail, style: TextStyle(color: c.labelSecondary))
                          : TextSpan(text: p.name.split(' ').skip(1).join(' ')),
                    ]),
                    style: caption.copyWith(height: 14 / 11),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
        ]),
      ],
      if (apps.isNotEmpty) ...[
        separator,
        row(const EdgeInsets.fromLTRB(24, 18, 24, 20), [
          for (final a in apps)
            tap(
              a.onPressed,
              a.name,
              Column(children: [
                ClipRSuperellipse(
                  borderRadius: BorderRadius.circular(15),
                  child: Image(image: a.icon, width: 66, height: 66, fit: BoxFit.cover),
                ),
                const SizedBox(height: 11),
                Text(a.name, style: caption, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
              ]),
            ),
        ]),
      ],
      if (actions.isNotEmpty) ...[
        separator,
        row(const EdgeInsets.fromLTRB(24, 14, 24, 20), [
          for (final a in actions)
            tap(
              a.onPressed,
              a.label,
              Column(children: [
                Container(
                  width: 66,
                  height: 66,
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    // Kit Fills - Vibrant/Tertiary drawn plus-darker / plus-lighter.
                    color: theme.isDark ? const Color(0xFF2E2E30) : const Color(0xFFEDEDED),
                    shape: const CircleBorder(),
                  ),
                  child: Icon(a.icon, size: 30, color: a.destructive ? c.red : c.labelVibrantPrimary),
                ),
                const SizedBox(height: 7),
                // One line of height; a second line hangs into the row's bottom padding (kit: the row stays 120).
                SizedBox(
                  height: 13,
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    maxHeight: 26,
                    child: Text(a.label,
                        style: caption.copyWith(color: c.labelVibrantPrimary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center),
                  ),
                ),
              ]),
            ),
        ]),
      ],
      for (var g = 0; g < actionGroups.length; g++)
        Padding(
          padding: EdgeInsets.fromLTRB(16, g == 0 ? 2 : 0, 16, 20),
          child: ClipRSuperellipse(
            borderRadius: BorderRadius.circular(26),
            child: ColoredBox(
              color: c.fillSecondary,
              child: Column(children: [
                for (var i = 0; i < actionGroups[g].length; i++)
                  _ListAction(action: actionGroups[g][i], separated: i > 0),
              ]),
            ),
          ),
        ),
      if (onEditActions != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Center(
            child: IosButton(label: 'Edit Actions', style: IosButtonStyle.glass, size: IosButtonSize.large, onPressed: onEditActions),
          ),
        ),
    ];
    final column = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
    return DefaultTextStyle(
      style: t.body,
      child: scrollable ? SingleChildScrollView(child: column) : column,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.subtitle, this.thumbnail, this.options, this.note, this.onNoteTap, this.onClose});
  final String title;
  final String? subtitle;
  final ImageProvider? thumbnail;
  final IosActivityViewAction? options;
  final String? note;
  final VoidCallback? onNoteTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = AppleTheme.of(context).ios;
    final t = IosTypography.of(context);
    // Kit "_Header": padding 16, gap 16; thumbnail 64 (corner 16) at 12/14; title Medium 15, subtitle Regular 13.
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 14),
          child: CustomPaint(
            painter: PresentationShadowPainter(
                const [GlassShadow(0, 2, 16, 0, Color(0x26000000))], RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(16))),
            child: Container(
              width: 64,
              height: 64,
              foregroundDecoration: ShapeDecoration(
                shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0x26000000), width: 0.5)),
              ),
              child: ClipRSuperellipse(
                borderRadius: BorderRadius.circular(16),
                child: thumbnail != null ? Image(image: thumbnail!, fit: BoxFit.cover) : ColoredBox(color: c.fillTertiary),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 2),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: t.subheadline.copyWith(fontWeight: FontWeight.w500, color: c.labelVibrantPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              if (subtitle != null) ...[
                const SizedBox(height: 1),
                Text(subtitle!, style: t.footnote.copyWith(color: c.labelVibrantSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
              if (options != null) ...[const SizedBox(height: 12), _OptionsButton(action: options!)],
              if (note != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  button: onNoteTap != null,
                  child: GestureDetector(
                    onTap: onNoteTap,
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${note!} '),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Icon(AppleIcons.chevronRight, size: 15, color: c.labelVibrantTertiary),
                        ),
                      ]),
                      style: t.subheadline.copyWith(height: 18 / 15, color: c.labelVibrantSecondary),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ),
        const SizedBox(width: 16),
        if (onClose != null) IosSheetButton(icon: AppleIcons.xmark, semanticLabel: 'Close', onPressed: onClose),
      ]),
    );
  }
}

/// Kit "_Button - Liquid Glass", drawn on the Regular blur material: 34 tall, padding 6/10/6/14, gap 4, symbol +
/// label Medium 15 + chevron (secondary).
class _OptionsButton extends StatelessWidget {
  const _OptionsButton({required this.action});
  final IosActivityViewAction action;

  @override
  Widget build(BuildContext context) {
    final c = AppleTheme.of(context).ios;
    final style = IosTypography.of(context).subheadline.copyWith(fontWeight: FontWeight.w500, color: c.labelControlPrimary);
    return Semantics(
      button: true,
      label: action.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: action.onPressed,
        child: AppleGlass(
          child: SizedBox(
            height: 34,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(action.icon, size: 18, color: c.labelControlPrimary),
                const SizedBox(width: 4),
                Text(action.label, style: style),
                const SizedBox(width: 4),
                Icon(AppleIcons.chevronRight, size: 15, color: c.labelControlSecondary),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.person});
  final IosActivityViewPerson person;

  @override
  Widget build(BuildContext context) {
    final c = AppleTheme.of(context).ios;
    Widget face;
    if (person.images != null && person.images!.length >= 2) {
      face = Container(
        decoration: ShapeDecoration(color: c.fillSecondary, shape: const CircleBorder()),
        child: Stack(children: [
          Positioned(left: 9, top: 9, width: 37, height: 37, child: ClipOval(child: Image(image: person.images![0], fit: BoxFit.cover))),
          Positioned(left: 39, top: 39, width: 22, height: 22, child: ClipOval(child: Image(image: person.images![1], fit: BoxFit.cover))),
        ]),
      );
    } else if (person.image != null) {
      face = ClipOval(child: Image(image: person.image!, fit: BoxFit.cover));
    } else {
      final initials = person.name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).map((p) => p[0]).take(2).join().toUpperCase();
      face = Container(
        alignment: Alignment.center,
        decoration: const ShapeDecoration(
          shape: CircleBorder(),
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFA5ABB8), Color(0xFF858994)]),
        ),
        child: Text(initials, style: appleFont(size: 28).copyWith(fontSize: 28, fontWeight: FontWeight.w500, color: const Color(0xFFFFFFFF))),
      );
    }
    return SizedBox(
      width: 70,
      height: 70,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: face),
        if (person.badge != null)
          Positioned(
            right: 0,
            bottom: 0,
            width: 20,
            height: 20,
            child: ClipRSuperellipse(borderRadius: BorderRadius.circular(5), child: Image(image: person.badge!, fit: BoxFit.cover)),
          ),
      ]),
    );
  }
}

/// Kit "_Actions": a 52-tall row, symbol column 48 wide (8 from the edge), title Regular 17 from x 56,
/// separator above the title (not on the first row).
class _ListAction extends StatelessWidget {
  const _ListAction({required this.action, required this.separated});
  final IosActivityViewAction action;
  final bool separated;

  @override
  Widget build(BuildContext context) {
    final c = AppleTheme.of(context).ios;
    final color = action.destructive ? c.red : c.labelPrimary;
    return Semantics(
      button: true,
      label: action.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: action.onPressed,
        child: SizedBox(
          height: 52,
          child: Row(children: [
            const SizedBox(width: 8),
            SizedBox(width: 48, child: Center(child: Icon(action.icon, size: 20.4, color: color))),
            Expanded(
              child: Container(
                height: 52,
                margin: const EdgeInsets.only(right: 16),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(border: separated ? Border(top: BorderSide(color: c.separator)) : null),
                child: Text(action.label,
                    style: IosTypography.of(context).body.copyWith(color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Presents the share sheet. iPhone: a sheet (medium and large detents, grabber, drag to dismiss) over a dimmed page
/// (kit "Overlay - Activity View Controller"). iPad: a 402-wide material popover next to [anchorKey]'s button
/// (corners 38), no dimming; a tap outside closes it. Actions run their onPressed and close the sheet.
///
///     final shareKey = GlobalKey();
///     IosButton(key: shareKey, icon: AppleIcons.squareAndArrowUp, semanticLabel: 'Share', style: IosButtonStyle.glass,
///         onPressed: () => showIosActivityView(context, anchorKey: shareKey, title: 'Trip to Rome', subtitle: '12 Photos',
///             actions: [IosActivityViewAction(label: 'Copy', icon: AppleIcons.docOnDoc, onPressed: copy)]))
Future<void> showIosActivityView(
  BuildContext context, {
  GlobalKey? anchorKey,
  required String title,
  String? subtitle,
  ImageProvider? thumbnail,
  IosActivityViewAction? options,
  String? note,
  VoidCallback? onNoteTap,
  List<IosActivityViewPerson> people = const [],
  List<IosActivityViewApp> apps = const [],
  List<IosActivityViewAction> actions = const [],
  List<List<IosActivityViewAction>> actionGroups = const [],
  VoidCallback? onEditActions,
  /// Present on the app's root navigator (default), so it covers the tab bar even from inside a tab's own stack.
  bool useRootNavigator = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  VoidCallback? andClose(VoidCallback? f) => () {
        navigator.pop();
        f?.call();
      };
  IosActivityViewAction closing(IosActivityViewAction a) =>
      IosActivityViewAction(label: a.label, icon: a.icon, destructive: a.destructive, onPressed: andClose(a.onPressed));
  Widget content() => IosActivityView(
        title: title,
        subtitle: subtitle,
        thumbnail: thumbnail,
        options: options,
        note: note,
        onNoteTap: onNoteTap,
        people: [
          for (final p in people)
            IosActivityViewPerson(name: p.name, detail: p.detail, image: p.image, images: p.images, badge: p.badge, onPressed: andClose(p.onPressed)),
        ],
        apps: [for (final a in apps) IosActivityViewApp(name: a.name, icon: a.icon, onPressed: andClose(a.onPressed))],
        actions: [for (final a in actions) closing(a)],
        actionGroups: [for (final g in actionGroups) [for (final a in g) closing(a)]],
        onEditActions: onEditActions,
        onClose: () => navigator.pop(),
      );

  if (!IosLayout.isRegular(context)) {
    final theme = AppleTheme.of(context);
    return navigator.push<void>(IosSheetRoute<void>(
      builder: (_) => content(),
      detents: const [IosSheetDetent.medium, IosSheetDetent.large],
      scrollable: false,
      dim: theme.ios.overlayActivity,
    ));
  }
  return navigator.push<void>(_IosActivityPopoverRoute(source: presentationRectOf(anchorKey), builder: content));
}

class _IosActivityPopoverRoute extends PopupRoute<void> {
  _IosActivityPopoverRoute({this.source, required this.builder});
  final Rect? source;
  final Widget Function() builder;

  @override
  Color? get barrierColor => const Color(0x00000000);
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => 'Close';
  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final screen = MediaQuery.sizeOf(context);
    final dims = IosDimensions.ipad;
    final padTop = MediaQuery.paddingOf(context).top;
    final statusBar = padTop > 0 ? padTop : dims.statusBarHeight;
    final top = source != null ? source!.bottom + 6 : statusBar + 60;
    final height = (screen.height - top - 8).clamp(200.0, 970.0);
    final size = Size(402, height);
    final pos = source != null
        ? Offset((source!.center.dx > screen.width / 2 ? source!.right - 402 : source!.left).clamp(8.0, screen.width - 410), top)
        : Offset(screen.width - 410, top);
    return Stack(children: [
      Positioned(
        left: pos.dx,
        top: pos.dy,
        width: size.width,
        height: size.height,
        child: PresentationGlass(
          radius: BorderRadius.circular(dims.popoverRadius),
          extraShadows: const [GlassShadow(0, 10, 100, 0, Color(0x4D000000))],
          child: Stack(children: [
            Positioned.fill(child: builder()),
            // Grabber (decorative on iPad, kit "Activity View - iPad").
            Positioned(
              top: 6,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: dims.grabberWidth,
                  height: dims.grabberHeight,
                  decoration: ShapeDecoration(color: AppleTheme.of(context).ios.labelTertiary, shape: const StadiumBorder()),
                ),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final curved = CurvedAnimation(parent: animation, curve: const Cubic(0.32, 0.72, 0, 1));
    if (MediaQuery.disableAnimationsOf(context)) return FadeTransition(opacity: animation, child: child);
    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(alignment: Alignment.topRight, scale: Tween(begin: 0.8, end: 1.0).animate(curved), child: child),
    );
  }
}
