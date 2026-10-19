import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../core/mac_support.dart';
import '../core/theme.dart';

/// Scroll edge effect styles (kit page "Materials": Scroll Edge Effect - Hard / - Soft).
enum MacScrollEdgeStyle {
  /// No effect.
  none,

  /// Translucent band (white 85% · #1F1F1F 55%, blur) with a 0.67 px hairline on the side that faces the content.
  /// Use it under anything with text or controls that must stay readable (title bars, list headers).
  hard,

  /// Blur only, fading out from the edge. Use it only under floating material controls with no bar behind them.
  soft,
}

/// A scroll view with macOS overlay scroll bars (kit page "Scrollbar"): no track, no arrows, a 6 px rounded thumb
/// (black 50% · white 55%) inset 3 px inside a 12 px strip at the right (vertical) or bottom (horizontal) edge.
/// The thumb hides while the window is inactive (`MacWindowState`).
///
///     MacScrollView(padding: const EdgeInsets.all(20), child: Column(children: rows))
///     MacScrollView(autohide: true, child: longText)                       // thumb only while the pointer is over it
///     MacScrollView(header: const Padding(padding: EdgeInsets.fromLTRB(14, 8, 14, 8), child: Text('Today')),
///                   child: Column(children: rows))                          // header stays put, rows scroll under it
///     MacScrollView(bottomEdge: MacScrollEdgeStyle.soft, edgeSize: 64, child: grid)   // under floating buttons
///
/// The window content area ([MacContent]), sidebars and inspectors already scroll: don't wrap them in another one.
/// The child is at least as tall as the viewport (minus [padding]), so `MacEmptyState` and `MacEditor` can fill it.
class MacScrollView extends StatefulWidget {
  const MacScrollView({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.scrollDirection = Axis.vertical,
    this.controller,
    this.autohide = false,
    this.header,
    this.topEdge = MacScrollEdgeStyle.none,
    this.bottomEdge = MacScrollEdgeStyle.none,
    this.edgeSize = 52,
    this.fillViewport = true,
    this.semanticLabel,
  });

  final Widget child;

  /// Space around the child, inside the scrolling area (the window content area uses 20).
  final EdgeInsetsGeometry padding;
  final Axis scrollDirection;
  final ScrollController? controller;

  /// Show the thumb only while the pointer is over the view or focus is inside it (macOS "Show scroll bars:
  /// Automatically"). Default false: always visible, like the kit's active windows.
  final bool autohide;

  /// A bar that stays at the top while the content scrolls under it, drawn on the hard scroll edge band
  /// (web `mac-scroll-edge` with content). Vertical scroll views only.
  final Widget? header;

  /// An effect-only edge over the top of the content ([edgeSize] tall, lets clicks through).
  final MacScrollEdgeStyle topEdge;

  /// An effect-only edge over the bottom of the content.
  final MacScrollEdgeStyle bottomEdge;

  /// Height of [topEdge] / [bottomEdge] (web `--mac-scroll-edge-size`, default 52).
  final double edgeSize;

  /// Make the child at least as tall (wide) as the visible area. Ignored when [header] is set.
  final bool fillViewport;

  /// Accessible name of the scroll area (for content without focusable children).
  final String? semanticLabel;

  @override
  State<MacScrollView> createState() => _MacScrollViewState();
}

class _MacScrollViewState extends State<MacScrollView> {
  ScrollController? _own;
  bool _hovered = false;
  bool _focusInside = false;

  ScrollController get _controller => widget.controller ?? (_own ??= ScrollController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final inactive = MacWindowState.isInactive(context);
    final vertical = widget.scrollDirection == Axis.vertical;
    final visible = !inactive && (!widget.autohide || _hovered || _focusInside);

    Widget view = LayoutBuilder(
      builder: (context, constraints) {
        final padding = widget.padding.resolve(Directionality.of(context));
        Widget content = widget.child;
        final fill = widget.fillViewport && widget.header == null;
        if (fill) {
          final extent = vertical ? constraints.maxHeight - padding.vertical : constraints.maxWidth - padding.horizontal;
          if (extent.isFinite && extent > 0) {
            content = ConstrainedBox(
              constraints: vertical ? BoxConstraints(minHeight: extent) : BoxConstraints(minWidth: extent),
              child: content,
            );
          }
        }
        return CustomScrollView(
          controller: _controller,
          scrollDirection: widget.scrollDirection,
          slivers: [
            if (widget.header != null && vertical) PinnedHeaderSliver(child: MacScrollEdge(child: widget.header)),
            SliverPadding(
              padding: padding,
              sliver: SliverToBoxAdapter(child: content),
            ),
          ],
        );
      },
    );
    view = ScrollConfiguration(behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false, overscroll: false), child: view);

    if (widget.topEdge != MacScrollEdgeStyle.none || widget.bottomEdge != MacScrollEdgeStyle.none) {
      view = Stack(
        children: [
          Positioned.fill(child: view),
          if (widget.topEdge != MacScrollEdgeStyle.none)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: MacScrollEdge(style: widget.topEdge, size: widget.edgeSize),
            ),
          if (widget.bottomEdge != MacScrollEdgeStyle.none)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MacScrollEdge(style: widget.bottomEdge, bottom: true, size: widget.edgeSize),
            ),
        ],
      );
    }

    // Kit "Scrollbar": 12 px strip, 6 px thumb inset 3 px from the strip sides and from both ends of the track.
    view = RawScrollbar(
      controller: _controller,
      thumbVisibility: visible,
      trackVisibility: false,
      thickness: 6,
      radius: const Radius.circular(3),
      crossAxisMargin: 3,
      mainAxisMargin: 3,
      minThumbLength: 8,
      // The kit's inactive windows show no scroll bar at all (not even while scrolling).
      thumbColor: inactive ? const Color(0x00000000) : theme.mac.scrollbarThumb,
      fadeDuration: const Duration(milliseconds: 200),
      timeToFade: const Duration(milliseconds: 800),
      child: view,
    );

    if (widget.autohide) {
      view = MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Focus(canRequestFocus: false, skipTraversal: true, onFocusChange: (v) => setState(() => _focusInside = v), child: view),
      );
    }
    if (widget.semanticLabel != null) {
      view = Semantics(container: true, label: widget.semanticLabel, child: view);
    }
    return view;
  }
}

/// The scroll edge effect on its own (web `mac-scroll-edge`): the band that keeps a bar readable while content
/// scrolls under it. [MacScrollView] draws it for you (`header`, `topEdge`, `bottomEdge`); use this widget directly
/// only for your own overlays.
///
///     MacScrollEdge(child: Padding(padding: EdgeInsets.all(8), child: Text('Today')))   // hard band with content
///     MacScrollEdge(style: MacScrollEdgeStyle.soft, bottom: true, size: 64)            // effect only
class MacScrollEdge extends StatelessWidget {
  const MacScrollEdge({super.key, this.child, this.style = MacScrollEdgeStyle.hard, this.bottom = false, this.size = 52});

  /// Content of the band (a list header). Null = the effect only, [size] tall, letting clicks through.
  final Widget? child;
  final MacScrollEdgeStyle style;

  /// At the bottom edge: the hairline is on top, the soft blur fades upwards.
  final bool bottom;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (style == MacScrollEdgeStyle.none) return child ?? const SizedBox.shrink();
    final dark = AppleTheme.of(context).isDark;
    if (style == MacScrollEdgeStyle.soft) {
      // Kit: background blur 10 under a gradient mask (#000 0%, 90% at 35%, transparent 100%). Drawn as bands of
      // decreasing blur, because a backdrop blur cannot be masked by a gradient in Flutter.
      const steps = 8;
      final bands = <Widget>[
        for (var i = 0; i < steps; i++)
          Expanded(
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 5 * _softMask((i + 0.5) / steps), sigmaY: 5 * _softMask((i + 0.5) / steps)),
                child: const SizedBox.expand(),
              ),
            ),
          ),
      ];
      final effect = IgnorePointer(
        child: SizedBox(
          height: size,
          child: Column(children: bottom ? bands.reversed.toList() : bands),
        ),
      );
      return child == null
          ? effect
          : Stack(
              children: [
                Positioned.fill(child: effect),
                child!,
              ],
            );
    }
    // Hard (kit): fill white 85% · #1F1F1F 55%, background blur, 0.67 px divider black 5% · white 10%.
    final fill = dark ? const Color(0x8C1F1F1F) : const Color(0xD9FFFFFF);
    final divider = BorderSide(width: 0.67, color: dark ? const Color(0x1AFFFFFF) : const Color(0x0D000000));
    Widget band = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        border: bottom ? Border(top: divider) : Border(bottom: divider),
      ),
      child: child == null
          ? SizedBox(height: size, width: double.infinity)
          : Padding(
              padding: EdgeInsets.only(top: bottom ? 0.67 : 0, bottom: bottom ? 0 : 0.67),
              child: child,
            ),
    );
    band = ClipRect(
      child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3), child: band),
    );
    return child == null ? IgnorePointer(child: band) : band;
  }

  static double _softMask(double t) => t <= 0.35 ? 1 - 0.1 * (t / 0.35) : 0.9 * (1 - (t - 0.35) / 0.65);
}
