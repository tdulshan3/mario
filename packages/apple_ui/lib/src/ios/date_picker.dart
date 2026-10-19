import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoLocalizations;
import 'package:flutter/widgets.dart';

import '../core/glass.dart';
import '../core/icons.dart';
import '../core/theme.dart';
import '../core/typography.dart';

/* ------------------------------------------------------------------ wheel picker */

/// One wheel of an [IosWheelPicker].
@immutable
class IosWheelColumn {
  const IosWheelColumn({
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
    this.semanticLabel,
    this.alignment = Alignment.center,
    this.width,
  });

  /// The rows, top to bottom.
  final List<String> items;
  final int selectedIndex;

  /// Called with the new row while the wheel settles. Null = the wheel can't be turned.
  final ValueChanged<int>? onChanged;

  /// Accessible name of the wheel ("Hour").
  final String? semanticLabel;

  /// Text alignment in the wheel: centerLeft, center (default) or centerRight.
  final Alignment alignment;

  /// Fixed width; wheels without one share the rest.
  final double? width;
}

/// Spinning wheels (SwiftUI Picker(.wheel), UIPickerView; kit "Date and time - Wheels"): 32 pt rows, 23 pt text,
/// a 35 pt selection band, rows outside the band dimmed and fading at the top and bottom.
///
///     IosWheelPicker(columns: [
///       IosWheelColumn(items: sizes, selectedIndex: size, onChanged: (i) => setState(() => size = i), semanticLabel: 'Size'),
///     ])
class IosWheelPicker extends StatelessWidget {
  const IosWheelPicker({super.key, required this.columns, this.glass = false});

  final List<IosWheelColumn> columns;

  /// Draw it on a panel of Thick blur material (radius 13), as in a popover.
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final c = AppleTheme.of(context).ios;
    Widget body = SizedBox(
      height: 214,
      child: Stack(
        children: [
          // Kit "Selection": Fills/Quaternary, 35 tall, the full width of the picker.
          Positioned(
            left: 0,
            right: 0,
            top: 107 - 17.5,
            height: 35,
            child: DecoratedBox(
              decoration: ShapeDecoration(color: c.fillQuaternary, shape: const StadiumBorder()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              // Wheels that all have a width (time) sit in the middle, like iOS.
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final col in columns)
                  if (col.width != null)
                    SizedBox(
                      width: col.width,
                      child: _Wheel(column: col),
                    )
                  else
                    Expanded(child: _Wheel(column: col)),
              ],
            ),
          ),
        ],
      ),
    );
    if (glass) body = AppleGlass(style: AppleGlassStyle.panel, radius: 13, child: body);
    return body;
  }
}

class _Wheel extends StatefulWidget {
  const _Wheel({required this.column});
  final IosWheelColumn column;
  @override
  State<_Wheel> createState() => _WheelState();
}

class _WheelState extends State<_Wheel> {
  late final FixedExtentScrollController _controller = FixedExtentScrollController(initialItem: widget.column.selectedIndex);

  @override
  void didUpdateWidget(_Wheel old) {
    super.didUpdateWidget(old);
    final want = widget.column.selectedIndex;
    if (_controller.hasClients && _controller.selectedItem != want && !_controller.position.isScrollingNotifier.value) {
      _controller.jumpToItem(want);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final col = widget.column;
    final c = AppleTheme.of(context).ios;
    final style = appleFont(size: 23).copyWith(
      fontSize: 23,
      height: 32 / 23,
      letterSpacing: 0.35,
      color: c.labelPrimary,
      leadingDistribution: TextLeadingDistribution.even,
      decoration: TextDecoration.none,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final int selected = col.selectedIndex.clamp(0, math.max(0, col.items.length - 1)).toInt();
    return Semantics(
      label: col.semanticLabel,
      value: col.items.isEmpty ? null : col.items[selected],
      increasedValue: selected + 1 < col.items.length ? col.items[selected + 1] : null,
      decreasedValue: selected > 0 ? col.items[selected - 1] : null,
      onIncrease: col.onChanged == null || selected + 1 >= col.items.length
          ? null
          : () => _controller.animateToItem(selected + 1, duration: const Duration(milliseconds: 200), curve: Curves.easeOut),
      onDecrease: col.onChanged == null || selected <= 0
          ? null
          : () => _controller.animateToItem(selected - 1, duration: const Duration(milliseconds: 200), curve: Curves.easeOut),
      child: ExcludeSemantics(
        // Rows outside the band fade from 100 % to 30 % towards the top and bottom edge (kit "_Gradient").
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x4D000000), Color(0xFF000000), Color(0xFF000000), Color(0x4D000000)],
            stops: [0, 72 / 178, 106 / 178, 1],
          ).createShader(rect),
          child: ListWheelScrollView.useDelegate(
            controller: _controller,
            // Kit wheel rows sit 32, 58.75 and 77.75 pt from the centre: a cylinder of radius 80.6, 23.4° a row.
            itemExtent: 32,
            diameterRatio: 0.906,
            squeeze: 1.384,
            perspective: 0.001,
            // Rows outside the band: the label colour at 30 % = the kit's #B3B3B3 on white.
            overAndUnderCenterOpacity: 0.3,
            physics: col.onChanged == null ? const NeverScrollableScrollPhysics() : const FixedExtentScrollPhysics(),
            onSelectedItemChanged: col.onChanged,
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: col.items.length,
              builder: (context, i) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: col.onChanged == null
                    ? null
                    : () => _controller.animateToItem(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                child: Align(
                  alignment: col.alignment,
                  child: Text(col.items[i], style: style, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------ shared helpers */

const _shortMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdaySymbols = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
const _weekdayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

bool _sameDay(DateTime? a, DateTime? b) => a != null && b != null && a.year == b.year && a.month == b.month && a.day == b.day;
DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

String _defaultDate(BuildContext context, DateTime d) => '${_shortMonths[d.month - 1]} ${d.day}, ${d.year}';
String _defaultTime(BuildContext context, DateTime d) {
  final l = CupertinoLocalizations.of(context);
  final m = d.minute.toString().padLeft(2, '0');
  if (MediaQuery.alwaysUse24HourFormatOf(context)) return '${d.hour.toString().padLeft(2, '0')}:$m';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:$m ${d.hour < 12 ? l.anteMeridiemAbbreviation : l.postMeridiemAbbreviation}';
}

/// The grey date/time capsule (kit "Date and time - Collapsed"): 34 tall, padding 11, 17 Regular; accent while open.
class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.open, required this.onTap, this.semanticLabel});
  final String text;
  final bool open;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final t = IosTypography.of(context).body;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel == null ? text : '$semanticLabel, $text',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5), // 44 pt tap height
          child: DecoratedBox(
            decoration: ShapeDecoration(color: c.fillTertiary, shape: const StadiumBorder()),
            child: SizedBox(
              height: 34,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    text,
                    maxLines: 1,
                    style: t.copyWith(color: onTap == null ? c.labelTertiary : (open ? theme.accentColor : c.labelPrimary)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A popover route placed under (or above) a widget; centred on iPhone sizes. Light dismiss and back close it.
class _AnchoredRoute<T> extends PopupRoute<T> {
  _AnchoredRoute({required this.anchor, required this.builder, required this.theme});
  final Rect anchor;
  final WidgetBuilder builder;
  final AppleThemeData theme;

  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => 'Dismiss';
  @override
  Duration get transitionDuration => const Duration(milliseconds: 250);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    return AppleTheme(
      data: theme,
      child: CustomSingleChildLayout(
        delegate: _AnchoredLayout(anchor, regular: MediaQuery.sizeOf(context).width >= 744 && MediaQuery.sizeOf(context).height >= 600),
        child: Builder(builder: builder),
      ),
    );
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    if (MediaQuery.disableAnimationsOf(context)) return FadeTransition(opacity: animation, child: child);
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: ScaleTransition(scale: Tween<double>(begin: 0.9, end: 1).animate(curved), child: child),
    );
  }
}

class _AnchoredLayout extends SingleChildLayoutDelegate {
  _AnchoredLayout(this.anchor, {required this.regular});
  final Rect anchor;
  final bool regular;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(maxWidth: math.max(0, constraints.maxWidth - 32), maxHeight: math.max(0, constraints.maxHeight - 16));

  @override
  Offset getPositionForChild(Size size, Size child) {
    var left = regular ? anchor.center.dx - child.width / 2 : (size.width - child.width) / 2;
    left = left.clamp(16.0, math.max(16.0, size.width - child.width - 16));
    var top = anchor.bottom + 8;
    if (top + child.height > size.height - 8 && anchor.top - 8 - child.height > 8) top = anchor.top - 8 - child.height;
    return Offset(left, math.max(8, top));
  }

  @override
  bool shouldRelayout(_AnchoredLayout old) => old.anchor != anchor || old.regular != regular;
}

Future<void> _showPopover(BuildContext anchorContext, WidgetBuilder builder) {
  final navigator = Navigator.of(anchorContext);
  final box = anchorContext.findRenderObject()! as RenderBox;
  final origin = box.localToGlobal(Offset.zero, ancestor: navigator.context.findRenderObject());
  return navigator.push(_AnchoredRoute<void>(anchor: origin & box.size, builder: builder, theme: AppleTheme.of(anchorContext)));
}

/* ------------------------------------------------------------------ time wheels */

/// Hour, minute (and AM/PM) wheels for [value]; [onChanged] gets the same day with the new time.
Widget _timeWheels(BuildContext context, DateTime value, ValueChanged<DateTime> onChanged, {bool glass = false}) {
  final l = CupertinoLocalizations.of(context);
  final h24 = MediaQuery.alwaysUse24HourFormatOf(context);
  DateTime at(int hour, int minute) => DateTime(value.year, value.month, value.day, hour, minute);
  final pm = value.hour >= 12;
  return IosWheelPicker(
    glass: glass,
    columns: [
      if (h24)
        IosWheelColumn(
          semanticLabel: 'Hour',
          width: 36,
          alignment: Alignment.centerRight,
          items: [for (var i = 0; i < 24; i++) i.toString().padLeft(2, '0')],
          selectedIndex: value.hour,
          onChanged: (i) => onChanged(at(i, value.minute)),
        )
      else
        IosWheelColumn(
          semanticLabel: 'Hour',
          width: 36,
          alignment: Alignment.centerRight,
          items: [for (var i = 0; i < 12; i++) '${i == 0 ? 12 : i}'],
          selectedIndex: value.hour % 12,
          onChanged: (i) => onChanged(at(i + (pm ? 12 : 0), value.minute)),
        ),
      IosWheelColumn(
        semanticLabel: 'Minute',
        width: 80,
        items: [for (var i = 0; i < 60; i++) i.toString().padLeft(2, '0')],
        selectedIndex: value.minute,
        onChanged: (i) => onChanged(at(value.hour, i)),
      ),
      if (!h24)
        IosWheelColumn(
          semanticLabel: 'AM/PM',
          width: 42,
          alignment: Alignment.centerLeft,
          items: [l.anteMeridiemAbbreviation, l.postMeridiemAbbreviation],
          selectedIndex: pm ? 1 : 0,
          onChanged: (i) => onChanged(at(value.hour % 12 + (i == 1 ? 12 : 0), value.minute)),
        ),
    ],
  );
}

/// Keeps a popover's picker in step with its owner: the popover edits its own copy and reports every change.
class _LiveValue extends StatefulWidget {
  const _LiveValue({required this.initial, required this.onChanged, required this.builder});
  final DateTime initial;
  final ValueChanged<DateTime> onChanged;
  final Widget Function(BuildContext context, DateTime value, ValueChanged<DateTime> set) builder;
  @override
  State<_LiveValue> createState() => _LiveValueState();
}

class _LiveValueState extends State<_LiveValue> {
  late DateTime _value = widget.initial;
  @override
  Widget build(BuildContext context) => widget.builder(context, _value, (v) {
    setState(() => _value = v);
    widget.onChanged(v);
  });
}

/* ------------------------------------------------------------------ calendar */

/// A month calendar (SwiftUI DatePicker(.graphical); kit "Date and time - Pickers"): month title, arrows, weekday
/// letters, 38 pt day circles. Tapping the title shows month and year wheels.
///
///     IosCalendarPicker(value: day, onChanged: (d) => setState(() => day = d))
///     IosCalendarPicker(value: start, onChanged: setStart, showTime: true)        // with the "Time" row
class IosCalendarPicker extends StatefulWidget {
  const IosCalendarPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.today,
    this.firstWeekday = DateTime.sunday,
    this.showTime = false,
    this.timeLabel = 'Time',
    this.glass = false,
    this.weekdaySymbols = _weekdaySymbols,
    this.formatTime,
  });

  /// The selected day (and time, for [showTime]). Null = nothing selected yet.
  final DateTime? value;

  /// The new day keeps the time of [value]. Null = read only.
  final ValueChanged<DateTime>? onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;

  /// The accent-coloured day. Default: today.
  final DateTime? today;

  /// [DateTime.sunday] (default) or [DateTime.monday].
  final int firstWeekday;

  /// Adds the "Time" row (kit "Show Time") with a time capsule that opens time wheels.
  final bool showTime;
  final String timeLabel;

  /// Draw it on a panel of Thick blur material (radius 13, 370 wide) — what the compact [IosDatePicker] opens.
  final bool glass;

  /// Seven weekday letters starting with Sunday (localise them here). Shown in upper case.
  final List<String> weekdaySymbols;

  /// Text of the time capsule. Default "9:41 AM" style (24-hour when the device uses it).
  final String Function(BuildContext context, DateTime time)? formatTime;

  @override
  State<IosCalendarPicker> createState() => _IosCalendarPickerState();
}

class _IosCalendarPickerState extends State<IosCalendarPicker> {
  late DateTime _month = DateTime(
    (widget.value ?? widget.today ?? DateTime.now()).year,
    (widget.value ?? widget.today ?? DateTime.now()).month,
  );
  bool _wheels = false;
  bool _timeOpen = false;

  bool _disabled(DateTime d) =>
      (widget.firstDate != null && d.isBefore(_day(widget.firstDate!))) || (widget.lastDate != null && d.isAfter(widget.lastDate!));

  void _pick(DateTime d) {
    final v = widget.value;
    widget.onChanged?.call(v == null ? d : DateTime(d.year, d.month, d.day, v.hour, v.minute));
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final l = CupertinoLocalizations.of(context);
    final t = IosTypography.of(context);
    final today = widget.today ?? DateTime.now();
    final y = _month.year;
    final m = _month.month;
    final title = '${l.datePickerMonth(m)} $y';
    final count = DateTime(y, m + 1, 0).day;
    final lead = (DateTime(y, m, 1).weekday % 7 - widget.firstWeekday % 7 + 7) % 7;
    final prevDisabled = widget.firstDate != null && DateTime(y, m, 0).isBefore(widget.firstDate!);
    final nextDisabled = widget.lastDate != null && DateTime(y, m + 1, 1).isAfter(widget.lastDate!);

    Widget arrow(IconData icon, String label, bool disabled, int step) => Semantics(
      button: true,
      enabled: !disabled,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: disabled ? null : () => setState(() => _month = DateTime(y, m + step)),
        child: SizedBox(
          width: 15,
          height: 24,
          child: OverflowBox(
            maxWidth: 44,
            maxHeight: 44,
            child: Center(child: Icon(icon, size: 22, color: disabled ? c.labelTertiary : c.labelPrimary)),
          ),
        ),
      ),
    );

    final header = SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 13, 6, 3),
        child: Row(
          children: [
            Semantics(
              button: true,
              expanded: _wheels,
              label: title,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _wheels = !_wheels),
                child: SizedBox(
                  height: 24,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: t.headline.copyWith(color: _wheels ? theme.accentColor : c.labelPrimary)),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: _wheels ? 0.25 : 0,
                        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 250),
                        child: Icon(AppleIcons.chevronRight, size: 14, color: theme.accentColor),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Spacer(),
            if (!_wheels) ...[
              arrow(AppleIcons.chevronLeft, 'Previous Month', prevDisabled, -1),
              const SizedBox(width: 28),
              arrow(AppleIcons.chevronRight, 'Next Month', nextDisabled, 1),
            ],
          ],
        ),
      ),
    );

    Widget body;
    if (_wheels) {
      final years = [for (var i = y - 100; i <= y + 100; i++) i];
      body = Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 11),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 242),
          child: Center(
            child: IosWheelPicker(
              columns: [
                IosWheelColumn(
                  semanticLabel: 'Month',
                  items: [for (var i = 1; i <= 12; i++) l.datePickerMonth(i)],
                  selectedIndex: m - 1,
                  onChanged: (i) => setState(() => _month = DateTime(_month.year, i + 1)),
                ),
                IosWheelColumn(
                  semanticLabel: 'Year',
                  items: [for (final v in years) '$v'],
                  selectedIndex: 100,
                  onChanged: (i) => setState(() => _month = DateTime(years[i], _month.month)),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      final weekdays = SizedBox(
        height: 20,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < 7; i++)
              SizedBox(
                width: 38,
                child: OverflowBox(
                  maxWidth: 50,
                  child: Text(
                    widget.weekdaySymbols[(widget.firstWeekday % 7 + i) % 7].toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: t.footnoteEmphasized.copyWith(color: c.labelTertiary, height: 20 / 13),
                  ),
                ),
              ),
          ],
        ),
      );
      final rows = <Widget>[];
      final cells = (lead + count + 6) ~/ 7 * 7;
      for (var r = 0; r < cells ~/ 7; r++) {
        if (r > 0) rows.add(const SizedBox(height: 13));
        rows.add(
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 7; i++)
                () {
                  final n = r * 7 + i - lead + 1;
                  if (n < 1 || n > count) return const SizedBox(width: 38, height: 38);
                  final d = DateTime(y, m, n);
                  return _DayCell(
                    date: d,
                    isToday: _sameDay(d, today),
                    isSelected: _sameDay(d, widget.value),
                    enabled: widget.onChanged != null && !_disabled(d),
                    onTap: () => _pick(d),
                  );
                }(),
            ],
          ),
        );
      }
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [const SizedBox(height: 8), weekdays, const SizedBox(height: 4), ...rows, const SizedBox(height: 11)],
      );
    }

    final hairline = MediaQuery.devicePixelRatioOf(context) >= 2 ? 0.5 : 1.0;
    final value = widget.value ?? today;
    final timeRow = widget.showTime
        ? DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: c.separator, width: hairline),
              ),
            ),
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  Expanded(child: Text(widget.timeLabel, style: t.body)),
                  Builder(
                    builder: (pillContext) => _Pill(
                      text: (widget.formatTime ?? _defaultTime)(context, value),
                      open: _timeOpen,
                      onTap: widget.onChanged == null
                          ? null
                          : () async {
                              setState(() => _timeOpen = true);
                              await _showPopover(
                                pillContext,
                                (_) => _LiveValue(
                                  initial: value,
                                  onChanged: (v) => widget.onChanged?.call(v),
                                  builder: (ctx, v, set) => SizedBox(width: 200, child: _timeWheels(ctx, v, set, glass: true)),
                                ),
                              );
                              if (mounted) setState(() => _timeOpen = false);
                            },
                    ),
                  ),
                ],
              ),
            ),
          )
        : null;

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [header, body, ?timeRow],
    );
    if (widget.glass) {
      return SizedBox(
        width: 370,
        child: AppleGlass(
          style: AppleGlassStyle.panel,
          radius: 13,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: content),
        ),
      );
    }
    return ColoredBox(
      color: c.groupedBgSecondary,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: content),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.date, required this.isToday, required this.isSelected, required this.enabled, required this.onTap});
  final DateTime date;
  final bool isToday;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final t = IosTypography.of(context).title3;
    // Kit _Day: Default · Current (accent 12 % circle, accent number) · Selected (primary-label circle, background-coloured
    // Semibold number) · Current and Selected (accent circle, white Semibold number).
    Color? fill;
    var color = enabled ? c.labelPrimary : c.labelTertiary;
    var weight = FontWeight.w400;
    if (isSelected && isToday) {
      fill = theme.accentColor;
      color = const Color(0xFFFFFFFF);
      weight = FontWeight.w600;
    } else if (isSelected) {
      fill = c.labelPrimary;
      color = c.bgPrimary;
      weight = FontWeight.w600;
    } else if (isToday) {
      fill = theme.accentColor.withValues(alpha: 0.12);
      color = theme.accentColor;
    }
    return Semantics(
      button: true,
      selected: isSelected,
      enabled: enabled,
      label:
          '${_weekdayNames[date.weekday % 7]}, ${CupertinoLocalizations.of(context).datePickerMonth(date.month)} ${date.day}, ${date.year}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 38,
          height: 38,
          child: DecoratedBox(
            decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
            child: Center(
              child: Text(
                '${date.day}',
                style: t.copyWith(color: color, fontWeight: weight, height: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------ date picker */

/// What an [IosDatePicker] picks.
enum IosDatePickerMode { date, time, dateAndTime }

/// [compact] (default): grey capsules that open a popover · [inline]: the calendar in place · [wheels]: spinning wheels.
enum IosDatePickerStyle { compact, inline, wheels }

/// The iOS date picker (SwiftUI DatePicker). Compact: capsules ("Apr 1, 2026" "9:41 AM", kit "Date and time -
/// Collapsed") that open the calendar or time wheels in a popover. Inline: [IosCalendarPicker]. Wheels: [IosWheelPicker].
///
///     IosDatePicker(value: start, onChanged: (d) => setState(() => start = d))
///     IosDatePicker(value: day, onChanged: setDay, mode: IosDatePickerMode.date, style: IosDatePickerStyle.inline)
class IosDatePicker extends StatefulWidget {
  const IosDatePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.mode = IosDatePickerMode.dateAndTime,
    this.style = IosDatePickerStyle.compact,
    this.firstDate,
    this.lastDate,
    this.firstWeekday = DateTime.sunday,
    this.formatDate,
    this.formatTime,
    this.semanticLabel,
  });

  final DateTime value;

  /// Null = disabled.
  final ValueChanged<DateTime>? onChanged;
  final IosDatePickerMode mode;
  final IosDatePickerStyle style;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final int firstWeekday;

  /// Text of the date capsule. Default "Apr 1, 2026" (pass intl's DateFormat.yMMMd().format for other languages).
  final String Function(BuildContext context, DateTime date)? formatDate;

  /// Text of the time capsule. Default "9:41 AM" (24-hour when the device uses it).
  final String Function(BuildContext context, DateTime time)? formatTime;

  /// Accessible name ("Starts"). Put the visible label in the list row.
  final String? semanticLabel;

  @override
  State<IosDatePicker> createState() => _IosDatePickerState();
}

class _IosDatePickerState extends State<IosDatePicker> {
  bool _dateOpen = false;
  bool _timeOpen = false;

  DateTime _clamp(DateTime d) {
    if (widget.firstDate != null && d.isBefore(widget.firstDate!)) return widget.firstDate!;
    if (widget.lastDate != null && d.isAfter(widget.lastDate!)) return widget.lastDate!;
    return d;
  }

  void _set(DateTime d) => widget.onChanged?.call(_clamp(d));

  @override
  Widget build(BuildContext context) {
    final hasDate = widget.mode != IosDatePickerMode.time;
    final hasTime = widget.mode != IosDatePickerMode.date;
    final enabled = widget.onChanged != null;
    final v = widget.value;

    if (widget.style == IosDatePickerStyle.inline && hasDate) {
      return Semantics(
        label: widget.semanticLabel,
        child: IosCalendarPicker(
          value: v,
          onChanged: enabled ? _set : null,
          firstDate: widget.firstDate,
          lastDate: widget.lastDate,
          firstWeekday: widget.firstWeekday,
          showTime: hasTime,
          formatTime: widget.formatTime,
        ),
      );
    }
    if (widget.style != IosDatePickerStyle.compact) {
      return Semantics(label: widget.semanticLabel, child: _wheels(context, v));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasDate)
          Builder(
            builder: (pillContext) => _Pill(
              text: (widget.formatDate ?? _defaultDate)(context, v),
              open: _dateOpen,
              semanticLabel: widget.semanticLabel,
              onTap: !enabled
                  ? null
                  : () async {
                      setState(() => _dateOpen = true);
                      await _showPopover(
                        pillContext,
                        (_) => _LiveValue(
                          initial: v,
                          onChanged: _set,
                          builder: (ctx, value, set) => IosCalendarPicker(
                            value: value,
                            onChanged: set,
                            glass: true,
                            firstDate: widget.firstDate,
                            lastDate: widget.lastDate,
                            firstWeekday: widget.firstWeekday,
                          ),
                        ),
                      );
                      if (mounted) setState(() => _dateOpen = false);
                    },
            ),
          ),
        if (hasDate && hasTime) const SizedBox(width: 6),
        if (hasTime)
          Builder(
            builder: (pillContext) => _Pill(
              text: (widget.formatTime ?? _defaultTime)(context, v),
              open: _timeOpen,
              semanticLabel: widget.semanticLabel,
              onTap: !enabled
                  ? null
                  : () async {
                      setState(() => _timeOpen = true);
                      await _showPopover(
                        pillContext,
                        (_) => _LiveValue(
                          initial: v,
                          onChanged: _set,
                          builder: (ctx, value, set) => SizedBox(width: 200, child: _timeWheels(ctx, value, set, glass: true)),
                        ),
                      );
                      if (mounted) setState(() => _timeOpen = false);
                    },
            ),
          ),
      ],
    );
  }

  Widget _wheels(BuildContext context, DateTime v) {
    final hasDate = widget.mode != IosDatePickerMode.time;
    final hasTime = widget.mode != IosDatePickerMode.date;
    final onChanged = widget.onChanged == null ? null : _set;
    if (!hasDate) return _timeWheels(context, v, onChanged ?? (_) {});
    final l = CupertinoLocalizations.of(context);
    if (!hasTime) {
      final first = widget.firstDate?.year ?? v.year - 100;
      final last = widget.lastDate?.year ?? v.year + 100;
      final days = DateTime(v.year, v.month + 1, 0).day;
      DateTime make(int y, int m, int d) => DateTime(y, m, math.min(d, DateTime(y, m + 1, 0).day), v.hour, v.minute);
      return IosWheelPicker(
        columns: [
          IosWheelColumn(
            semanticLabel: 'Month',
            width: 130,
            alignment: Alignment.centerLeft,
            items: [for (var i = 1; i <= 12; i++) l.datePickerMonth(i)],
            selectedIndex: v.month - 1,
            onChanged: onChanged == null ? null : (i) => onChanged(make(v.year, i + 1, v.day)),
          ),
          IosWheelColumn(
            semanticLabel: 'Day',
            width: 48,
            items: [for (var i = 1; i <= days; i++) '$i'],
            selectedIndex: v.day - 1,
            onChanged: onChanged == null ? null : (i) => onChanged(make(v.year, v.month, i + 1)),
          ),
          IosWheelColumn(
            semanticLabel: 'Year',
            alignment: Alignment.centerRight,
            items: [for (var y = first; y <= last; y++) '$y'],
            selectedIndex: v.year - first,
            onChanged: onChanged == null ? null : (i) => onChanged(make(first + i, v.month, v.day)),
          ),
        ],
      );
    }
    // Date and time: a day wheel ("Today", "Mon Apr 20") next to the time wheels.
    final base = _day(DateTime.now());
    final offset = _day(v).difference(base).inDays.clamp(-365, 365);
    final time = _timeWheels(context, v, (d) => onChanged?.call(d)) as IosWheelPicker;
    return IosWheelPicker(
      columns: [
        IosWheelColumn(
          semanticLabel: 'Day',
          width: 130,
          alignment: Alignment.centerRight,
          items: [for (var i = -365; i <= 365; i++) i == 0 ? l.todayLabel : l.datePickerMediumDate(base.add(Duration(days: i)))],
          selectedIndex: offset + 365,
          onChanged: onChanged == null
              ? null
              : (i) {
                  final d = base.add(Duration(days: i - 365));
                  onChanged(DateTime(d.year, d.month, d.day, v.hour, v.minute));
                },
        ),
        ...time.columns,
      ],
    );
  }
}
