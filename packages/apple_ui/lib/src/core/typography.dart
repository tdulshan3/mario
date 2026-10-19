import 'package:flutter/widgets.dart';

import 'ios_tokens.dart';
import 'macos_tokens.dart';
import 'theme.dart';

/// Font family for a text size: SF Pro on iOS and macOS (Display from 20 pt, like Apple), Inter elsewhere.
/// SF Pro may only be used on Apple platforms (Apple's font licence), so Android, Windows, Linux and the web use Inter.
TextStyle appleFont({required double size}) {
  if (isAppleSystemFontAvailable) {
    return TextStyle(fontFamily: size >= 20 ? 'CupertinoSystemDisplay' : 'CupertinoSystemText');
  }
  return const TextStyle(fontFamily: 'Inter', package: 'apple_ui');
}

/// The 11 iOS text styles (kit "Text Styles and Dynamic Type").
enum IosTextStyle { largeTitle, title1, title2, title3, headline, body, callout, subheadline, footnote, caption1, caption2 }

IosTextSpec _iosSpec(IosTextStyle s) => switch (s) {
      IosTextStyle.largeTitle => IosTextSpecs.largeTitle,
      IosTextStyle.title1 => IosTextSpecs.title1,
      IosTextStyle.title2 => IosTextSpecs.title2,
      IosTextStyle.title3 => IosTextSpecs.title3,
      IosTextStyle.headline => IosTextSpecs.headline,
      IosTextStyle.body => IosTextSpecs.body,
      IosTextStyle.callout => IosTextSpecs.callout,
      IosTextStyle.subheadline => IosTextSpecs.subheadline,
      IosTextStyle.footnote => IosTextSpecs.footnote,
      IosTextStyle.caption1 => IosTextSpecs.caption1,
      IosTextStyle.caption2 => IosTextSpecs.caption2,
    };

/// iOS text styles at the current Dynamic Type size, in label-primary colour.
///
///     final t = IosTypography.of(context);
///     Text('Settings', style: t.largeTitleEmphasized);
///     Text('Detail', style: t.body.copyWith(color: context.iosColors.labelSecondary));
class IosTypography {
  IosTypography._(this.dynamicType, this.color);

  /// The Dynamic Type size in use.
  final IosDynamicType dynamicType;
  final Color color;

  static IosTypography of(BuildContext context) {
    final theme = AppleTheme.of(context);
    return IosTypography._(theme.dynamicType ?? IosDynamicType.large, theme.ios.labelPrimary);
  }

  /// One style. [emphasized] = the bold version Apple defines for that style.
  TextStyle style(IosTextStyle s, {bool emphasized = false}) {
    final spec = _iosSpec(s);
    final i = dynamicType.index;
    final size = spec.dynamicSizes[i];
    final lineHeight = spec.dynamicLineHeights[i];
    return appleFont(size: size).copyWith(
      fontSize: size,
      height: lineHeight / size,
      letterSpacing: spec.tracking,
      fontWeight: emphasized ? spec.emphasizedWeight : spec.weight,
      color: color,
      leadingDistribution: TextLeadingDistribution.even,
      decoration: TextDecoration.none,
    );
  }

  TextStyle get largeTitle => style(IosTextStyle.largeTitle);
  TextStyle get largeTitleEmphasized => style(IosTextStyle.largeTitle, emphasized: true);
  TextStyle get title1 => style(IosTextStyle.title1);
  TextStyle get title1Emphasized => style(IosTextStyle.title1, emphasized: true);
  TextStyle get title2 => style(IosTextStyle.title2);
  TextStyle get title2Emphasized => style(IosTextStyle.title2, emphasized: true);
  TextStyle get title3 => style(IosTextStyle.title3);
  TextStyle get title3Emphasized => style(IosTextStyle.title3, emphasized: true);
  TextStyle get headline => style(IosTextStyle.headline);
  TextStyle get body => style(IosTextStyle.body);
  TextStyle get bodyEmphasized => style(IosTextStyle.body, emphasized: true);
  TextStyle get callout => style(IosTextStyle.callout);
  TextStyle get calloutEmphasized => style(IosTextStyle.callout, emphasized: true);
  TextStyle get subheadline => style(IosTextStyle.subheadline);
  TextStyle get subheadlineEmphasized => style(IosTextStyle.subheadline, emphasized: true);
  TextStyle get footnote => style(IosTextStyle.footnote);
  TextStyle get footnoteEmphasized => style(IosTextStyle.footnote, emphasized: true);
  TextStyle get caption1 => style(IosTextStyle.caption1);
  TextStyle get caption1Emphasized => style(IosTextStyle.caption1, emphasized: true);
  TextStyle get caption2 => style(IosTextStyle.caption2);
  TextStyle get caption2Emphasized => style(IosTextStyle.caption2, emphasized: true);
}

/// The nearest Dynamic Type size for Flutter's text scale factor (the device's text size setting).
IosDynamicType dynamicTypeForScale(double scale) {
  final body = IosTextSpecs.body.dynamicSizes;
  final wanted = 17 * scale;
  var best = IosDynamicType.large;
  var bestDiff = double.infinity;
  for (final t in IosDynamicType.values) {
    final d = (body[t.index] - wanted).abs();
    if (d < bestDiff) {
      bestDiff = d;
      best = t;
    }
  }
  return best;
}

/// The macOS text styles (kit "Text Styles"): 13 px body. macOS has no Dynamic Type.
///
///     Text('Name', style: MacTypography.of(context).body);
class MacTypography {
  MacTypography._(this.color);
  final Color color;

  static MacTypography of(BuildContext context) => MacTypography._(AppleTheme.of(context).mac.labelPrimary);

  TextStyle _style(MacTextSpec spec, bool emphasized) => appleFont(size: spec.size).copyWith(
        fontSize: spec.size,
        height: spec.lineHeight / spec.size,
        letterSpacing: spec.tracking,
        fontWeight: emphasized ? spec.emphasizedWeight : spec.weight,
        color: color,
        leadingDistribution: TextLeadingDistribution.even,
        decoration: TextDecoration.none,
      );

  TextStyle get largeTitle => _style(MacTextSpecs.largeTitle, false);
  TextStyle get title1 => _style(MacTextSpecs.title1, false);
  TextStyle get title2 => _style(MacTextSpecs.title2, false);
  TextStyle get title3 => _style(MacTextSpecs.title3, false);
  TextStyle get headline => _style(MacTextSpecs.headline, false);
  TextStyle get body => _style(MacTextSpecs.body, false);
  TextStyle get bodyEmphasized => _style(MacTextSpecs.body, true);
  TextStyle get callout => _style(MacTextSpecs.callout, false);
  TextStyle get subheadline => _style(MacTextSpecs.subheadline, false);
  TextStyle get footnote => _style(MacTextSpecs.footnote, false);
  TextStyle get caption1 => _style(MacTextSpecs.caption1, false);
  TextStyle get caption2 => _style(MacTextSpecs.caption2, false);

  /// Any style in its emphasized (bold) version.
  TextStyle emphasized(MacTextSpec spec) => _style(spec, true);
}
