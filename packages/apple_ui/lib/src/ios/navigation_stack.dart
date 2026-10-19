import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/widgets.dart';

/// A navigation stack (SwiftUI `NavigationStack`): screens pushed inside it slide in from the right, the back button
/// and a swipe from the left edge go back, and the Android back button pops it. Give EVERY tab of an [IosTabView]
/// (and every column of a split view on iPhone) its own stack, so each keeps its place when you switch.
/// Sheets, alerts and action sheets still cover the whole app (they open on the root navigator).
///
///     IosTabView(selectedIndex: tab, onChanged: (i) => setState(() => tab = i), tabs: tabs, pageBuilder: (context, i) =>
///         IosNavigationStack(active: i == tab, root: [const LibraryScreen(), const SettingsScreen()][i]))
///
///     // inside LibraryScreen: open a detail screen
///     IosListRow(title: item.title, onTap: () => pushIosScreen(context, ItemScreen(item)))
class IosNavigationStack extends StatefulWidget {
  const IosNavigationStack({super.key, required this.root, this.active = true, this.navigatorKey});

  /// The first screen (usually an `IosBarScaffold` with a large-title `IosNavigationBar`).
  final Widget root;

  /// True for the stack on screen (the selected tab): only it handles the Android back button.
  final bool active;

  /// Optional key to push or pop from outside (`navigatorKey.currentState!.popUntil((r) => r.isFirst)`).
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<IosNavigationStack> createState() => _IosNavigationStackState();
}

class _IosNavigationStackState extends State<IosNavigationStack> {
  final _ownKey = GlobalKey<NavigatorState>();
  GlobalKey<NavigatorState> get _key => widget.navigatorKey ?? _ownKey;

  @override
  Widget build(BuildContext context) {
    return NavigatorPopHandler(
      enabled: widget.active,
      onPopWithResult: (_) => _key.currentState?.maybePop(),
      // A semantics container: screen readers keep seeing the sidebar and bars next to this stack
      // (without it, a route's barrier hides them).
      child: Semantics(
        container: true,
        child: Navigator(
          key: _key,
          onGenerateRoute: (settings) => CupertinoPageRoute<void>(settings: settings, builder: (_) => widget.root),
        ),
      ),
    );
  }
}

/// Pushes [screen] on the nearest [IosNavigationStack] with the iOS slide-in (swipe from the left edge goes back).
/// The pushed screen shows a back button: `IosNavigationBar(leading: [IosBarButton.back(onPressed: () => Navigator.pop(context))])`.
Future<T?> pushIosScreen<T>(BuildContext context, Widget screen) =>
    Navigator.of(context).push<T>(CupertinoPageRoute<T>(builder: (_) => screen));
