/// The app mark renders from the real artwork.
///
/// It previously existed twice as a hand-drawn letter "M", while the actual
/// logo asset sat in the repo unused. These tests pin that the widget loads the
/// asset and survives both sizes it is used at — a 28px toolbar icon and a 96px
/// login mark.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mario/ui/widgets/mario_logo.dart';

void main() {
  testWidgets('renders the logo asset, not a drawn placeholder',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: MarioLogo())),
    ));
    await tester.pump();

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('honours its size at both sizes the app uses', (tester) async {
    for (final size in [28.0, 96.0]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: MarioLogo(size: size))),
      ));
      await tester.pump();
      expect(tester.getSize(find.byType(MarioLogo)), Size(size, size));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the shadowed variant still renders and keeps its size',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: MarioLogo(size: 96, shadow: true))),
    ));
    await tester.pump();
    expect(tester.getSize(find.byType(MarioLogo)), const Size(96, 96));
    expect(tester.takeException(), isNull);
  });

  test('the asset path is declared in pubspec', () {
    // pubspec bundles the assets/logo/ directory; if the constant ever points
    // outside it, the widget throws only at runtime.
    expect(kMarioLogoAsset, startsWith('assets/logo/'));
  });
}
