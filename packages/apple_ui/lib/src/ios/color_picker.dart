import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

import '../core/adaptive.dart';
import '../core/glass.dart';
import '../core/icons.dart';
import '../core/theme.dart';
import '../core/typography.dart';

/// The kit's 12 × 10 colour grid ("Color Picker - iPhone" > Color Grid), rows top to bottom.
const List<List<Color>> kIosColorPickerPalette = [
  [
    Color(0xFFFEFFFE),
    Color(0xFFEBEBEB),
    Color(0xFFD6D6D6),
    Color(0xFFC2C2C2),
    Color(0xFFADADAD),
    Color(0xFF999999),
    Color(0xFF858585),
    Color(0xFF707070),
    Color(0xFF5C5C5C),
    Color(0xFF474747),
    Color(0xFF333333),
    Color(0xFF000000),
  ],
  [
    Color(0xFF00374A),
    Color(0xFF011D57),
    Color(0xFF11053B),
    Color(0xFF2E063D),
    Color(0xFF3C071B),
    Color(0xFF5C0701),
    Color(0xFF5A1C00),
    Color(0xFF583300),
    Color(0xFF563D00),
    Color(0xFF666100),
    Color(0xFF4F5504),
    Color(0xFF263E0F),
  ],
  [
    Color(0xFF004D65),
    Color(0xFF012F7B),
    Color(0xFF1A0A52),
    Color(0xFF450D59),
    Color(0xFF551029),
    Color(0xFF831100),
    Color(0xFF7B2900),
    Color(0xFF7A4A00),
    Color(0xFF785800),
    Color(0xFF8D8602),
    Color(0xFF6F760A),
    Color(0xFF38571A),
  ],
  [
    Color(0xFF016E8F),
    Color(0xFF0042A9),
    Color(0xFF2C0977),
    Color(0xFF61187C),
    Color(0xFF791A3D),
    Color(0xFFB51A00),
    Color(0xFFAD3E00),
    Color(0xFFA96800),
    Color(0xFFA67B01),
    Color(0xFFC4BC00),
    Color(0xFF9BA50E),
    Color(0xFF4E7A27),
  ],
  [
    Color(0xFF008CB4),
    Color(0xFF0056D6),
    Color(0xFF371A94),
    Color(0xFF7A219E),
    Color(0xFF99244F),
    Color(0xFFE22400),
    Color(0xFFDA5100),
    Color(0xFFD38301),
    Color(0xFFD19D01),
    Color(0xFFF5EC00),
    Color(0xFFC3D117),
    Color(0xFF669D34),
  ],
  [
    Color(0xFF00A1D8),
    Color(0xFF0061FD),
    Color(0xFF4D22B2),
    Color(0xFF982ABC),
    Color(0xFFB92D5D),
    Color(0xFFFF4015),
    Color(0xFFFF6A00),
    Color(0xFFFFAB01),
    Color(0xFFFCC700),
    Color(0xFFFEFB41),
    Color(0xFFD9EC37),
    Color(0xFF76BB40),
  ],
  [
    Color(0xFF01C7FC),
    Color(0xFF3A87FD),
    Color(0xFF5E30EB),
    Color(0xFFBE38F3),
    Color(0xFFE63B7A),
    Color(0xFFFE6250),
    Color(0xFFFE8648),
    Color(0xFFFEB43F),
    Color(0xFFFECB3E),
    Color(0xFFFFF76B),
    Color(0xFFE4EF65),
    Color(0xFF96D35F),
  ],
  [
    Color(0xFF52D6FC),
    Color(0xFF74A7FF),
    Color(0xFF864FFD),
    Color(0xFFD357FE),
    Color(0xFFEE719E),
    Color(0xFFFF8C82),
    Color(0xFFFEA57D),
    Color(0xFFFEC777),
    Color(0xFFFED977),
    Color(0xFFFFF994),
    Color(0xFFEAF28F),
    Color(0xFFB1DD8B),
  ],
  [
    Color(0xFF93E3FC),
    Color(0xFFA7C6FF),
    Color(0xFFB18CFE),
    Color(0xFFE292FE),
    Color(0xFFF4A4C0),
    Color(0xFFFFB5AF),
    Color(0xFFFFC5AB),
    Color(0xFFFED9A8),
    Color(0xFFFDE4A8),
    Color(0xFFFFFBB9),
    Color(0xFFF1F7B7),
    Color(0xFFCDE8B5),
  ],
  [
    Color(0xFFCBF0FF),
    Color(0xFFD2E2FE),
    Color(0xFFD8C9FE),
    Color(0xFFEFCAFE),
    Color(0xFFF9D3E0),
    Color(0xFFFFDAD8),
    Color(0xFFFFE2D6),
    Color(0xFFFEECD4),
    Color(0xFFFEF1D5),
    Color(0xFFFDFBDD),
    Color(0xFFF6FADB),
    Color(0xFFDEEED4),
  ],
];

/// The kit's rainbow ring (angular gradient, yellow at the top, clockwise).
const _rainbow = SweepGradient(
  colors: [
    Color(0xFFE7E040),
    Color(0xFFEEAA3C),
    Color(0xFFE8403B),
    Color(0xFFB33ED5),
    Color(0xFF694AE8),
    Color(0xFF3CCAE7),
    Color(0xFF3CE885),
    Color(0xFF89E743),
    Color(0xFFE7E040),
  ],
  stops: [0, 0.124, 0.249, 0.366, 0.506, 0.643, 0.749, 0.87, 1],
  transform: GradientRotation(-math.pi / 2),
);

bool _sameRgb(Color a, Color b) => (a.toARGB32() & 0xFFFFFF) == (b.toARGB32() & 0xFFFFFF);

/* ------------------------------------------------------------------ color well */

/// [small] 28 pt (default, list rows) · [large] 36 pt (kit "Picker Button" Size).
enum IosColorWellSize { small, large }

/// The iOS color well (SwiftUI ColorPicker, kit "Picker Button"): a rainbow ring with the colour inside. Tapping it opens
/// the color picker — a sheet on iPhone, a popover on iPad. A null [color] shows the full rainbow disc (no colour yet).
///
///     IosColorWell(color: tint, onChanged: (c) => setState(() => tint = c), semanticLabel: 'Highlight Color')
class IosColorWell extends StatelessWidget {
  const IosColorWell({
    super.key,
    required this.color,
    required this.onChanged,
    this.size = IosColorWellSize.small,
    this.supportsOpacity = true,
    this.title = 'Colors',
    this.semanticLabel = 'Color',
  });

  final Color? color;

  /// Null = disabled.
  final ValueChanged<Color>? onChanged;
  final IosColorWellSize size;

  /// Show the opacity slider in the picker.
  final bool supportsOpacity;

  /// Title of the picker.
  final String title;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final side = size == IosColorWellSize.large ? 36.0 : 28.0;
    final enabled = onChanged != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      value: color == null ? null : '#${(color!.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: !enabled
            ? null
            : () => showIosColorPicker(
                context,
                color: color ?? const Color(0xFFAF52DE),
                onChanged: onChanged!,
                supportsOpacity: supportsOpacity,
                title: title,
              ),
        child: Opacity(
          opacity: enabled ? 1 : 0.35,
          child: SizedBox(
            width: side,
            height: side,
            child: CustomPaint(painter: _WellPainter(color)),
          ),
        ),
      ),
    );
  }
}

class _WellPainter extends CustomPainter {
  _WellPainter(this.color);
  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final r = size.shortestSide / 2;
    final rainbow = Paint()..shader = _rainbow.createShader(rect);
    if (color == null) {
      canvas.drawCircle(center, r, rainbow);
      canvas.drawCircle(
        center,
        r,
        Paint()..shader = const RadialGradient(colors: [Color(0xFFE4E4E4), Color(0x00E4E4E4)], stops: [0, 0.88]).createShader(rect),
      );
      return;
    }
    // Ring 3 pt, then a 2 pt gap, then the colour.
    canvas.drawCircle(
      center,
      r - 1.5,
      rainbow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(center, r - 5, Paint()..color = color!);
  }

  @override
  bool shouldRepaint(_WellPainter old) => old.color != color;
}

/* ------------------------------------------------------------------ presenting */

/// Shows the color picker: a sheet 8 pt from the screen edges on iPhone (over the dimmed screen), a 402 pt popover next
/// to [context]'s widget on iPad. [onChanged] is called for every change; the future completes when it closes.
Future<void> showIosColorPicker(
  BuildContext context, {
  required Color color,
  required ValueChanged<Color> onChanged,
  bool supportsOpacity = true,
  String title = 'Colors',
  /// Present on the app's root navigator (default), so it covers the tab bar even from inside a tab's own stack.
  bool useRootNavigator = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final theme = AppleTheme.of(context);
  final regular = IosLayout.isRegular(context);
  Rect? anchor;
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    anchor = box.localToGlobal(Offset.zero, ancestor: navigator.context.findRenderObject()) & box.size;
  }
  return navigator.push(
    _ColorPickerRoute(
      regular: regular,
      anchor: anchor,
      theme: theme,
      builder: (routeContext) => _LiveColor(
        initial: color,
        onChanged: onChanged,
        builder: (ctx, value, set) => IosColorPicker(
          color: value,
          onChanged: set,
          supportsOpacity: supportsOpacity,
          title: title,
          onClose: () => Navigator.of(routeContext).pop(),
        ),
      ),
    ),
  );
}

class _LiveColor extends StatefulWidget {
  const _LiveColor({required this.initial, required this.onChanged, required this.builder});
  final Color initial;
  final ValueChanged<Color> onChanged;
  final Widget Function(BuildContext context, Color value, ValueChanged<Color> set) builder;
  @override
  State<_LiveColor> createState() => _LiveColorState();
}

class _LiveColorState extends State<_LiveColor> {
  late Color _value = widget.initial;
  @override
  Widget build(BuildContext context) => widget.builder(context, _value, (c) {
    setState(() => _value = c);
    widget.onChanged(c);
  });
}

class _ColorPickerRoute extends PopupRoute<void> {
  _ColorPickerRoute({required this.regular, required this.anchor, required this.theme, required this.builder});
  final bool regular;
  final Rect? anchor;
  final AppleThemeData theme;
  final WidgetBuilder builder;

  @override
  Color? get barrierColor => regular ? null : theme.ios.overlay; // kit Overlays/Default on iPhone
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => 'Dismiss';
  @override
  Duration get transitionDuration => const Duration(milliseconds: 350);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final child = AppleTheme(
      data: theme,
      child: Builder(builder: builder),
    );
    if (!regular) {
      return SafeArea(
        top: true,
        bottom: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(padding: const EdgeInsets.all(8), child: child),
        ),
      );
    }
    return CustomSingleChildLayout(delegate: _PopoverLayout(anchor), child: child);
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    if (MediaQuery.disableAnimationsOf(context)) return FadeTransition(opacity: animation, child: child);
    if (!regular) {
      return SlideTransition(
        position: Tween(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      );
    }
    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.9, end: 1).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack)),
        child: child,
      ),
    );
  }
}

class _PopoverLayout extends SingleChildLayoutDelegate {
  _PopoverLayout(this.anchor);
  final Rect? anchor;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();
  @override
  Offset getPositionForChild(Size size, Size child) {
    final a = anchor ?? Rect.fromCenter(center: size.center(Offset.zero), width: 0, height: 0);
    final double left = (a.center.dx - child.width / 2).clamp(12.0, math.max(12.0, size.width - child.width - 12));
    var top = a.bottom + 12;
    if (top + child.height > size.height - 12) top = math.max(12.0, a.top - 12 - child.height);
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_PopoverLayout old) => old.anchor != anchor;
}

/* ------------------------------------------------------------------ color picker */

/// Grid (kit), Spectrum and Sliders.
enum IosColorPickerMode { grid, spectrum, sliders }

/// The iOS color picker (UIColorPickerViewController; kit "Color Picker - iPhone / iPad"): header, Grid / Spectrum /
/// Sliders, opacity, the current colour and saved colours, on a Thick material panel (386 pt sheet on iPhone, 402 pt
/// popover on iPad). Usually opened by [IosColorWell] or [showIosColorPicker].
///
///     IosColorPicker(color: c, onChanged: (v) => setState(() => c = v), onClose: () => Navigator.pop(context))
class IosColorPicker extends StatefulWidget {
  const IosColorPicker({
    super.key,
    required this.color,
    required this.onChanged,
    this.supportsOpacity = true,
    this.title = 'Colors',
    this.onClose,
    this.onEyedropper,
    this.savedColors,
    this.initialMode = IosColorPickerMode.grid,
    this.glass = true,
  });

  final Color color;
  final ValueChanged<Color> onChanged;
  final bool supportsOpacity;
  final String title;

  /// Shows the close (×) button.
  final VoidCallback? onClose;

  /// Shows the eyedropper button (pick a colour from the screen yourself and call [onChanged]).
  final VoidCallback? onEyedropper;

  /// Saved colours under the grid. Default: the kit's (system Green … Brown). "+" adds the current colour.
  final List<Color>? savedColors;

  /// The mode shown first (the user switches with the segmented control).
  final IosColorPickerMode initialMode;

  /// false = no panel (embed the contents in your own sheet).
  final bool glass;

  @override
  State<IosColorPicker> createState() => _IosColorPickerState();
}

class _IosColorPickerState extends State<IosColorPicker> {
  late IosColorPickerMode _mode = widget.initialMode;
  late List<Color>? _saved = widget.savedColors == null ? null : [...widget.savedColors!];
  Offset? _spot;

  void _set(Color c) => widget.onChanged(c.withValues(alpha: widget.supportsOpacity ? c.a : 1));

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final t = IosTypography.of(context);
    final regular = IosLayout.isRegular(context);
    final color = widget.color;
    final opaque = color.withValues(alpha: 1);
    final saved = _saved ?? [c.green, c.yellow, c.orange, c.red, c.purple, c.blue, c.indigo, c.pink, c.brown];

    Widget tool(IconData icon, String label, VoidCallback? onTap, {double size = 25}) => Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 24,
          height: 44,
          child: onTap == null
              ? null
              : OverflowBox(
                  maxWidth: 44,
                  child: Center(
                    child: Icon(icon, size: size, color: c.labelVibrantSecondary),
                  ),
                ),
        ),
      ),
    );

    final header = SizedBox(
      height: 49,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          children: [
            tool(CupertinoIcons.eyedropper, 'Pick a Color from the Screen', widget.onEyedropper),
            Expanded(
              child: Text(
                widget.title,
                textAlign: TextAlign.center,
                style: t.headline.copyWith(color: c.labelVibrantPrimary),
              ),
            ),
            tool(AppleIcons.xmark, 'Close', widget.onClose, size: 23),
          ],
        ),
      ),
    );

    // Small segmented control: 32 tall, padding 2, gap 4; 13 Medium, selected 13 Semibold on a white capsule.
    final modes = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: ShapeDecoration(color: c.fillTertiary, shape: const StadiumBorder()),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Row(
            children: [
              for (final m in IosColorPickerMode.values) ...[
                if (m != IosColorPickerMode.grid) const SizedBox(width: 4),
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: _mode == m,
                    label: switch (m) {
                      IosColorPickerMode.grid => 'Grid',
                      IosColorPickerMode.spectrum => 'Spectrum',
                      IosColorPickerMode.sliders => 'Sliders',
                    },
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _mode = m),
                      child: Container(
                        height: 28,
                        alignment: Alignment.center,
                        decoration: _mode == m
                            ? ShapeDecoration(
                                color: c.segmentedSelectedFill,
                                shape: const StadiumBorder(),
                                shadows: const [BoxShadow(color: Color(0x0F000000), offset: Offset(0, 2), blurRadius: 20)],
                              )
                            : null,
                        child: Text(switch (m) {
                          IosColorPickerMode.grid => 'Grid',
                          IosColorPickerMode.spectrum => 'Spectrum',
                          IosColorPickerMode.sliders => 'Sliders',
                        }, style: t.footnote.copyWith(fontWeight: _mode == m ? FontWeight.w600 : FontWeight.w500)),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    Widget panel;
    switch (_mode) {
      case IosColorPickerMode.grid:
        panel = ClipRSuperellipse(
          borderRadius: BorderRadius.circular(10),
          child: Column(
            children: [
              for (final row in kIosColorPickerPalette)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final swatch in row)
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: _sameRgb(swatch, opaque),
                            label: '#${(swatch.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                            excludeSemantics: true,
                            child: GestureDetector(
                              onTap: () => _set(swatch.withValues(alpha: color.a)),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: swatch,
                                  border: _sameRgb(swatch, opaque) ? Border.all(color: const Color(0xFFFFFFFF), width: 3) : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      case IosColorPickerMode.spectrum:
        final hsl = HSLColor.fromColor(opaque);
        final spot = _spot ?? Offset(hsl.hue / 360, 1 - hsl.lightness);
        panel = LayoutBuilder(
          builder: (context, box) {
            void pick(Offset p) {
              final x = (p.dx / box.maxWidth).clamp(0.0, 1.0);
              final y = (p.dy / box.maxHeight).clamp(0.0, 1.0);
              setState(() => _spot = Offset(x, y));
              _set(HSLColor.fromAHSL(color.a, x * 360, 1, 1 - y).toColor());
            }

            return GestureDetector(
              onPanDown: (d) => pick(d.localPosition),
              onPanUpdate: (d) => pick(d.localPosition),
              child: Semantics(
                label: 'Spectrum',
                child: ClipRSuperellipse(
                  borderRadius: BorderRadius.circular(10),
                  child: CustomPaint(
                    painter: _SpectrumPainter(),
                    child: Stack(
                      children: [
                        Positioned(
                          left: spot.dx * box.maxWidth - 14,
                          top: spot.dy * box.maxHeight - 14,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: opaque,
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFFFFFFF), width: 3),
                              boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 3)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      case IosColorPickerMode.sliders:
        Widget channel(String name, double v, Color lo, Color hi, Color Function(double) make) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(context, name),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _ColorTrack(value: v, thumb: opaque, gradient: [lo, hi], semanticLabel: name, onChanged: (x) => _set(make(x))),
                ),
                const SizedBox(width: 11),
                _ValueBox(text: '${(v * 255).round()}'),
              ],
            ),
          ],
        );
        final r = opaque.r, g = opaque.g, b = opaque.b;
        panel = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            channel('Red', r, opaque.withValues(red: 0), opaque.withValues(red: 1), (x) => color.withValues(red: x)),
            const SizedBox(height: 12),
            channel('Green', g, opaque.withValues(green: 0), opaque.withValues(green: 1), (x) => color.withValues(green: x)),
            const SizedBox(height: 12),
            channel('Blue', b, opaque.withValues(blue: 0), opaque.withValues(blue: 1), (x) => color.withValues(blue: x)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _label(context, 'Hex Color #')),
                _ValueBox(text: (opaque.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase(), width: 100),
              ],
            ),
          ],
        );
    }

    final opacity = widget.supportsOpacity
        ? DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.separatorOpaque)),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 15, bottom: 21),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label(context, 'Opacity'),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: _ColorTrack(
                          value: color.a,
                          thumb: opaque,
                          gradient: [opaque.withValues(alpha: 0), opaque],
                          stops: const [0.12, 0.88],
                          checkerboard: true,
                          semanticLabel: 'Opacity',
                          onChanged: (x) => _set(color.withValues(alpha: (x * 100).round() / 100)),
                        ),
                      ),
                      const SizedBox(width: 11),
                      _ValueBox(text: '${(color.a * 100).round()}%'),
                    ],
                  ),
                ],
              ),
            ),
          )
        : SizedBox(height: 1, child: ColoredBox(color: c.separatorOpaque));

    final footer = Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 75,
            height: 75,
            child: ClipRSuperellipse(
              borderRadius: BorderRadius.circular(10),
              child: CustomPaint(
                painter: _CheckerPainter(),
                child: ColoredBox(color: color),
              ),
            ),
          ),
          const SizedBox(width: 30),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final gap = (box.maxWidth - 5 * 30) / 4;
                final dots = <Widget>[
                  for (final s in saved)
                    _Dot(
                      color: s,
                      selected: _sameRgb(s, opaque),
                      onTap: () => _set(s.withValues(alpha: color.a)),
                    ),
                  Semantics(
                    button: true,
                    label: 'Add Color',
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: () => setState(() => _saved = [...saved, opaque]),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(color: c.fillPrimary, shape: BoxShape.circle),
                        child: Icon(AppleIcons.plus, size: 18, color: c.labelPrimary),
                      ),
                    ),
                  ),
                ];
                return Wrap(spacing: gap, runSpacing: regular ? 22 : 15, children: dots);
              },
            ),
          ),
        ],
      ),
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        modes,
        SizedBox(height: 296, child: panel),
        opacity,
        footer,
      ],
    );
    if (!widget.glass) return content;
    return SizedBox(
      width: regular ? 402 : 386,
      child: AppleGlass(
        style: AppleGlassStyle.panel,
        radius: regular ? IosLayout.dimensionsOf(context).popoverRadius : 32,
        child: Padding(padding: regular ? const EdgeInsets.all(16) : const EdgeInsets.fromLTRB(16, 4, 16, 16), child: content),
      ),
    );
  }
}

Widget _label(BuildContext context, String text) {
  final t = IosTypography.of(context);
  return SizedBox(
    height: 20,
    child: Text(text.toUpperCase(), style: t.footnoteEmphasized.copyWith(height: 20 / 13)),
  );
}

/// The value box (kit "Percentage"): 75 × 34, radius 8, 17 Semibold; white (Dark: Fills/Tertiary).
class _ValueBox extends StatelessWidget {
  const _ValueBox({required this.text, this.width = 75});
  final String text;
  final double width;
  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    return Container(
      width: width,
      height: 34,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: theme.isDark ? theme.ios.fillTertiary : const Color(0xFFFFFFFF),
        shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(text, style: IosTypography.of(context).headline),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          // Kit "Selection Ring": 22 pt, 2 pt white.
          child: selected
              ? Padding(
                  padding: const EdgeInsets.all(3),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFFFFFFF), width: 2),
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

/// A 34 pt capsule track with a 34 pt knob (3 pt white ring, filled with the colour); value 0…1.
class _ColorTrack extends StatelessWidget {
  const _ColorTrack({
    required this.value,
    required this.thumb,
    required this.gradient,
    required this.onChanged,
    required this.semanticLabel,
    this.stops,
    this.checkerboard = false,
  });
  final double value;
  final Color thumb;
  final List<Color> gradient;
  final List<double>? stops;
  final bool checkerboard;
  final ValueChanged<double> onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return Semantics(
      slider: true,
      label: semanticLabel,
      value: '${(v * 100).round()}%',
      increasedValue: '${(math.min(1.0, v + 0.1) * 100).round()}%',
      decreasedValue: '${(math.max(0.0, v - 0.1) * 100).round()}%',
      onIncrease: () => onChanged(math.min(1, v + 0.1)),
      onDecrease: () => onChanged(math.max(0, v - 0.1)),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          void at(double x) => onChanged(((x - 17) / math.max(1, w - 34)).clamp(0.0, 1.0));
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragDown: (d) => at(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => at(d.localPosition.dx),
            child: SizedBox(
              height: 34,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(17),
                      child: CustomPaint(
                        painter: checkerboard ? _CheckerPainter(transparent: true) : null,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: gradient, stops: stops),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: v * (w - 34),
                    top: 0,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: thumb,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFFFFFFF), width: 3),
                        boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 3)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Black checkerboard (kit: 11.6 pt squares) — over the panel ([transparent]) or over white.
class _CheckerPainter extends CustomPainter {
  _CheckerPainter({this.transparent = false});
  final bool transparent;
  @override
  void paint(Canvas canvas, Size size) {
    const s = 11.6;
    if (!transparent) canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
    final black = Paint()..color = const Color(0xFF000000);
    for (var y = 0; y * s < size.height; y++) {
      for (var x = 0; x * s < size.width; x++) {
        if ((x + y).isEven) canvas.drawRect(Rect.fromLTWH(x * s, y * s, s, s), black);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter old) => old.transparent != transparent;
}

class _SpectrumPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xFFFF0000),
            Color(0xFFFFFF00),
            Color(0xFF00FF00),
            Color(0xFF00FFFF),
            Color(0xFF0000FF),
            Color(0xFFFF00FF),
            Color(0xFFFF0000),
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0x00FFFFFF), Color(0x00000000), Color(0xFF000000)],
          stops: [0, 0.5, 0.5, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SpectrumPainter old) => false;
}
