import 'dart:math' as math;

import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/widgets.dart';

import '../core/mac_support.dart';
import '../core/macos_tokens.dart';
import '../core/theme.dart';
import '../core/typography.dart';
import '_glyphs.dart';
import 'menus.dart' show MacMenu, MacMenuItem;
import '_text_input.dart' show macFieldTextStyle;
import 'text_fields.dart' show MacTextArea;

/// A macOS form (kit page "Forms"): rows with a label on the left and ONE control on the right.
///
/// Grouped (default, settings windows — like System Settings): rows sit in rounded, lightly filled
/// [MacFormSection]s with a hairline between rows, an optional bold header above and grey footer below.
/// Classic ([columns] true, small dialogs and sheets): right-aligned "Label:" column, controls left-aligned
/// next to it, 12 px between rows, no boxes.
///
///     MacForm(children: [
///       MacFormSection(title: 'General', footer: 'These settings apply to every window.', children: [
///         MacFormRow(label: 'Launch at login', child: MacSwitch(value: login, onChanged: (v) => setState(() => login = v))),
///         MacFormRow(label: 'Version', value: '27.0'),
///       ]),
///     ])
///     MacForm(columns: true, children: [                          // classic dialog layout
///       MacFormRow(label: 'Save As:', child: MacTextField(controller: _name)),
///       MacFormRow(label: 'Tags:', child: MacTextField(placeholder: 'Add tags')),
///     ])
///
/// [children]: [MacFormSection]s (20 px apart). Rows passed directly are put in one section.
/// The form fills the width it gets (480 when unbounded); settings windows are 480–680 wide.
class MacForm extends StatelessWidget {
  const MacForm({super.key, required this.children, this.columns = false, this.labelWidth});

  final List<Widget> children;

  /// Classic layout: right-aligned "Label:" column (Title Case, ending with ":"), no boxes.
  final bool columns;

  /// Classic layout: the label column width (line up several forms). Null = the widest label.
  final double? labelWidth;

  @override
  Widget build(BuildContext context) {
    // Rows given directly: one implicit section around each run of rows.
    final sections = <Widget>[];
    var run = <Widget>[];
    void flush() {
      if (run.isNotEmpty) sections.add(MacFormSection(children: run));
      run = <Widget>[];
    }

    for (final c in children) {
      if (c is MacFormSection) {
        flush();
        sections.add(c);
      } else {
        run.add(c);
      }
    }
    flush();

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: 20), // between one section (with its footer) and the next
          sections[i],
        ],
      ],
    );
    return _MacFormScope(
      columns: columns,
      labelWidth: labelWidth,
      child: DefaultTextStyle(
        style: MacTypography.of(context).body,
        child: LimitedBox(
          maxWidth: 480,
          child: SizedBox(width: double.infinity, child: body),
        ),
      ),
    );
  }
}

class _MacFormScope extends InheritedWidget {
  const _MacFormScope({required this.columns, required this.labelWidth, required super.child});
  final bool columns;
  final double? labelWidth;

  static _MacFormScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_MacFormScope>();

  @override
  bool updateShouldNotify(_MacFormScope old) => old.columns != columns || old.labelWidth != labelWidth;
}

/// Tells a row whether it is the last one of its section (no separator under the last row).
class _MacFormRowSlot extends InheritedWidget {
  const _MacFormRowSlot({required this.last, required super.child});
  final bool last;

  @override
  bool updateShouldNotify(_MacFormRowSlot old) => old.last != last;
}

/// A group of [MacFormRow]s inside a [MacForm]: grouped = a rounded box (radius 12, black 3 % / white 3 %,
/// 10 px side padding), with an optional [title] above (13 Bold) and [footer] below (11, grey).
///
///     MacFormSection(
///       title: 'Notifications',                                   // optional; sentence case or Title Case
///       footer: 'You can change this later in System Settings.',  // optional explanation
///       children: [MacFormRow(...), MacFormRow(...)],
///     )
class MacFormSection extends StatelessWidget {
  const MacFormSection({super.key, this.title, this.footer, required this.children});

  final String? title;

  /// Grey explanation under the section (put explanations here, not in the rows).
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scope = _MacFormScope.maybeOf(context);
    final columns = scope?.columns ?? false;
    final c = AppleTheme.of(context).mac;
    final t = MacTypography.of(context);
    final inset = columns ? 0.0 : 10.0;

    Widget box;
    if (columns) {
      box = _ColumnsGrid(rows: children, labelWidth: scope?.labelWidth);
    } else {
      box = DecoratedBox(
        decoration: BoxDecoration(color: c.fillQuaternary, borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (var i = 0; i < children.length; i++) _MacFormRowSlot(last: i == children.length - 1, child: children[i])],
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: title,
      explicitChildNodes: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: EdgeInsets.fromLTRB(inset, 0, inset, 8),
              child: Text(title!, style: t.headline), // 13 / 16 Bold, label primary
            ),
          box,
          if (footer != null)
            Padding(
              padding: EdgeInsets.fromLTRB(inset, 6, inset, 0),
              child: Text(footer!, style: t.subheadline.copyWith(color: c.labelSecondary)), // 11 / 14, secondary
            ),
        ],
      ),
    );
  }
}

/// One row of a [MacForm]: the label (title + optional subtitle, icon, checkbox or disclosure chevron) on the left,
/// the control on the right (kit "Form Row": 42 px tall, 16 px gap, hairline under it).
///
///     MacFormRow(label: 'Launch at login', child: MacSwitch(value: on, onChanged: (v) => setState(() => on = v)))   // drawn mini
///     MacFormRow(label: 'Show in menu bar', subtitle: 'Adds an icon next to the clock.', child: MacSwitch(...))
///     MacFormRow(label: 'Version', value: '27.0')                                         // read-only grey value
///     MacFormRow(label: 'Wi-Fi', icon: MacFormIcon(AppleIcons.wifi, color: context.macColors.accentBlue),
///                value: 'Home', onTap: openWifi)                                         // navigation row + chevron
///     MacFormRow(label: 'Battery', value: '87%', child: MacFormIconButton.info(onPressed: showInfo))
///     MacFormRow(label: 'Appearance', child: MacFormPopUp<String>(options: modes, value: mode, onChanged: setMode))
///     MacFormRow(label: 'Refresh every', child: MacStepper(...), unit: 'minutes')
///     MacFormRow(label: 'Advanced', expanded: open, onExpandedChanged: (v) => setState(() => open = v))
///     MacFormRow(label: 'Notes', stacked: true, child: MacTextArea(controller: _notes))   // label above, full width
///     MacFormRow(label: 'Sync over cellular', enabled: false, child: MacSwitch(value: false, onChanged: null))
///
/// Grouped labels are sentence case without a colon; classic ([MacForm.columns]) labels are Title Case with ":".
/// Rows have no hover or pressed effect (only [onTap] rows react).
class MacFormRow extends StatelessWidget {
  const MacFormRow({
    super.key,
    required this.label,
    this.subtitle,
    this.child,
    this.value,
    this.unit,
    this.icon,
    this.leading,
    this.onTap,
    this.expanded,
    this.onExpandedChanged,
    this.stacked = false,
    this.enabled = true,
    this.note,
    this.noteIsError = false,
    this.alignLabelTop = false,
  });

  /// The title (13 Medium). Grouped: sentence case, no colon. Classic: "Title Case:".
  final String label;

  /// Small grey line under the title (grouped layout).
  final String? subtitle;

  /// The ONE control: MacSwitch (drawn mini), MacFormPopUp, MacTextField, MacComboBox, MacStepper, MacButton,
  /// MacCheckbox, MacRadioGroup(horizontal: true), MacFormIconButton…
  final Widget? child;

  /// A read-only value in grey before the control ("27.0", "128 GB available").
  final String? value;

  /// Small grey unit after the control, 6 px away ("minutes" after a stepper).
  final String? unit;

  /// Before the title: a [MacFormIcon] (coloured square, 8 px gap) or a plain symbol `Icon(…, size: 15)` (6 px gap).
  final Widget? icon;

  /// Before the icon: a checkbox that turns the whole row's feature on/off (kit "Checkbox + Icon").
  final Widget? leading;

  /// The whole row opens a page of more settings: a chevron at the end, the row is a button.
  final VoidCallback? onTap;

  /// Non-null = a disclosure chevron before the title (› closed, ⌄ open). Show the detail rows after this row
  /// when it is true.
  final bool? expanded;
  final ValueChanged<bool>? onExpandedChanged;

  /// Label above, control full width (a multi-line [MacTextArea]: notes, a description).
  final bool stacked;

  /// False = the title and subtitle turn tertiary. Disable the control itself too (onChanged: null).
  final bool enabled;

  /// Classic layout: a note under the control, 4 px below it (11 px grey; red with [noteIsError]).
  final String? note;
  final bool noteIsError;

  /// Classic layout: line the label up with the first line of a tall control (text area, vertical radio group).
  final bool alignLabelTop;

  @override
  Widget build(BuildContext context) {
    final columns = _MacFormScope.maybeOf(context)?.columns ?? false;
    if (columns) {
      // Outside a section grid (rare): a one-row grid.
      return _ColumnsGrid(rows: [this], labelWidth: _MacFormScope.maybeOf(context)?.labelWidth);
    }
    return _GroupedRow(row: this);
  }
}

/// True for an M2 MacSwitch (by name, so forms don't depend on that file): switches in grouped rows are mini.
bool _isSwitch(Widget? w) => w != null && w.runtimeType.toString() == 'MacSwitch';

class _GroupedRow extends StatefulWidget {
  const _GroupedRow({required this.row});
  final MacFormRow row;

  @override
  State<_GroupedRow> createState() => _GroupedRowState();
}

class _GroupedRowState extends State<_GroupedRow> {
  bool _focusVisible = false;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final theme = AppleTheme.of(context);
    final c = theme.mac;
    final last = context.dependOnInheritedWidgetOfExactType<_MacFormRowSlot>()?.last ?? true;
    final titleColor = row.enabled ? c.labelPrimary : c.labelTertiary;
    final subColor = row.enabled ? c.labelSecondary : c.labelTertiary;
    final titleStyle = macFieldTextStyle(context, fontSize: 13, color: titleColor);
    final subStyle = macFieldTextStyle(context, fontSize: 11, color: subColor);
    final hasSub = row.subtitle != null;

    // Leading part: [checkbox | disclosure] [icon] title/subtitle.
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(row.label, style: titleStyle),
        if (hasSub) ...[const SizedBox(height: 2), Text(row.subtitle!, style: subStyle)],
      ],
    );
    final largeIcon = row.icon is MacFormIcon && (row.icon as MacFormIcon).large;
    // With a subtitle, a checkbox, chevron or small icon lines up with the title line; a large icon stays centred.
    final alignTop = hasSub && !largeIcon;
    final leadingItems = <Widget>[
      ?row.leading,
      if (row.expanded != null)
        _FormDisclosure(expanded: row.expanded!, onChanged: row.onExpandedChanged, label: row.label, color: titleColor),
      ?row.icon,
    ];
    Widget leading;
    if (leadingItems.isEmpty) {
      leading = text;
    } else {
      // A plain symbol sits 6 px before the title; checkboxes, chevrons and icon squares 8 px.
      final gap = row.icon != null && row.icon is! MacFormIcon && row.leading == null && row.expanded == null ? 6.0 : 8.0;
      leading = Row(
        crossAxisAlignment: alignTop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          for (final w in leadingItems) ...[
            // Kit: they share a 19 px frame at the top of the title (a 16 px checkbox 1.5 px down, a 20 px icon -0.5).
            alignTop
                ? SizedBox(
                    height: 19,
                    child: OverflowBox(fit: OverflowBoxFit.deferToChild, minHeight: 0, maxHeight: double.infinity, child: w),
                  )
                : w,
            SizedBox(width: gap),
          ],
          Flexible(child: text),
        ],
      );
    }

    // Trailing part: [value] [control] [unit] [chevron], 8 px apart (6 before a unit).
    Widget? control = row.child;
    if (control != null && _isSwitch(control)) {
      control = MacControlSizeScope(size: MacControlSize.mini, child: control); // kit: mini switches in rows
    }
    final trailing = <Widget>[];
    void add(Widget w, [double gap = 8]) {
      if (trailing.isNotEmpty) trailing.add(SizedBox(width: gap));
      trailing.add(w);
    }

    if (row.value != null) {
      add(_value(row.value!, c.labelSecondary));
    }
    if (control != null && !row.stacked) add(control);
    if (row.unit != null) add(Text(row.unit!, style: subStyle.copyWith(color: c.labelSecondary)), 6);
    if (row.onTap != null) {
      add(macGlyphBox(MacGlyphKind.chevronRight, width: 8, height: 16, glyph: 15, color: c.labelTertiary));
    }

    Widget content;
    if (row.stacked) {
      content = Padding(
        padding: const EdgeInsets.only(top: 11, bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            leading,
            if (control != null) ...[const SizedBox(height: 8), control],
          ],
        ),
      );
    } else {
      content = ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 42),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: Align(alignment: AlignmentDirectional.centerStart, child: leading),
              ),
              if (trailing.isNotEmpty) ...[const SizedBox(width: 16), Row(mainAxisSize: MainAxisSize.min, children: trailing)],
            ],
          ),
        ),
      );
    }

    // Separator: 1 px label quinary under every row but the last, outside the row (kit stroke "outside").
    content = CustomPaint(foregroundPainter: last ? null : _SeparatorPainter(c.labelQuinary), child: content);

    if (row.onTap != null) {
      final accent = theme.accentColor;
      content = FocusableActionDetector(
        mouseCursor: SystemMouseCursors.basic,
        onShowFocusHighlight: (v) => setState(() => _focusVisible = v),
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => row.onTap!())},
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: row.onTap,
          child: CustomPaint(
            foregroundPainter: _focusVisible ? _RingPainter(accent.withValues(alpha: accent.a * 0.55), 6) : null,
            child: content,
          ),
        ),
      );
      content = Semantics(button: true, child: content);
    }
    return MergeSemantics(child: content);
  }

  Widget _value(String value, Color color) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 260),
    child: Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: macFieldTextStyle(context, fontSize: 13, color: color),
    ),
  );
}

class _SeparatorPainter extends CustomPainter {
  _SeparatorPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(Rect.fromLTWH(0, size.height, size.width, 1), Paint()..color = color);
  @override
  bool shouldRepaint(_SeparatorPainter old) => old.color != color;
}

/// The 3.5 px focus ring around a focused row or control.
class _RingPainter extends CustomPainter {
  _RingPainter(this.color, this.radius);
  final Color color;
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    canvas.drawDRRect(r.inflate(3.5), r, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color || old.radius != radius;
}

/// The disclosure chevron that expands a row (kit "_Chevron": › Semibold 10 in 8 × 16; ⌄ when open).
class _FormDisclosure extends StatelessWidget {
  const _FormDisclosure({required this.expanded, required this.onChanged, required this.label, required this.color});
  final bool expanded;
  final ValueChanged<bool>? onChanged;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final glyph = SizedBox(
      width: 8,
      height: 16,
      child: OverflowBox(
        maxWidth: 16,
        maxHeight: 16,
        child: AnimatedRotation(
          turns: expanded ? 0.25 : 0,
          duration: reduce ? Duration.zero : const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: MacGlyph(MacGlyphKind.chevronRightBold, size: 16, color: color),
        ),
      ),
    );
    return Semantics(
      button: true,
      expanded: expanded,
      label: expanded ? 'Hide $label' : 'Show $label',
      child: FocusableActionDetector(
        enabled: onChanged != null,
        mouseCursor: SystemMouseCursors.basic,
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => onChanged?.call(!expanded))},
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onChanged == null ? null : () => onChanged!(!expanded),
          child: glyph,
        ),
      ),
    );
  }
}

/// The classic layout of one section: right-aligned label column, 6 px, controls; rows 12 px apart.
class _ColumnsGrid extends StatelessWidget {
  const _ColumnsGrid({required this.rows, this.labelWidth});
  final List<Widget> rows;
  final double? labelWidth;

  @override
  Widget build(BuildContext context) {
    final c = AppleTheme.of(context).mac;
    final s = MacControlSizeScope.sizesOf(context);
    final fontSize = s.globalFontSize;
    final labelStyle = macFieldTextStyle(context, fontSize: fontSize, color: c.labelSecondary);
    final scaler = MediaQuery.textScalerOf(context);
    final dir = Directionality.of(context);

    // The label column is as wide as the widest label (like CSS grid max-content), unless [labelWidth] is set.
    var width = labelWidth ?? 0.0;
    if (labelWidth == null) {
      for (final r in rows) {
        if (r is! MacFormRow || r.label.isEmpty) continue;
        final tp = TextPainter(
          text: TextSpan(text: r.label, style: labelStyle),
          textDirection: dir,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        width = math.max(width, tp.width.ceilToDouble());
        tp.dispose();
      }
    }

    final out = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (i > 0) out.add(const SizedBox(height: 12));
      if (r is! MacFormRow) {
        out.add(
          Padding(
            padding: EdgeInsetsDirectional.only(start: width + 6),
            child: r,
          ),
        );
        continue;
      }
      final top = r.alignLabelTop || r.child is MacTextArea;
      final labelColor = r.enabled ? c.labelSecondary : c.labelTertiary;
      final label = SizedBox(
        width: width,
        child: Padding(
          padding: EdgeInsets.only(top: top && r.child is MacTextArea ? (s.globalHeight - 16) / 2 : 0),
          child: Text(
            r.label,
            textAlign: TextAlign.end,
            maxLines: 1,
            softWrap: false,
            style: labelStyle.copyWith(color: labelColor),
          ),
        ),
      );
      final controls = <Widget>[
        if (r.leading != null) ...[r.leading!, const SizedBox(width: 8)],
        if (r.value != null)
          Text(
            r.value!,
            style: macFieldTextStyle(context, fontSize: fontSize, color: c.labelSecondary),
          ),
        if (r.value != null && r.child != null) const SizedBox(width: 8),
        if (r.child != null) Flexible(child: r.child!),
        if (r.unit != null) ...[
          const SizedBox(width: 6),
          Text(r.unit!, style: macFieldTextStyle(context, fontSize: 11, color: c.labelSecondary)),
        ],
      ];
      out.add(
        MergeSemantics(
          child: Row(
            crossAxisAlignment: top ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              label,
              const SizedBox(width: 6),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Row(mainAxisSize: r.child is MacTextArea || r.stacked ? MainAxisSize.max : MainAxisSize.min, children: controls),
                ),
              ),
            ],
          ),
        ),
      );
      if (r.note != null) {
        out.add(
          Padding(
            padding: EdgeInsetsDirectional.only(start: width + 6, top: 4),
            child: Text(
              r.note!,
              style: MacTypography.of(context).subheadline.copyWith(color: r.noteIsError ? c.accentRed : c.labelSecondary),
            ),
          ),
        );
        // The note sits 4 px under its control; the next row stays 12 px under the note.
      }
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }
}

/// A coloured icon square before a row title (kit "_Left Accessory Icons"): 20 × 20 (or 26 × 26 with [large],
/// use it with a subtitle), radius 5, the colour with a white top sheen and a soft shadow, a white glyph.
///
///     MacFormIcon(AppleIcons.wifi, color: context.macColors.accentBlue)
///     MacFormIcon(AppleIcons.battery, color: context.macColors.accentGreen, large: true)
///     MacFormIcon(AppleIcons.gear)                        // grey
///
/// Colours: the accent colours (`context.macColors.accentRed` … `accentBrown`), black, dark grey `Color(0xFF4A4A4A)`,
/// light grey `Color(0xFF919191)`, white `Color(0xFFE5E5E5)` (gets a dark glyph). Decorative: no semantics.
class MacFormIcon extends StatelessWidget {
  const MacFormIcon(this.icon, {super.key, this.color, this.large = false});

  final IconData icon;

  /// The square's colour. Null = system grey.
  final Color? color;

  /// 26 × 26 (kit "32pt") instead of 20 × 20 (kit "24pt").
  final bool large;

  @override
  Widget build(BuildContext context) {
    final base = color ?? AppleTheme.of(context).mac.gray;
    final white = base.computeLuminance() > 0.7;
    final side = large ? 26.0 : 20.0;
    final glyph = large ? 17.0 : 13.0;
    return ExcludeSemantics(
      child: CustomPaint(
        painter: _IconSquarePainter(base, white),
        child: SizedBox.square(
          dimension: side,
          child: Center(
            child: Icon(icon, size: glyph, color: white ? const Color(0xD9000000) : const Color(0xFFFFFFFF)),
          ),
        ),
      ),
    );
  }
}

class _IconSquarePainter extends CustomPainter {
  _IconSquarePainter(this.color, this.white);
  final Color color;
  final bool white;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(5));
    // 0 0.5 1.5 black 20 %
    canvas.drawRRect(
      shape.shift(const Offset(0, 0.5)),
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.75),
    );
    canvas.drawRRect(shape, Paint()..color = color);
    // White sheen, top to bottom: 20 % → 0 (the white square: 100 % → 0).
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [white ? const Color(0xFFFFFFFF) : const Color(0x33FFFFFF), const Color(0x00FFFFFF)],
        ).createShader(rect),
    );
    // Inner hairlines: white 10 % top and bottom, a brighter top highlight.
    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 0.5), Paint()..color = const Color(0x1AFFFFFF));
    canvas.drawRect(Rect.fromLTWH(0, size.height - 0.5, size.width, 0.5), Paint()..color = const Color(0x1AFFFFFF));
    canvas.drawRect(
      Rect.fromLTWH(1, 0.5, size.width - 2, 0.5),
      Paint()
        ..color = const Color(0x99FFFFFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.25),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconSquarePainter old) => old.color != color || old.white != white;
}

/// The ⓘ and ··· buttons of a form row (kit "Label + Info Button", "More Button"): a 16 × 16 glyph in label
/// secondary; label primary while pressed. Icon-only: it always has an accessible name.
///
///     MacFormRow(label: 'Battery', value: '87%', child: MacFormIconButton.info(onPressed: showBatteryInfo))
///     MacFormRow(label: 'Storage', value: '128 GB available', child: MacFormIconButton.more(onPressed: showMenu))
///     MacFormIconButton(icon: AppleIcons.questionmarkCircle, semanticLabel: 'Help', onPressed: help)
class MacFormIconButton extends StatefulWidget {
  const MacFormIconButton({super.key, required IconData this.icon, required this.semanticLabel, required this.onPressed}) : _glyph = null;

  /// ⓘ "More Info".
  const MacFormIconButton.info({super.key, this.semanticLabel = 'More Info', required this.onPressed})
    : icon = null,
      _glyph = MacGlyphKind.infoCircle;

  /// ··· "More".
  const MacFormIconButton.more({super.key, this.semanticLabel = 'More', required this.onPressed})
    : icon = null,
      _glyph = MacGlyphKind.ellipsis;

  final IconData? icon;
  final String semanticLabel;

  /// Null = disabled (label tertiary).
  final VoidCallback? onPressed;
  final MacGlyphKind? _glyph;

  @override
  State<MacFormIconButton> createState() => _MacFormIconButtonState();
}

class _MacFormIconButtonState extends State<MacFormIconButton> {
  bool _pressed = false;
  bool _focusVisible = false;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.mac;
    final enabled = widget.onPressed != null;
    final color = !enabled ? c.labelTertiary : (_pressed ? c.labelPrimary : c.labelSecondary);
    final glyph = widget._glyph != null ? MacGlyph(widget._glyph!, size: 16, color: color) : Icon(widget.icon, size: 15, color: color);
    final accent = theme.accentColor;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: SystemMouseCursors.basic,
        onShowFocusHighlight: (v) => setState(() => _focusVisible = v),
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed?.call())},
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTap: widget.onPressed,
          child: CustomPaint(
            foregroundPainter: _focusVisible ? _RingPainter(accent.withValues(alpha: accent.a * 0.55), 4) : null,
            child: SizedBox.square(dimension: 16, child: Center(child: glyph)),
          ),
        ),
      ),
    );
  }
}

/// The pop-up of a grouped form row (kit "Trailing Accessories / Pop-Up Button"): the value in label primary,
/// 12 px gap, then a 16 px circle with ⌃⌄. Click (or ↓ / Space / Return) opens a [MacMenu] of the options, ✓ on the
/// current one.
///
///     MacFormRow(
///       label: 'Appearance',
///       child: MacFormPopUp<String>(
///         options: const ['Automatic', 'Light', 'Dark'],
///         value: appearance,
///         onChanged: (v) => setState(() => appearance = v),
///       ),
///     )
///     MacFormPopUp<Sort>(options: Sort.values, value: sort, labelOf: (s) => s.title, onChanged: …)
///
/// [onChanged] null = disabled. In a classic form ([MacForm.columns]) use the bordered pop-up button instead.
class MacFormPopUp<T> extends StatefulWidget {
  const MacFormPopUp({super.key, required this.options, required this.value, required this.onChanged, this.labelOf, this.semanticLabel});

  final List<T> options;
  final T value;
  final ValueChanged<T>? onChanged;

  /// The text of an option. Default: `option.toString()`.
  final String Function(T option)? labelOf;
  final String? semanticLabel;

  @override
  State<MacFormPopUp<T>> createState() => _MacFormPopUpState<T>();
}

class _MacFormPopUpState<T> extends State<MacFormPopUp<T>> {
  bool _focusVisible = false;

  String _label(T o) => widget.labelOf?.call(o) ?? '$o';
  bool get _enabled => widget.onChanged != null;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.mac;
    final dark = theme.isDark;
    final color = _enabled ? c.labelPrimary : c.labelTertiary;
    final style = macFieldTextStyle(context, fontSize: 13, color: color);
    final accent = theme.accentColor;

    // The trigger: "Value  ⌃⌄". The circle darkens while the menu is open (kit State=Clicked).
    final trigger = Builder(
      builder: (context) {
        final open = MacMenu.isOpenOf(context);
        final circle = open && _enabled
            ? (dark ? const Color(0x29FFFFFF) : const Color(0x29000000))
            : (dark ? const Color(0x12FFFFFF) : const Color(0x14000000));
        return Focus(
          canRequestFocus: _enabled,
          onFocusChange: (f) => setState(() => _focusVisible = f && FocusManager.instance.highlightMode == FocusHighlightMode.traditional),
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            child: CustomPaint(
              foregroundPainter: _focusVisible ? _RingPainter(accent.withValues(alpha: accent.a * 0.55), 4) : null,
              child: SizedBox(
                height: 16,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(_label(widget.value), maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: style),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(color: circle, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: MacGlyph(MacGlyphKind.chevronUpDownBold, size: 14, color: color),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      value: _label(widget.value),
      child: MacMenu(
        enabled: _enabled,
        matchTriggerWidth: false,
        semanticLabel: widget.semanticLabel,
        items: [
          for (final o in widget.options)
            MacMenuItem(label: _label(o), checked: o == widget.value, onSelected: () => widget.onChanged?.call(o)),
        ],
        trigger: trigger,
      ),
    );
  }
}
