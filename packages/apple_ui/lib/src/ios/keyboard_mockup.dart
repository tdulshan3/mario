import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

import '../core/glass.dart';
import '../core/theme.dart';
import '../core/typography.dart';
import '_presentation_support.dart' show presentationMaterialFilter;

/// Which system keyboard to picture (kit page "Keyboards", Type). In a real app the system draws the keyboard;
/// choose it with `TextField(keyboardType:, textInputAction:)` (see keyboards.md).
enum IosKeyboardMockupType { lowercase, uppercase, numeric, punctuation, email, url, web, numberPad }

/// The return key: default ↵ (white key), or a blue action key (Go, Search, Send, Done).
enum IosKeyboardMockupReturnKey { standard, go, search, send, done }

/// A STATIC picture of the iOS / iPadOS keyboard (kit page "Keyboards") for mockups, onboarding and screenshots.
/// It is not an input method and is excluded from semantics.
///
///     const IosKeyboardMockup()                                            // iPhone, lowercase, 402 × 332
///     const IosKeyboardMockup(type: IosKeyboardMockupType.email)
///     const IosKeyboardMockup(type: IosKeyboardMockupType.numberPad)       // 402 × 308
///     const IosKeyboardMockup(ipad: true)                                  // 1210 × 428
/// Width: iPhone keyboards fill their width (402 on iPhone 17 / 17 Pro); the iPad keyboard is 1210 wide.
class IosKeyboardMockup extends StatelessWidget {
  const IosKeyboardMockup({
    super.key,
    this.type = IosKeyboardMockupType.lowercase,
    this.ipad = false,
    this.suggestions = const ['“Design”', 'Designs', 'Designed'],
    this.autofill = 'Smith.Trev@icloud.com',
    this.returnKey,
  });

  final IosKeyboardMockupType type;

  /// The iPad keyboard (lowercase or uppercase only).
  final bool ipad;

  /// QuickType suggestions (up to 3). Empty = no suggestion bar.
  final List<String> suggestions;

  /// Email keyboard: the AutoFill suggestion.
  final String autofill;

  /// Return key look. Null = go for [IosKeyboardMockupType.web], standard otherwise.
  final IosKeyboardMockupReturnKey? returnKey;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final s = _KbStyle(theme);
    final content = ipad ? _ipad(context, s) : (type == IosKeyboardMockupType.numberPad ? _numberPad(s) : _iphone(context, s));
    final radius = ipad
        ? BorderRadius.circular(27)
        : const BorderRadius.vertical(top: Radius.circular(27), bottom: Radius.circular(62));
    return ExcludeSemantics(
      child: ClipRSuperellipse(
        borderRadius: radius,
        // The classic keyboard material: the content behind blurred and saturated like the other materials
        // (blur 50, saturation 1.8), under the keyboard fill. No inner glow, no rim.
        child: BackdropFilter(
          filter: presentationMaterialFilter(
            GlassRecipe.of(
              AppleGlassStyle.regular,
              dark: theme.isDark,
              accent: theme.accentColor,
              quaternaryFill: theme.ios.fillQuaternary,
            ),
          ),
          child: ColoredBox(color: s.background, child: content),
        ),
      ),
    );
  }

  // ---- iPhone ----
  Widget _iphone(BuildContext context, _KbStyle s) {
    final upper = type == IosKeyboardMockupType.uppercase;
    final symbols = type == IosKeyboardMockupType.numeric || type == IosKeyboardMockupType.punctuation;
    final charSize = upper || symbols ? 23.0 : 25.0;
    final lift = upper || symbols ? 2.0 : 3.0;
    Widget ch(String c) => _Key(s: s, lift: lift, child: _txt(c, charSize, s.glyph));
    List<Widget> chars(Iterable<String> cs) => [for (final c in cs) Expanded(child: ch(upper ? c.toUpperCase() : c))];
    Widget label(String t, double size, {double lift = 2}) => _Key(s: s, lift: lift, child: _txt(t, size, s.glyph));
    Widget icon(IconData i, double size, {Color? color}) => Icon(i, size: size * 1.1, color: color ?? s.glyph);
    Widget punct(String c) => _Key(s: s, lift: 6, child: _txt(c, 27, s.glyph));
    final del = SizedBox(width: symbols ? 46 : 45, child: _Key(s: s, child: icon(CupertinoIcons.delete_left, 20)));
    final ret = returnKey ?? (type == IosKeyboardMockupType.web ? IosKeyboardMockupReturnKey.go : IosKeyboardMockupReturnKey.standard);
    final retIcon = switch (ret) {
      IosKeyboardMockupReturnKey.standard => CupertinoIcons.return_icon,
      IosKeyboardMockupReturnKey.go => CupertinoIcons.arrow_right,
      IosKeyboardMockupReturnKey.search => CupertinoIcons.search,
      IosKeyboardMockupReturnKey.send => CupertinoIcons.arrow_up,
      IosKeyboardMockupReturnKey.done => CupertinoIcons.checkmark,
    };
    final prominent = ret != IosKeyboardMockupReturnKey.standard;
    final returnKeyWidget = SizedBox(
      width: type == IosKeyboardMockupType.web ? 63 : 93,
      child: _Key(s: s, fill: prominent ? s.accent : null, child: icon(retIcon, 19, color: prominent ? const Color(0xFFFFFFFF) : null)),
    );
    final space = Expanded(child: _Key(s: s, child: const SizedBox()));
    final sw = SizedBox(width: 92.67, child: label(symbols ? 'ABC' : '123', 18));

    List<Widget> rows;
    if (symbols) {
      final numeric = type == IosKeyboardMockupType.numeric;
      rows = [
        _row(chars((numeric ? '1234567890' : '[]{}#%^*+=').split(''))),
        _row(chars(numeric ? ['-', '/', ':', ';', '(', ')', r'$', '&', '@', '”'] : ['_', r'\', '|', '~', '<', '>', '€', '£', '¥', '•'])),
        _row([
          SizedBox(width: 46, child: label(numeric ? '#+=' : '123', 15)),
          const SizedBox(width: 13.67),
          Expanded(child: Row(spacing: 6, children: chars(['.', ',', '?', '!', '’']))),
          const SizedBox(width: 13.67),
          del,
        ], gap: 0),
        _row([sw, space, returnKeyWidget]),
      ];
    } else {
      List<Widget> r4;
      switch (type) {
        case IosKeyboardMockupType.email:
          r4 = [sw, space, SizedBox(width: 42, child: ch('@')), SizedBox(width: 42, child: punct('.')), returnKeyWidget];
        case IosKeyboardMockupType.url:
          r4 = [sw, Expanded(child: punct('.')), Expanded(child: punct('/')), Expanded(child: label('.com', 18)), returnKeyWidget];
        case IosKeyboardMockupType.web:
          r4 = [sw, space, SizedBox(width: 33.33, child: punct('.')), returnKeyWidget];
        default:
          r4 = [sw, space, returnKeyWidget];
      }
      rows = [
        _row(chars('qwertyuiop'.split(''))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _row(chars('asdfghjkl'.split('')))),
        _row([
          SizedBox(width: 45, child: _Key(s: s, child: icon(upper ? CupertinoIcons.shift_fill : CupertinoIcons.shift, 22))),
          const SizedBox(width: 13.33),
          Expanded(child: Row(spacing: 6, children: chars('zxcvbnm'.split('')))),
          const SizedBox(width: 13.33),
          del,
        ], gap: 0),
        _row(r4),
      ];
    }

    final noBar = type == IosKeyboardMockupType.url || type == IosKeyboardMockupType.web ||
        (type != IosKeyboardMockupType.email && suggestions.isEmpty);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (noBar) const SizedBox(height: 24) else SizedBox(height: 49, child: _bar(context, s)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6.67),
          child: Column(mainAxisSize: MainAxisSize.min, spacing: 11, children: rows),
        ),
        SizedBox(
          height: 78,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Icon(CupertinoIcons.smiley, size: 28, color: s.glyph), Icon(CupertinoIcons.mic, size: 27, color: s.glyph)],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bar(BuildContext context, _KbStyle s) {
    if (type == IosKeyboardMockupType.email) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: Row(children: [
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              _txt('password for this website — Passwords', 14, s.suggestion, height: 17.5),
              _txt(autofill, 16, s.suggestion, height: 17.5),
            ]),
          ),
          Container(width: 1, height: 24, margin: const EdgeInsets.only(left: 12, right: 12), color: s.separatorStrong),
          SizedBox(width: 29, height: 23, child: CustomPaint(painter: _KeyGlyphPainter(s.suggestion.withValues(alpha: 0.65)))),
        ]),
      );
    }
    final items = suggestions.take(3).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8.5, 0, 8.5, 4),
      child: Row(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) Container(width: 1, height: 25, margin: const EdgeInsets.symmetric(horizontal: 5), color: s.separator),
          Expanded(child: _txt(items[i], 18, s.suggestion, height: 25, overflow: true)),
        ],
      ]),
    );
  }

  Widget _numberPad(_KbStyle s) {
    const digits = [['1', ''], ['2', 'ABC'], ['3', 'DEF'], ['4', 'GHI'], ['5', 'JKL'], ['6', 'MNO'], ['7', 'PQRS'], ['8', 'TUV'], ['9', 'WXYZ']];
    Widget cell(String d, String l) => _Key(
          s: s,
          lift: 0,
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _txt(d, 23, s.glyph, height: 28),
              Transform.translate(
                offset: const Offset(0, -2),
                child: _txt(l, 13, s.glyph, height: 15, weight: FontWeight.w500, spacing: 2),
              ),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(7.67, 24, 7.67, 74),
      child: Column(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
        for (var r = 0; r < 3; r++)
          SizedBox(height: 48, child: Row(spacing: 6, children: [for (var i = 0; i < 3; i++) Expanded(child: cell(digits[r * 3 + i][0], digits[r * 3 + i][1]))])),
        SizedBox(
          height: 48,
          child: Row(spacing: 6, children: [
            const Expanded(child: SizedBox()),
            Expanded(child: _Key(s: s, lift: 0, alignment: Alignment.topCenter, child: Padding(padding: const EdgeInsets.only(top: 9), child: _txt('0', 23, s.glyph, height: 28)))),
            Expanded(child: Center(child: Icon(CupertinoIcons.delete_left, size: 25, color: s.glyph))),
          ]),
        ),
      ]),
    );
  }

  // ---- iPad (1210 × 428) ----
  Widget _ipad(BuildContext context, _KbStyle s) {
    final shift = type == IosKeyboardMockupType.uppercase;
    Widget two(String alt, String c) => _Key(
          s: s,
          radius: 13,
          lift: 0,
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 6.5),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _txt(alt, 18, s.secondary, height: 21),
              _txt(shift ? c.toUpperCase() : c, 33, s.glyph, height: 39),
            ]),
          ),
        );
    Widget punct(String top, String bottom) => _Key(
          s: s,
          radius: 13,
          lift: 0,
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 4.5),
            child: Column(mainAxisSize: MainAxisSize.min, children: [_txt(top, 29, s.glyph, height: 36), _txt(bottom, 29, s.glyph, height: 14)]),
          ),
        );
    Widget cmd(double w, Widget label, {bool end = false}) => SizedBox(
          width: w,
          child: _Key(
            s: s,
            radius: 13,
            lift: 0,
            alignment: end ? Alignment.bottomRight : Alignment.bottomLeft,
            child: Padding(padding: const EdgeInsets.fromLTRB(13, 0, 13, 16), child: label),
          ),
        );
    Widget ic(IconData i) => Icon(i, size: 24, color: s.glyph);
    final numbers = _txt('.?123', 22, s.glyph, height: 22);
    Row row(List<Widget> c, double gap) => Row(spacing: gap, children: c);
    List<Widget> keys(List<String> alts, String chars) => [for (var i = 0; i < alts.length; i++) Expanded(child: two(alts[i], chars[i]))];
    final shiftIcon = ic(shift ? CupertinoIcons.shift_fill : CupertinoIcons.shift);
    return Padding(
      padding: const EdgeInsets.fromLTRB(13.5, 6, 13.5, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          SizedBox(
            height: 44,
            child: Stack(children: [
              Positioned(
                left: 9,
                top: 9,
                child: Row(spacing: 18, children: [
                  for (final i in [CupertinoIcons.arrow_uturn_left, CupertinoIcons.arrow_uturn_right, CupertinoIcons.doc_on_clipboard])
                    SizedBox(width: 28, height: 28, child: Icon(i, size: 24, color: s.toolGlyph)),
                ]),
              ),
              Positioned.fill(
                left: 269.5,
                right: 269.5,
                child: Row(children: [
                  for (var i = 0; i < suggestions.take(3).length; i++) ...[
                    if (i > 0) Container(width: 1, height: 25, margin: const EdgeInsets.symmetric(horizontal: 5), color: s.separator),
                    Expanded(child: _txt(suggestions[i], 18, s.suggestion, height: 25, overflow: true)),
                  ],
                ]),
              ),
            ]),
          ),
          Column(mainAxisSize: MainAxisSize.min, spacing: 12, children: [
            SizedBox(
              height: 74,
              child: row([cmd(105, ic(CupertinoIcons.arrow_right_to_line)), ...keys('1234567890'.split(''), 'qwertyuiop'), cmd(105, ic(CupertinoIcons.delete_left), end: true)], 13.75),
            ),
            SizedBox(
              height: 74,
              child: row([cmd(138, ic(CupertinoIcons.capslock)), ...keys(['@', '#', r'$', '&', '*', '(', ')', '’', '”'], 'asdfghjkl'), cmd(167, ic(CupertinoIcons.return_icon), end: true)], 13.5),
            ),
            SizedBox(
              height: 74,
              child: row([
                cmd(182, shiftIcon),
                ...keys(['%', '-', '+', '=', '/', ';', ':'], 'zxcvbnm'),
                Expanded(child: punct('!', ',')),
                Expanded(child: punct('?', '.')),
                cmd(125, shiftIcon, end: true),
              ], 13.5),
            ),
            SizedBox(
              height: 74,
              child: row([
                cmd(84, ic(CupertinoIcons.smiley)),
                cmd(84, numbers),
                cmd(84, ic(CupertinoIcons.mic)),
                Expanded(child: _Key(s: s, radius: 13, child: const SizedBox())),
                cmd(119.33, numbers, end: true),
                cmd(125, ic(CupertinoIcons.keyboard_chevron_compact_down), end: true),
              ], 14),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _row(List<Widget> children, {double gap = 6}) => SizedBox(height: 43, child: Row(spacing: gap, children: children));
}

Text _txt(String t, double size, Color color, {double? height, FontWeight weight = FontWeight.w400, double spacing = 0, bool overflow = false}) =>
    Text(
      t,
      textAlign: TextAlign.center,
      maxLines: 1,
      softWrap: false,
      overflow: overflow ? TextOverflow.ellipsis : TextOverflow.visible,
      style: appleFont(size: size).copyWith(
        fontSize: size,
        height: height == null ? 1 : height / size,
        fontWeight: weight,
        letterSpacing: spacing,
        color: color,
        leadingDistribution: TextLeadingDistribution.even,
        decoration: TextDecoration.none,
      ),
    );

/// Kit "_Background - Keyboard" and "_Keys" colours, reduced to plain fills (light / dark).
class _KbStyle {
  _KbStyle(AppleThemeData theme)
      : background = theme.isDark ? const Color(0xF0262626) : const Color(0xC4D8DCE1),
        key = theme.isDark ? const Color(0x2BEDEDED) : const Color(0xF7FFFFFF),
        glyph = theme.ios.keyboardGlyph,
        secondary = theme.ios.labelSecondary,
        suggestion = theme.ios.labelVibrantPrimary,
        toolGlyph = theme.ios.labelVibrantSecondary,
        separator = theme.ios.fillVibrantPrimary.withValues(alpha: 0.1),
        separatorStrong = theme.ios.fillVibrantPrimary,
        accent = theme.accentColor;
  final Color background;
  final Color key;
  final Color glyph;
  final Color secondary;
  final Color suggestion;
  final Color toolGlyph;
  final Color separator;
  final Color separatorStrong;
  final Color accent;
}

class _Key extends StatelessWidget {
  const _Key({required this.s, required this.child, this.fill, this.radius = 8.5, this.lift = 0, this.alignment = Alignment.center});
  final _KbStyle s;
  final Widget child;
  final Color? fill;
  final double radius;

  /// Characters sit a little above the middle of the key.
  final double lift;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(color: fill ?? s.key, shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius))),
      child: Padding(
        padding: EdgeInsets.only(bottom: lift),
        child: Align(alignment: alignment, child: child),
      ),
    );
  }
}

/// A small key symbol (passwords AutoFill), drawn because CupertinoIcons has no key glyph.
class _KeyGlyphPainter extends CustomPainter {
  _KeyGlyphPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final c = Offset(size.width / 2, size.height * 0.3);
    canvas.drawCircle(c, 5, Paint()..color = color);
    canvas.drawLine(c, Offset(c.dx, size.height - 2), p);
    canvas.drawLine(Offset(c.dx, size.height - 7), Offset(c.dx + 3.5, size.height - 7), p);
  }

  @override
  bool shouldRepaint(_KeyGlyphPainter old) => old.color != color;
}
