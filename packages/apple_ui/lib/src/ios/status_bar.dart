import 'package:flutter/widgets.dart';

import '../core/adaptive.dart';
import '../core/theme.dart';
import '../core/typography.dart';

/// Which status bar to draw.
enum IosStatusBarDevice {
  /// iPhone 17 Pro: 62 tall, time, Dynamic Island, cellular, Wi-Fi, battery.
  iphone,

  /// iPad: 32 tall, time + date, the iPadOS menu bar (app name, menus), Wi-Fi, battery percentage.
  ipad,

  /// iPhone or iPad from the window size ([IosLayout.isRegular]).
  auto,
}

/// A static status bar FOR MOCKUPS ONLY (device frames, screenshots, prototypes, store images) — kit page
/// "Status Bars and Menu Bars". A real app never draws a status bar: the system does; leave the safe area free.
///
///     IosStatusBar(device: IosStatusBarDevice.iphone)                        // 9:41, Dynamic Island, full levels
///     IosStatusBar(device: IosStatusBarDevice.ipad, menus: ['File', 'Edit', 'View'], selectedMenu: 'Edit')
///     IosStatusBar(device: IosStatusBarDevice.iphone, foreground: Color(0xFFFFFFFF))   // over a dark photo
class IosStatusBar extends StatelessWidget {
  const IosStatusBar({
    super.key,
    this.device = IosStatusBarDevice.auto,
    this.time = '9:41',
    this.date = 'Wed Apr 1',
    this.appName = 'App',
    this.menus = const [],
    this.selectedMenu,
    this.windowControls = false,
    this.battery = 100,
    this.foreground,
  });

  final IosStatusBarDevice device;

  /// "9:41" (Apple's marketing time). iPad adds "AM".
  final String time;

  /// iPad: the date ("Wed Apr 1").
  final String date;

  /// iPad: the app name shown bold in the menu bar.
  final String appName;

  /// iPad: menu titles shown while the menu bar is expanded.
  final List<String> menus;

  /// iPad: the open menu (highlighted capsule).
  final String? selectedMenu;

  /// iPad: red/yellow/green window controls instead of time and date (full-screen app with its menu bar shown).
  final bool windowControls;

  /// iPad: the battery percentage text.
  final int battery;

  /// Content colour. Null = primary label (black in Light, white in Dark). White over dark images.
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final fg = foreground ?? theme.ios.labelPrimary;
    final ipad =
        device == IosStatusBarDevice.ipad ||
        (device == IosStatusBarDevice.auto && IosLayout.isRegular(context));
    final label = ipad
        ? 'Status bar: ${_clock()}, $date, Wi-Fi, battery $battery%'
        : 'Status bar: $time, full signal, Wi-Fi, battery full';
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: ipad ? _ipad(context, fg) : _iphone(fg),
    );
  }

  String _clock() =>
      RegExp(r'AM|PM', caseSensitive: false).hasMatch(time) ? time : '$time AM';

  // Kit "Status bar - iPhone 17 Pro": 402 x 62, padding 9; time Semibold 17 centered left of the island (6 pt
  // in from the island side); island 125 x 37 black; levels (cellular 19.3, Wi-Fi 16.7, battery 27.3; 7 apart).
  Widget _iphone(Color fg) {
    final text = appleFont(size: 17).copyWith(
      fontSize: 17,
      height: 22 / 17,
      letterSpacing: -0.43,
      fontWeight: FontWeight.w600,
      color: fg,
      decoration: TextDecoration.none,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return SizedBox(
      height: 62,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(9, 2.4, 9, 0),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Center(child: Text(time, style: text, maxLines: 1)),
              ),
            ),
            Container(
              width: 125,
              height: 37,
              decoration: const ShapeDecoration(
                color: Color(0xFF000000),
                shape: StadiumBorder(),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 9),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 7,
                  children: [
                    CustomPaint(
                      size: const Size(19.3, 12.3),
                      painter: _CellularPainter(fg),
                    ),
                    CustomPaint(
                      size: const Size(16.7, 12.3),
                      painter: _WifiPainter(fg),
                    ),
                    CustomPaint(
                      size: const Size(27.3, 13),
                      painter: _BatteryPainter(fg),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Kit "Status bar and Menu bar - iPad": 32 tall, padding 16, Medium 14/16; app name Bold; menus 10.5 apart
  // from their capsule edges; trailing Wi-Fi 13.5 x 10, "100%", battery 27.3 x 13, 5 apart.
  Widget _ipad(BuildContext context, Color fg) {
    TextStyle style(FontWeight w) => appleFont(size: 14).copyWith(
      fontSize: 14,
      height: 16 / 14,
      letterSpacing: 0,
      fontWeight: w,
      color: fg,
      decoration: TextDecoration.none,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final medium = style(FontWeight.w500);
    final clock = _clock().split(' ');
    Widget menu(String title, {bool app = false}) {
      final selected = selectedMenu == title;
      return Container(
        padding: EdgeInsets.symmetric(horizontal: app ? 10 : 10.5, vertical: 8),
        decoration: selected
            ? ShapeDecoration(
                color: AppleTheme.of(context).isDark
                    ? const Color(0x0FFFFFFF)
                    : const Color(0x8CFFFFFF),
                shape: const StadiumBorder(),
                shadows: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    offset: Offset(0, 2),
                    blurRadius: 16,
                  ),
                ],
              )
            : null,
        child: Text(
          title,
          style: app ? style(FontWeight.w700) : medium,
          maxLines: 1,
        ),
      );
    }

    return SizedBox(
      height: 32,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            if (windowControls)
              const SizedBox(
                width: 132,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  spacing: 12,
                  children: [
                    _WindowControl(Color(0xFFFF0B18), _WindowGlyph.close),
                    _WindowControl(Color(0xFFFFC700), _WindowGlyph.minimize),
                    _WindowControl(Color(0xFF00C847), _WindowGlyph.fullscreen),
                  ],
                ),
              )
            else ...[
              Text(clock.first, style: medium),
              if (clock.length > 1) ...[
                const SizedBox(width: 2),
                Text(clock.sublist(1).join(' '), style: medium),
              ],
              const SizedBox(width: 8),
              Text(date, style: medium),
            ],
            Expanded(
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        menu(appName, app: true),
                        for (final m in menus) menu(m),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Row(
              spacing: 5,
              children: [
                CustomPaint(
                  size: const Size(13.5, 10),
                  painter: _WifiPainter(fg),
                ),
                // Natural width: Inter (off Apple platforms) is wider than SF Pro and a fixed box would clip the "%".
                Text('$battery%', style: medium, maxLines: 1, softWrap: false),
                CustomPaint(
                  size: const Size(27.3, 13),
                  painter: _BatteryPainter(fg),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Glyphs (original drawings) ------------------------------------------------------------------------------

/// Four rounded bars, rising (viewBox 19.3 x 12.3).
class _CellularPainter extends CustomPainter {
  _CellularPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 19.3;
    final p = Paint()..color = color;
    const heights = [4.4, 6.9, 9.5, 12.3];
    for (var i = 0; i < 4; i++) {
      final h = heights[i] * k;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * 5.367 * k, size.height - h, 3.2 * k, h),
          Radius.circular(1.6 * k),
        ),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_CellularPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Two arcs with round ends and a small fan at the bottom (viewBox 16.7 x 12.3).
class _WifiPainter extends CustomPainter {
  _WifiPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 16.7;
    final center = Offset(8.35 * k, 12.75 * k);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.3 * k
      ..strokeCap = StrokeCap.round;
    const half = 40 * 3.141592653589793 / 180;
    for (final r in [11.0, 6.6]) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r * k),
        -3.141592653589793 / 2 - half,
        2 * half,
        false,
        stroke,
      );
    }
    final fan = Path()
      ..moveTo(8.35 * k, 12.3 * k)
      ..lineTo(5.75 * k, 9.7 * k)
      ..arcToPoint(Offset(10.95 * k, 9.7 * k), radius: Radius.circular(3.6 * k))
      ..close();
    canvas.drawPath(
      fan,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      fan,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6 * k
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_WifiPainter oldDelegate) => oldDelegate.color != color;
}

/// A full battery: rounded body and a small cap (viewBox 27.3 x 13).
class _BatteryPainter extends CustomPainter {
  _BatteryPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 27.3;
    final p = Paint()..color = color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, 24.7 * k, 13 * k),
        Radius.circular(4.3 * k),
      ),
      p,
    );
    final cap = Path()
      ..moveTo(25.7 * k, 4.4 * k)
      ..arcToPoint(
        Offset(25.7 * k, 8.6 * k),
        radius: Radius.elliptical(1.6 * k, 2.1 * k),
      )
      ..close();
    canvas.drawPath(cap, p);
  }

  @override
  bool shouldRepaint(_BatteryPainter oldDelegate) => oldDelegate.color != color;
}

enum _WindowGlyph { close, minimize, fullscreen }

/// A 16 pt window control circle with its glyph in black 55%.
class _WindowControl extends StatelessWidget {
  const _WindowControl(this.color, this.glyph);
  final Color color;
  final _WindowGlyph glyph;
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(16, 16),
    painter: _WindowControlPainter(color, glyph),
  );
}

class _WindowControlPainter extends CustomPainter {
  _WindowControlPainter(this.color, this.glyph);
  final Color color;
  final _WindowGlyph glyph;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(const Offset(8, 8), 8, Paint()..color = color);
    final ink = Paint()..color = const Color(0x8C000000);
    final line = Paint()
      ..color = const Color(0x8C000000)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    switch (glyph) {
      case _WindowGlyph.close:
        canvas.drawLine(const Offset(5.4, 5.4), const Offset(10.6, 10.6), line);
        canvas.drawLine(const Offset(10.6, 5.4), const Offset(5.4, 10.6), line);
      case _WindowGlyph.minimize:
        canvas.drawLine(const Offset(5.2, 8), const Offset(10.8, 8), line);
      case _WindowGlyph.fullscreen:
        canvas.drawPath(
          Path()
            ..moveTo(3.5, 3.5)
            ..lineTo(8.7, 3.5)
            ..lineTo(3.5, 8.7)
            ..close(),
          ink,
        );
        canvas.drawPath(
          Path()
            ..moveTo(12.5, 12.5)
            ..lineTo(7.3, 12.5)
            ..lineTo(12.5, 7.3)
            ..close(),
          ink,
        );
    }
  }

  @override
  bool shouldRepaint(_WindowControlPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.glyph != glyph;
}
