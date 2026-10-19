/// Global search on the desktop builds: the Spotlight-style panel.
///
/// Widget tests run as Android, which draws the Material palette; these
/// switch the platform to Linux, which is what opens the macOS panel. The
/// last test stays on Android to pin that the palette pre-fills there too.
library;

import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/models/note_page.dart';
import 'package:mario/core/models/notebook.dart';
import 'package:mario/core/models/section.dart';
import 'package:mario/features/search/global_search.dart';
import 'package:mario/features/search/mac_global_search.dart';
import 'package:mario/features/shell/shell_state.dart';
import 'package:mario/ui/mac/mac_look.dart';
import 'package:mario/ui/mac/mac_theme.dart';
import 'package:mario/ui/theme.dart';

Notebook _nb(String id, String name) => Notebook(
      id: id,
      name: name,
      ownerId: 'u1',
      colorIndex: 1,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

NotePage _page(String id, String nb, String s, String title, int order) =>
    NotePage(
      id: id,
      sectionId: s,
      notebookId: nb,
      title: title,
      order: order,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

final _notebooks = [_nb('n1', 'Physics'), _nb('n2', 'Biology')];

const _sections = {
  'n1': [
    Section(
        id: 's1', notebookId: 'n1', name: 'Mechanics', colorIndex: 0, order: 0),
  ],
  'n2': [
    Section(id: 's2', notebookId: 'n2', name: 'Cells', colorIndex: 0, order: 0),
    Section(
        id: 's3', notebookId: 'n2', name: 'Genetics', colorIndex: 0, order: 1),
  ],
};

/// Genetics holds thirty pages, more than the panel shows at once, so the
/// highlight has somewhere to scroll to.
final _pages = {
  's1': [_page('p1', 'n1', 's1', 'Torque', 0)],
  's2': [
    _page('p2', 'n2', 's2', 'Photosynthesis', 0),
    _page('p3', 'n2', 's2', 'Mitosis', 1),
  ],
  's3': [
    for (var i = 1; i <= 30; i++)
      _page('g$i', 'n2', 's3', 'Gene ${'$i'.padLeft(2, '0')}', i),
  ],
};

/// Widget tests run as Android; Linux is what draws the macOS look.
final _linux = TargetPlatformVariant.only(TargetPlatform.linux);

const _home = Key('home');

/// An empty window, as the app builds it, with the pages' streams open —
/// the search reads their current values, which the shell keeps open in the
/// app.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  bool mac = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: [
    notebooksStreamProvider.overrideWith((ref) => Stream.value(_notebooks)),
    sectionsStreamProvider
        .overrideWith((ref, id) => Stream.value(_sections[id] ?? const [])),
    pagesStreamProvider.overrideWith(
        (ref, key) => Stream.value(_pages[key.sectionId] ?? const [])),
  ]);
  addTearDown(container.dispose);
  container.listen(notebooksStreamProvider, (_, __) {});
  for (final MapEntry(key: nb, value: sections) in _sections.entries) {
    container.listen(sectionsStreamProvider(nb), (_, __) {});
    for (final s in sections) {
      container.listen(
          pagesStreamProvider((notebookId: nb, sectionId: s.id)), (_, __) {});
    }
  }

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: mac ? macMaterialTheme(Brightness.light) : MarioTheme.light(),
      builder: mac ? (context, child) => MacLookScope(child: child!) : null,
      home: const SizedBox.expand(key: _home),
    ),
  ));
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
  return container;
}

/// Opens the search the way the shortcut and the toolbar do, past its fade.
Future<void> _open(WidgetTester tester, {String initialQuery = ''}) async {
  showGlobalSearch(tester.element(find.byKey(_home)),
      initialQuery: initialQuery);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

/// Lets a close finish, and the overlay scroll bars' fade timer run out.
/// The first frame starts the close animation's clock; the long one runs it
/// out; the last removes the route.
Future<void> _finish(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  await tester.pump();
}

final _panel = find.byType(MacGlobalSearchPanel);

final _field = find.descendant(of: _panel, matching: find.byType(EditableText));

String _fieldText(WidgetTester tester) =>
    tester.widget<EditableText>(_field).controller.text;

MacList _list(WidgetTester tester, String label) => tester.widget<MacList>(
    find.byWidgetPredicate((w) => w is MacList && w.semanticLabel == label));

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

void main() {
  testWidgets('it opens as a Spotlight panel, not the Material palette',
      (tester) async {
    await _pump(tester);
    await _open(tester);

    expect(_panel, findsOneWidget);
    expect(find.descendant(of: _panel, matching: find.byType(MacGlass)),
        findsOneWidget);
    expect(find.descendant(of: _panel, matching: find.byType(MacSearchField)),
        findsOneWidget);
    expect(tester.widget<MacSearchField>(find.byType(MacSearchField)).size,
        MacControlSize.xl);
    expect(find.text('Search by Title'), findsOneWidget);
    // No Material control inside it.
    for (final type in [TextField, InkWell, ListTile, Material]) {
      expect(find.descendant(of: _panel, matching: find.byType(type)),
          findsNothing,
          reason: '$type');
    }
    // The field has the keyboard at once.
    await tester.enterText(_field, 'torque');
    await tester.pump();
    expect(find.text('Torque'), findsOneWidget);
    expect(find.text('Physics › Mechanics'), findsOneWidget);
    await _finish(tester);
  }, variant: _linux);

  for (final size in const [Size(800, 600), Size(1280, 800)]) {
    testWidgets('it fits a ${size.width.round()}×${size.height.round()} window',
        (tester) async {
      await _pump(tester, size: size);
      await _open(tester);
      expect(tester.takeException(), isNull, reason: 'empty');

      // Every page matches "e": a list longer than the panel.
      await tester.enterText(_field, 'e');
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'results');
      final panel = tester.getRect(
          find.descendant(of: _panel, matching: find.byType(MacGlass)));
      expect((Offset.zero & size).contains(panel.topLeft), isTrue);
      expect((Offset.zero & size).contains(panel.bottomRight), isTrue);
      // In the upper part of the window, centred.
      expect(panel.top, lessThan(size.height / 4));
      expect(panel.center.dx, closeTo(size.width / 2, 1));

      await tester.enterText(_field, 'zzz');
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'no results');
      expect(find.text('No Results'), findsOneWidget);
      await _finish(tester);
    }, variant: _linux);
  }

  testWidgets('the toolbar text arrives already typed', (tester) async {
    await _pump(tester);
    await _open(tester, initialQuery: 'photo');

    expect(_fieldText(tester), 'photo');
    expect(find.text('Photosynthesis'), findsOneWidget);
    expect(find.text('Biology › Cells'), findsOneWidget);
    // The first match is highlighted, ready for Return.
    expect(_list(tester, 'Pages').selection, {0});
    await _finish(tester);
  }, variant: _linux);

  testWidgets('↑ ↓ move round the ends and Return opens the page',
      (tester) async {
    final container = await _pump(tester);
    await _open(tester, initialQuery: 'cells');
    expect(find.text('Photosynthesis'), findsOneWidget);
    expect(find.text('Mitosis'), findsOneWidget);
    expect(_list(tester, 'Pages').selection, {0});

    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(_list(tester, 'Pages').selection, {1});
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(_list(tester, 'Pages').selection, {0}, reason: 'round the end');
    await _key(tester, LogicalKeyboardKey.arrowUp);
    expect(_list(tester, 'Pages').selection, {1}, reason: 'round the start');

    await _key(tester, LogicalKeyboardKey.enter);
    await _finish(tester);
    expect(_panel, findsNothing);
    final s = container.read(selectionProvider);
    expect(s.pageId, 'p3');
    expect(s.sectionId, 's2');
    expect(s.notebookId, 'n2');
  }, variant: _linux);

  testWidgets('a click highlights, a double-click opens', (tester) async {
    final container = await _pump(tester);
    await _open(tester, initialQuery: 'cells');

    await tester.tap(find.text('Mitosis'));
    await tester.pump();
    expect(_list(tester, 'Pages').selection, {1});
    expect(_panel, findsOneWidget);
    // The field kept the keyboard: typing still reaches it.
    expect(tester.widget<EditableText>(_field).focusNode.hasFocus, isTrue);

    // Another row, so neither click pairs with the one above.
    await tester.tap(find.text('Photosynthesis'));
    await tester.tap(find.text('Photosynthesis'));
    await _finish(tester);
    expect(_panel, findsNothing);
    expect(container.read(selectionProvider).pageId, 'p2');
  }, variant: _linux);

  testWidgets('Escape empties the field first, then closes', (tester) async {
    await _pump(tester);
    await _open(tester, initialQuery: 'cells');

    await _key(tester, LogicalKeyboardKey.escape);
    expect(_panel, findsOneWidget);
    expect(_fieldText(tester), '');
    expect(find.text('Search by Title'), findsOneWidget);

    await _key(tester, LogicalKeyboardKey.escape);
    await _finish(tester);
    expect(_panel, findsNothing);
  }, variant: _linux);

  testWidgets('the highlight stays in view as the keys move it',
      (tester) async {
    await _pump(tester, size: const Size(800, 600));
    await _open(tester, initialQuery: 'gene');
    final view = tester.getRect(
        find.descendant(of: _panel, matching: find.byType(MacScrollView)));

    for (var i = 0; i < 25; i++) {
      await _key(tester, LogicalKeyboardKey.arrowDown);
    }
    await tester.pump();
    expect(_list(tester, 'Pages').selection, {25});
    final row = tester.getRect(find.text('Gene 26'));
    expect(view.top <= row.top && row.bottom <= view.bottom, isTrue,
        reason: '$row in $view');

    // Round the end, back to the top of the list.
    for (var i = 0; i < 5; i++) {
      await _key(tester, LogicalKeyboardKey.arrowDown);
    }
    await tester.pump();
    expect(_list(tester, 'Pages').selection, {0});
    final first = tester.getRect(find.text('Gene 01'));
    expect(view.top <= first.top && first.bottom <= view.bottom, isTrue);
    await _finish(tester);
  }, variant: _linux);

  testWidgets('with a section open, a new title can become a page',
      (tester) async {
    final container = await _pump(tester);
    container
        .read(selectionProvider.notifier)
        .selectSection('s2', notebookId: 'n2');
    await _open(tester, initialQuery: 'Osmosis');

    // No page matches, but the action is a result, as in the palette.
    expect(find.text('No Results'), findsNothing);
    expect(find.text('New Page “Osmosis”'), findsOneWidget);
    expect(find.text('In Biology › Cells'), findsOneWidget);
    expect(_list(tester, 'Actions').selection, {0});
    await _finish(tester);
  }, variant: _linux);

  testWidgets('the Material palette is pre-filled too', (tester) async {
    expect(useMacLook, isFalse);
    await _pump(tester, mac: false);
    await _open(tester, initialQuery: 'cells');

    expect(_panel, findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'cells');
    expect(find.text('Photosynthesis'), findsOneWidget);
    expect(find.text('Mitosis'), findsOneWidget);
  });
}
