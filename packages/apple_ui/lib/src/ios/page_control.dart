import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../core/theme.dart';

/// The size of one page dot (kit "_Page Indicator" Type).
enum IosPageDot { normal, adjacent, overflow, hidden }

/// Which dots an [IosPageControl] shows for [count] pages with [current] selected (kit Pages = 1-6 · 7 · 8+):
/// up to 6 pages all normal; from 7 pages at most 5 normal dots around the current page (6 at the first or last),
/// then one smaller "adjacent" dot (6 pt) and one tiny "overflow" dot (4 pt) on each side where more pages follow.
List<IosPageDot> iosPageControlDots(int count, int current) {
  if (count <= 6) return List.filled(count, IosPageDot.normal);
  var start = (current - 2).clamp(0, count - 5);
  var end = start + 4;
  if (start == 0) {
    end = 5;
  } else if (end == count - 1) {
    start = count - 6;
  }
  return List.generate(count, (i) {
    if (i >= start && i <= end) return IosPageDot.normal;
    if (i == start - 1 || i == end + 1) return IosPageDot.adjacent;
    if (i == start - 2 || i == end + 2) return IosPageDot.overflow;
    return IosPageDot.hidden;
  });
}

/// An iOS page control (kit page "Page Controls"): a capsule of ultra-thin material with one 8 pt dot per page,
/// the current one in Labels/Primary, the others Labels/Tertiary. Put it centred under (or over) a PageView.
///
///     IosPageControl(count: 5, currentPage: page, onPageChanged: (i) => controller.animateToPage(i,
///         duration: const Duration(milliseconds: 300), curve: Curves.easeOut))
/// Pages are 0-based. A tap on the left / right half moves one page back / forward, like UIPageControl.
/// [onPageChanged] null = an indicator only (no taps). 7+ pages: the edge dots shrink.
class IosPageControl extends StatelessWidget {
  const IosPageControl({
    super.key,
    required this.count,
    required this.currentPage,
    this.onPageChanged,
    this.semanticLabel,
  });

  final int count;
  final int currentPage;
  final ValueChanged<int>? onPageChanged;

  /// Accessible name. Default "Pages" (the value reads "Page 3 of 8").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final current = currentPage.clamp(0, count > 0 ? count - 1 : 0);
    final kinds = iosPageControlDots(count, current);
    final dots = <Widget>[];
    for (var i = 0; i < count; i++) {
      final k = kinds[i];
      if (k == IosPageDot.hidden) continue;
      if (dots.isNotEmpty) dots.add(const SizedBox(width: 8));
      final d = switch (k) {
        IosPageDot.adjacent => 6.0,
        IosPageDot.overflow => 4.0,
        _ => 8.0,
      };
      final box = k == IosPageDot.overflow ? 6.0 : 8.0;
      dots.add(
        SizedBox(
          width: box,
          height: 8,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: d,
              height: d,
              decoration: BoxDecoration(shape: BoxShape.circle, color: i == current ? c.labelPrimary : c.labelTertiary),
            ),
          ),
        ),
      );
    }
    // Kit "_Materials / Ultrathin": white 7% (+3% colour dodge) Light, black 2% Dark, over a 100 background blur.
    final fill = theme.isDark ? const Color(0x05000000) : const Color(0x1AFFFFFF);
    final capsule = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 50, sigmaY: 50, tileMode: TileMode.clamp),
        child: ColoredBox(
          color: fill,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: dots),
          ),
        ),
      ),
    );
    // Like UIPageControl: a tap left of the middle goes back one page, right of it forward one page.
    Widget control = SizedBox(height: 44, child: Center(child: capsule));
    if (onPageChanged != null) {
      control = LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (e) {
            final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
            final forward = (e.localPosition.dx > constraints.maxWidth / 2) != rtl;
            final next = (current + (forward ? 1 : -1)).clamp(0, count - 1);
            if (next != current) onPageChanged!(next);
          },
          child: SizedBox(height: 44, child: Center(child: capsule)),
        ),
      );
    }
    return Semantics(
      container: true,
      label: semanticLabel ?? 'Pages',
      value: 'Page ${current + 1} of $count',
      increasedValue: current + 1 < count ? 'Page ${current + 2} of $count' : null,
      decreasedValue: current > 0 ? 'Page $current of $count' : null,
      onIncrease: onPageChanged != null && current + 1 < count ? () => onPageChanged!(current + 1) : null,
      onDecrease: onPageChanged != null && current > 0 ? () => onPageChanged!(current - 1) : null,
      child: control,
    );
  }
}
