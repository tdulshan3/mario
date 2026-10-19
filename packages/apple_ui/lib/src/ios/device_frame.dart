import 'package:flutter/widgets.dart';

import '../core/adaptive.dart';
import '../core/ios_tokens.dart';
import '../core/theme.dart';

/// Device models of the kit page "Product Bezels".
enum IosDeviceModel {
  /// 402 × 874 pt screen.
  iPhone17,

  /// 402 × 874.
  iPhone17Pro,

  /// 440 × 956.
  iPhone17ProMax,

  /// 420 × 912.
  iPhoneAir,

  /// 402 × 874 (narrower Dynamic Island).
  iPhone18Pro,

  /// 440 × 956 (narrower Dynamic Island).
  iPhone18ProMax,

  /// Foldable, inner display open: 669 × 951.
  iPhoneDuo,

  /// Foldable, outer display (closed): 466 × 678, hinge on the left.
  iPhoneDuoOuter,

  /// 1210 × 834 (landscape).
  iPadPro11,

  /// 1376 × 1032 (landscape).
  iPadPro13,

  /// 1133 × 744 (landscape).
  iPadMini,
}

/// Finishes (kit "Color"). Use the ones the kit has for the model; any works.
enum IosDeviceFinish {
  silver, cosmicOrange, deepBlue, black, lavender, mistBlue, sage, white, skyBlue, cloudWhite, spaceBlack, lightGold,
  burgundy, glacier, nightSky, starWhite, spaceGray, starlight,
}

/// A device frame for mockups and screenshots (kit page "Product Bezels"), painted (no images): metal band, black
/// border, rounded display, Dynamic Island or camera, side buttons, home indicator.
/// The [child] gets the device's screen as its MediaQuery (size and safe area insets), so iPhone/iPad layouts and
/// [IosLayout] behave as on that device.
///
///     IosDeviceFrame(model: IosDeviceModel.iPhone17Pro, finish: IosDeviceFinish.deepBlue, child: MyHomeScreen())
///     IosDeviceFrame(model: IosDeviceModel.iPadPro11, orientation: Orientation.portrait, child: ...)
/// Scale it with FittedBox / Transform.scale, never by changing the screen size.
class IosDeviceFrame extends StatelessWidget {
  const IosDeviceFrame({
    super.key,
    this.model = IosDeviceModel.iPhone17Pro,
    this.finish,
    this.orientation,
    this.homeIndicator = true,
    this.screenColor,
    required this.child,
  });

  final IosDeviceModel model;

  /// Null = the model's default finish.
  final IosDeviceFinish? finish;

  /// Null = the kit's orientation (iPhones portrait, iPads landscape).
  final Orientation? orientation;

  /// Draw the home indicator at the bottom of the screen.
  final bool homeIndicator;

  /// Screen background behind [child]. Null = Backgrounds/Primary.
  final Color? screenColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final spec = _DeviceSpec.of(model);
    final ipad = spec.ipad;
    final natural = ipad ? Orientation.landscape : Orientation.portrait;
    final turned = orientation != null && orientation != natural;
    final screen = turned ? Size(spec.h, spec.w) : Size(spec.w, spec.h);
    final m = _metal(finish ?? spec.finish, ipad: ipad);

    // Body padding (the outer display of the Duo is wider on the hinge side).
    var pad = EdgeInsets.all(spec.bezel);
    if (model == IosDeviceModel.iPhoneDuoOuter) {
      pad = turned ? const EdgeInsets.fromLTRB(18.67, 16, 16, 25.67) : const EdgeInsets.fromLTRB(25.67, 18.67, 16, 16);
    }
    final landscapeScreen = screen.width > screen.height;

    // Safe areas of the screen.
    EdgeInsets safe;
    if (ipad) {
      safe = const EdgeInsets.only(top: 32, bottom: 21);
    } else if (model == IosDeviceModel.iPhoneDuo || model == IosDeviceModel.iPhoneDuoOuter) {
      safe = const EdgeInsets.only(top: 24, bottom: 20);
    } else {
      safe = turned ? const EdgeInsets.fromLTRB(62, 0, 62, 21) : const EdgeInsets.only(top: 62, bottom: 34);
    }

    final radii = _screenRadii(spec, model, turned);
    final screenWidget = MediaQuery(
      data: MediaQuery.of(context).copyWith(size: screen, padding: safe, viewPadding: safe, viewInsets: EdgeInsets.zero),
      child: ClipRRect(
        borderRadius: radii,
        child: SizedBox.fromSize(
          size: screen,
          child: ColoredBox(
            color: screenColor ?? AppleTheme.of(context).ios.bgPrimary,
            child: Stack(fit: StackFit.expand, children: [
              child,
              if (spec.islandW > 0) _island(spec, screen, turned),
              if (homeIndicator)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IosHomeIndicator(landscape: landscapeScreen, ipad: ipad),
                ),
            ]),
          ),
        ),
      ),
    );

    final bodySize = Size(screen.width + pad.horizontal, screen.height + pad.vertical);
    return SizedBox.fromSize(
      size: bodySize,
      child: CustomPaint(
        painter: _BezelPainter(spec: spec, metal: m, pad: pad, screen: screen, radii: radii, turned: turned, model: model),
        child: Padding(padding: pad, child: screenWidget),
      ),
    );
  }

  static BorderRadius _screenRadii(_DeviceSpec spec, IosDeviceModel model, bool turned) {
    if (model == IosDeviceModel.iPhoneDuoOuter) {
      final r = Radius.circular(spec.radius);
      const s = Radius.circular(7);
      return turned
          ? BorderRadius.only(topLeft: r, topRight: r, bottomLeft: s, bottomRight: s)
          : BorderRadius.only(topLeft: s, bottomLeft: s, topRight: r, bottomRight: r);
    }
    return BorderRadius.circular(spec.radius);
  }

  Widget _island(_DeviceSpec spec, Size screen, bool turned) {
    final w = turned ? spec.islandH : spec.islandW;
    final h = turned ? spec.islandW : spec.islandH;
    double left;
    double top;
    if (model == IosDeviceModel.iPhoneDuoOuter) {
      left = turned ? 29.67 : screen.width - 29.67 - w;
      top = 29.67;
    } else if (turned) {
      left = spec.islandTop;
      top = (screen.height - h) / 2;
    } else {
      left = (screen.width - w) / 2;
      top = spec.islandTop;
    }
    return Positioned(
      left: left,
      top: top,
      width: w,
      height: h,
      child: CustomPaint(painter: _IslandPainter(lensAtEnd: !turned)),
    );
  }
}

/// The home indicator bar (kit "System / Home Indicator"): 144 × 5 (iPhone) / 273 × 5.5 (iPad), 226 / 315 in
/// landscape, 8 from the bottom of a 34 (iPhone portrait) or 21 tall strip. Colour = Labels/Primary.
///
///     Positioned(left: 0, right: 0, bottom: 0, child: IosHomeIndicator())
class IosHomeIndicator extends StatelessWidget {
  const IosHomeIndicator({super.key, this.landscape = false, this.ipad, this.color});

  /// The wider landscape bar.
  final bool landscape;

  /// iPad metrics. Null = from the screen size ([IosLayout.isRegular]).
  final bool? ipad;

  /// Null = Labels/Primary (black in Light Mode, white in Dark Mode).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final pad = ipad ?? IosLayout.isRegular(context);
    final d = pad ? IosDimensions.ipad : IosDimensions.iphone;
    final width = landscape ? d.homeIndicatorLandscapeWidth : d.homeIndicatorWidth;
    final stripHeight = !pad && !landscape ? 34.0 : 21.0;
    final bottom = pad && !landscape ? 7.75 : 8.0;
    return ExcludeSemantics(
      child: SizedBox(
        height: stripHeight,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: Container(
              width: width,
              height: d.homeIndicatorHeight,
              decoration: BoxDecoration(
                color: color ?? AppleTheme.of(context).ios.labelPrimary,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Geometry measured on the kit's bezel images (pt). Buttons: (edge, start, length) in the kit orientation, measured
// from the body's top-left corner; edge 0 = left, 1 = right, 2 = top.

class _DeviceSpec {
  const _DeviceSpec({
    required this.w,
    required this.h,
    required this.radius,
    required this.bezel,
    required this.band,
    required this.finish,
    this.shine = 1.25,
    this.islandW = 125,
    this.islandH = 37,
    this.islandTop = 13.67,
    this.buttons = const [],
    this.ipad = false,
  });
  final double w;
  final double h;
  final double radius;
  final double bezel;
  final double band;
  final double shine;
  final double islandW;
  final double islandH;
  final double islandTop;
  final List<(int, double, double)> buttons;
  final IosDeviceFinish finish;
  final bool ipad;

  static const _pro = [(0, 186.0, 41.67), (0, 258.33, 67.67), (0, 344.0, 67.67), (1, 281.67, 107.0)];
  static const _base = [(0, 185.0, 41.67), (0, 257.33, 67.67), (0, 343.0, 67.67), (1, 280.67, 106.67)];
  static const _max = [(0, 186.33, 41.67), (0, 258.67, 67.67), (0, 344.33, 67.67), (1, 282.0, 106.67)];
  static const _ipadButtons = [(0, 73.5, 62.0), (2, 100.5, 52.5), (2, 163.5, 52.0)];

  static _DeviceSpec of(IosDeviceModel m) => switch (m) {
        IosDeviceModel.iPhone17 => const _DeviceSpec(w: 402, h: 874, radius: 63, bezel: 15, band: 5.67, finish: IosDeviceFinish.black, buttons: _base),
        IosDeviceModel.iPhone17Pro => const _DeviceSpec(w: 402, h: 874, radius: 63, bezel: 15.67, band: 6.33, finish: IosDeviceFinish.silver, buttons: _pro),
        IosDeviceModel.iPhone18Pro =>
          const _DeviceSpec(w: 402, h: 874, radius: 63, bezel: 15.67, band: 6.33, finish: IosDeviceFinish.silver, islandW: 94, buttons: _pro),
        IosDeviceModel.iPhone17ProMax => const _DeviceSpec(w: 440, h: 956, radius: 64, bezel: 15.33, band: 6.33, finish: IosDeviceFinish.silver, buttons: _max),
        IosDeviceModel.iPhone18ProMax =>
          const _DeviceSpec(w: 440, h: 956, radius: 64, bezel: 15.33, band: 6.33, finish: IosDeviceFinish.silver, islandW: 94, buttons: _max),
        IosDeviceModel.iPhoneAir => const _DeviceSpec(
            w: 420, h: 912, radius: 63, bezel: 15.33, band: 6, shine: 2.75, islandTop: 20.33, finish: IosDeviceFinish.spaceBlack, buttons: _base),
        IosDeviceModel.iPhoneDuo => const _DeviceSpec(
            w: 669, h: 951, radius: 55, bezel: 20.67, band: 4, islandW: 0, islandH: 0, finish: IosDeviceFinish.nightSky, buttons: [(1, 198, 112.67)]),
        IosDeviceModel.iPhoneDuoOuter => const _DeviceSpec(
            w: 466, h: 678, radius: 60, bezel: 16, band: 4, islandW: 36, islandH: 36, islandTop: 29.67, finish: IosDeviceFinish.nightSky,
            buttons: [(1, 205, 112.67)]),
        IosDeviceModel.iPadPro11 => const _DeviceSpec(
            w: 1210, h: 834, radius: 30, bezel: 45.5, band: 6, islandW: 0, islandH: 0, finish: IosDeviceFinish.spaceGray, buttons: _ipadButtons, ipad: true),
        IosDeviceModel.iPadPro13 => const _DeviceSpec(
            w: 1376, h: 1032, radius: 29, bezel: 45, band: 6.5, islandW: 0, islandH: 0, finish: IosDeviceFinish.spaceGray, buttons: _ipadButtons, ipad: true),
        IosDeviceModel.iPadMini => const _DeviceSpec(
            w: 1133, h: 744, radius: 21.5, bezel: 59.5, band: 8, islandW: 0, islandH: 0, finish: IosDeviceFinish.starlight,
            buttons: [(0, 82, 109), (0, 640, 63.5), (0, 717, 64)], ipad: true),
      };
}

/// Edge, band, highlight near the outside, highlight next to the black border (sampled from the kit's bezels).
typedef _Metal = ({Color edge, Color band, Color outer, Color inner});

_Metal _metal(IosDeviceFinish f, {required bool ipad}) {
  _Metal m(int e, int b, int o, int i) => (edge: Color(e), band: Color(b), outer: Color(o), inner: Color(i));
  if (ipad && f == IosDeviceFinish.silver) return m(0xFFAEAFB0, 0xFF9E9FA0, 0xFFDBDCDD, 0xFF8E8F90);
  return switch (f) {
    IosDeviceFinish.silver => m(0xFF6D6D6B, 0xFFC1C1C1, 0xFFC1C1C1, 0xFFECECEB),
    IosDeviceFinish.cosmicOrange => m(0xFFB4421B, 0xFFF6A16C, 0xFFF6A16C, 0xFFFEE4D0),
    IosDeviceFinish.deepBlue => m(0xFF1F2534, 0xFF5A6175, 0xFF5A6175, 0xFFB5BBD3),
    IosDeviceFinish.black => m(0xFF313233, 0xFF646667, 0xFF646667, 0xFFB2B3B3),
    IosDeviceFinish.lavender => m(0xFF8C8298, 0xFFBEB5C9, 0xFFBEB5C9, 0xFFF3F0F6),
    IosDeviceFinish.mistBlue => m(0xFF56647A, 0xFF9CACC6, 0xFF9CACC6, 0xFFD6DFED),
    IosDeviceFinish.sage => m(0xFF4E593F, 0xFF899873, 0xFF899873, 0xFFDBE5CE),
    IosDeviceFinish.white => m(0xFF878685, 0xFFBFBFBE, 0xFFBFBFBE, 0xFFEFEFEF),
    IosDeviceFinish.skyBlue => m(0xFF707E88, 0xFF303F49, 0xFF303F49, 0xFFEAF6FF),
    IosDeviceFinish.cloudWhite => m(0xFF858483, 0xFF3D3C3C, 0xFF3D3C3C, 0xFFFBFBFB),
    IosDeviceFinish.spaceBlack => m(0xFF696969, 0xFF0C0C0F, 0xFF0C0C0F, 0xFFD2D2D3),
    IosDeviceFinish.lightGold => m(0xFF877A5E, 0xFF423C2A, 0xFF423C2A, 0xFFF5F3ED),
    IosDeviceFinish.burgundy => m(0xFF361E22, 0xFF513137, 0xFF513137, 0xFFC6909A),
    IosDeviceFinish.glacier => m(0xFF748093, 0xFFAEBBCE, 0xFFAEBBCE, 0xFFE9EEF6),
    IosDeviceFinish.nightSky => m(0xFF262F3E, 0xFF617290, 0xFF617290, 0xFF9FB7E3),
    IosDeviceFinish.starWhite => m(0xFF75736E, 0xFFD5D3CE, 0xFFD5D3CE, 0xFFFBF9F6),
    IosDeviceFinish.spaceGray => m(0xFF4A484E, 0xFF433F42, 0xFF7C797F, 0xFF3F3C40),
    IosDeviceFinish.starlight => m(0xFFADA597, 0xFFCEC6BA, 0xFFF9F6F1, 0xFFA9A296),
  };
}

class _BezelPainter extends CustomPainter {
  _BezelPainter({
    required this.spec,
    required this.metal,
    required this.pad,
    required this.screen,
    required this.radii,
    required this.turned,
    required this.model,
  });
  final _DeviceSpec spec;
  final _Metal metal;
  final EdgeInsets pad;
  final Size screen;
  final BorderRadius radii;
  final bool turned;
  final IosDeviceModel model;

  RRect _ring(Rect screenRect, double grow) => radii
      .copyWith(
        topLeft: Radius.circular(radii.topLeft.x + grow),
        topRight: Radius.circular(radii.topRight.x + grow),
        bottomLeft: Radius.circular(radii.bottomLeft.x + grow),
        bottomRight: Radius.circular(radii.bottomRight.x + grow),
      )
      .toRRect(screenRect.inflate(grow));

  @override
  void paint(Canvas canvas, Size size) {
    final screenRect = Offset(pad.left, pad.top) & screen;
    final black = spec.bezel - spec.band;

    // Side buttons (3 pt proud of the body), drawn in the kit orientation and turned with the device.
    final body = Offset.zero & size;
    canvas.save();
    if (turned) {
      canvas.translate(size.width / 2, size.height / 2);
      canvas.rotate(spec.ipad ? 1.5707963267948966 : -1.5707963267948966);
      canvas.translate(-size.height / 2, -size.width / 2);
    }
    final natural = turned ? Size(size.height, size.width) : size;
    final buttonPaint = Paint()..color = spec.ipad ? metal.outer : metal.band;
    for (final (edge, start, length) in spec.buttons) {
      final r = switch (edge) {
        0 => Rect.fromLTWH(-3, start, 3, length),
        1 => Rect.fromLTWH(natural.width, start, 3, length),
        _ => Rect.fromLTWH(start, -3, length, 3),
      };
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(1.5)), buttonPaint);
    }
    canvas.restore();

    // Everything below is drawn around the display, never under it (a transparent screen stays transparent).
    canvas.save();
    canvas.clipPath(Path.combine(
      PathOperation.difference,
      Path()..addRect(body.inflate(4)),
      Path()..addRRect(radii.toRRect(screenRect)),
    ));
    // Hinge-side metal of the Duo's outer display (the rings below cover a uniform 16).
    if (model == IosDeviceModel.iPhoneDuoOuter) {
      const small = Radius.circular(23);
      const big = Radius.circular(76);
      final r = turned
          ? const BorderRadius.only(topLeft: big, topRight: big, bottomLeft: small, bottomRight: small)
          : const BorderRadius.only(topLeft: small, bottomLeft: small, topRight: big, bottomRight: big);
      canvas.drawRRect(r.toRRect(body), Paint()..color = metal.band);
    }
    // Rings, outside in: edge, outer highlight, band, inner highlight, black border.
    canvas.drawRRect(_ring(screenRect, spec.bezel), Paint()..color = metal.edge);
    canvas.drawRRect(
      _ring(screenRect, spec.bezel - 0.75),
      Paint()
        ..color = metal.outer
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5),
    );
    canvas.drawRRect(_ring(screenRect, spec.bezel - 2.25), Paint()..color = metal.band);
    canvas.drawRRect(
      _ring(screenRect, black + spec.shine),
      Paint()
        ..color = metal.inner
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.375),
    );
    canvas.drawRRect(_ring(screenRect, black), Paint()..color = const Color(0xFF000000));
    canvas.restore();

    // iPad front camera, centred in the top border (landscape) or the right border (portrait).
    if (spec.ipad) {
      final c = turned ? Offset(size.width - pad.right / 2, size.height / 2) : Offset(size.width / 2, pad.top / 2);
      canvas.drawCircle(c, 3.5, Paint()..color = const Color(0xFF101114));
      canvas.drawCircle(c, 1.5, Paint()..color = const Color(0xFF1E2A55));
    }
  }

  @override
  bool shouldRepaint(_BezelPainter old) =>
      old.metal != metal || old.screen != screen || old.turned != turned || old.model != model || old.pad != pad;
}

/// Dynamic Island (or camera hole): a black capsule with the camera lens at its end.
class _IslandPainter extends CustomPainter {
  _IslandPainter({required this.lensAtEnd});
  final bool lensAtEnd;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(size.shortestSide / 2)), Paint()..color = const Color(0xFF000000));
    final r = size.shortestSide / 2;
    final c = lensAtEnd ? Offset(size.width - r, size.height / 2) : Offset(size.width / 2, size.height - r);
    canvas.drawCircle(
      c,
      6,
      Paint()
        ..shader = const RadialGradient(colors: [Color(0xFF1B2140), Color(0xFF0B0D1A), Color(0xFF050507)], stops: [0, 0.45, 1])
            .createShader(Rect.fromCircle(center: c, radius: 6)),
    );
  }

  @override
  bool shouldRepaint(_IslandPainter old) => old.lensAtEnd != lensAtEnd;
}
