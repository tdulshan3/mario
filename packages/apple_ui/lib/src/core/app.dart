import 'package:flutter/cupertino.dart';

import 'ios_tokens.dart';
import 'theme.dart';
import 'typography.dart';

/// The root of an apple_ui app: use it INSTEAD of MaterialApp / CupertinoApp.
/// It sets the look (iOS/iPadOS or macOS), Light/Dark Mode, the accent colour, Dynamic Type and the fonts
/// (SF Pro on Apple platforms, Inter elsewhere) for every widget below.
///
///     void main() => runApp(const AppleApp(title: 'Notes', home: NotesHome()));
///     AppleApp(look: AppleLook.macos, home: ...)            // force the Mac look (desktop apps)
///     AppleApp(themeMode: AppleThemeMode.dark, accent: IosColors.light.green, home: ...)
class AppleApp extends StatelessWidget {
  const AppleApp({
    super.key,
    this.home,
    this.routes = const <String, WidgetBuilder>{},
    this.initialRoute,
    this.onGenerateRoute,
    this.navigatorKey,
    this.title = '',
    this.look = AppleLook.auto,
    this.themeMode = AppleThemeMode.system,
    this.accent,
    this.dynamicType,
    this.builder,
    this.debugShowCheckedModeBanner = false,
  });

  final Widget? home;
  final Map<String, WidgetBuilder> routes;
  final String? initialRoute;
  final RouteFactory? onGenerateRoute;
  final GlobalKey<NavigatorState>? navigatorKey;
  final String title;

  /// [AppleLook.auto] (default): macOS look on macOS/Windows/Linux, iOS look on iOS/Android/web.
  final AppleLook look;
  final AppleThemeMode themeMode;

  /// App tint colour. Null = system blue.
  final Color? accent;

  /// Force a Dynamic Type size (iOS look). Null = follow the device text size setting.
  final IosDynamicType? dynamicType;
  final TransitionBuilder? builder;
  final bool debugShowCheckedModeBanner;

  @override
  Widget build(BuildContext context) {
    final resolved = resolveLook(look);
    final fixed = switch (themeMode) {
      AppleThemeMode.light => Brightness.light,
      AppleThemeMode.dark => Brightness.dark,
      AppleThemeMode.system => null,
    };
    return CupertinoApp(
      title: title,
      home: home,
      routes: routes,
      initialRoute: initialRoute,
      onGenerateRoute: onGenerateRoute,
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: debugShowCheckedModeBanner,
      theme: CupertinoThemeData(brightness: fixed, primaryColor: accent),
      builder: (context, child) {
        final brightness = fixed ?? MediaQuery.platformBrightnessOf(context);
        final scale = MediaQuery.textScalerOf(context).scale(17) / 17;
        final data = AppleThemeData(
          look: resolved,
          brightness: brightness,
          accent: accent,
          dynamicType: resolved == AppleLook.ios ? (dynamicType ?? dynamicTypeForScale(scale)) : null,
        );
        Widget content = AppleTheme(
          data: data,
          child: Builder(builder: (context) {
            final isMac = data.isMac;
            final text = isMac ? MacTypography.of(context).body : IosTypography.of(context).body;
            return DefaultTextStyle(
              style: text,
              child: IconTheme(
                data: IconThemeData(color: data.accentColor, size: isMac ? 16 : 22),
                child: child ?? const SizedBox.shrink(),
              ),
            );
          }),
        );
        // Text sizes come from Dynamic Type (exact Apple sizes), so Flutter must not scale them a second time.
        content = MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling), child: content);
        return builder != null ? builder!(context, content) : content;
      },
    );
  }
}
