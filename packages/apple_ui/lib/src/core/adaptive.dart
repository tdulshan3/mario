import 'package:flutter/widgets.dart';

import 'ios_tokens.dart';

/// iPhone-like (compact) or iPad-like (regular) layout. Same rule as the web part of the skill:
/// regular = at least 744 wide AND 600 tall (iPad in any orientation, wide windows); everything else is compact
/// (iPhones in portrait and landscape, narrow Split View / Slide Over windows).
enum IosSizeClass { compact, regular }

const double kIosRegularMinWidth = 744;
const double kIosRegularMinHeight = 600;

class IosLayout {
  IosLayout._();

  static IosSizeClass sizeClassOf(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width >= kIosRegularMinWidth && size.height >= kIosRegularMinHeight ? IosSizeClass.regular : IosSizeClass.compact;
  }

  static bool isRegular(BuildContext context) => sizeClassOf(context) == IosSizeClass.regular;

  /// Kit dimensions (margins, sheet radii, menu metrics…) for the current size class.
  static IosDimensions dimensionsOf(BuildContext context) => isRegular(context) ? IosDimensions.ipad : IosDimensions.iphone;
}

/// Builds a different layout for iPhone (compact) and iPad (regular) sizes.
///
///     IosAdaptive(compact: (context) => PhoneLayout(), regular: (context) => PadLayout())
class IosAdaptive extends StatelessWidget {
  const IosAdaptive({super.key, required this.compact, required this.regular});
  final WidgetBuilder compact;
  final WidgetBuilder regular;

  @override
  Widget build(BuildContext context) => IosLayout.isRegular(context) ? regular(context) : compact(context);
}
