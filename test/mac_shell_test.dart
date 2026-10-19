/// The desktop window: the macOS look's shell, sidebar and page browser.
///
/// Widget tests run as Android, which draws the Material shell; these switch
/// the platform to Linux, which is what puts `MacShellScreen` on screen.
library;

import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/models/note_page.dart';
import 'package:mario/core/models/notebook.dart';
import 'package:mario/core/models/section.dart';
import 'package:mario/core/services/auth_service.dart';
import 'package:mario/features/auth/auth_notifier.dart';
import 'package:mario/features/shell/mac/mac_shell.dart';
import 'package:mario/features/shell/mac/mac_sidebar.dart';
import 'package:mario/features/shell/shell_screen.dart';
import 'package:mario/features/shell/shell_state.dart';
import 'package:mario/ui/mac/mac_look.dart';
import 'package:mario/ui/mac/mac_theme.dart';
import 'package:mario/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime.now();

Notebook _nb(String id, String name) => Notebook(
      id: id,
      name: name,
      ownerId: 'u1',
      colorIndex: 1,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

NotePage _page(String id, String nb, String s, String title, Duration age) =>
    NotePage(
      id: id,
      sectionId: s,
      notebookId: nb,
      title: title,
      order: 0,
      createdAt: DateTime(2026),
      updatedAt: _now.subtract(age),
    );

final _notebooks = [_nb('n1', 'Physics'), _nb('n2', 'Biology')];

final _sections = {
  'n1': const [
    Section(
        id: 's1', notebookId: 'n1', name: 'Mechanics', colorIndex: 0, order: 0),
  ],
  'n2': const [
    Section(id: 's2', notebookId: 'n2', name: 'Cells', colorIndex: 0, order: 0),
    Section(
        id: 's3', notebookId: 'n2', name: 'Genetics', colorIndex: 0, order: 1),
  ],
};

final _pages = {
  's1': [_page('p1', 'n1', 's1', 'Torque', const Duration(minutes: 5))],
  's2': [
    _page('p2', 'n2', 's2', 'Photosynthesis', const Duration(days: 3)),
    _page('p3', 'n2', 's2', 'Mitosis', const Duration(days: 4)),
  ],
  's3': <NotePage>[],
};

const _user =
    MarioUser(uid: 'u1', email: 'sam@example.com', displayName: 'Sam');

/// Widget tests run as Android; Linux is what draws the macOS look.
final _linux = TargetPlatformVariant.only(TargetPlatform.linux);

/// The shell (or [child]) as the desktop app builds it.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Widget child = const ShellScreen(),
  Size size = const Size(1280, 800),
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: [
    authStateProvider.overrideWith((ref) => Stream.value(_user)),
    notebooksStreamProvider.overrideWith((ref) => Stream.value(_notebooks)),
    sectionsStreamProvider
        .overrideWith((ref, id) => Stream.value(_sections[id] ?? const [])),
    pagesStreamProvider.overrideWith(
        (ref, key) => Stream.value(_pages[key.sectionId] ?? const [])),
  ]);
  addTearDown(container.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: macMaterialTheme(brightness),
      builder: (context, child) => MacLookScope(child: child!),
      home: child,
    ),
  ));
  await _settle(tester);
  return container;
}

/// Lets the stream overrides land, level by level: notebooks, then their
/// sections, then those sections' pages.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}

/// The toolbar's search field.
final _search = find.descendant(
    of: find.byType(MacSearchField), matching: find.byType(EditableText));

/// [text] in the sidebar, not in the page table beside it.
Finder _side(String text) =>
    find.descendant(of: find.byType(MacNavSidebar), matching: find.text(text));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('only the native desktop builds take the macOS look', () {
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(useMacLook, isFalse);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(useMacLook, isFalse);
      for (final p in [
        TargetPlatform.linux,
        TargetPlatform.windows,
        TargetPlatform.macOS,
      ]) {
        debugDefaultTargetPlatformOverride = p;
        expect(useMacLook, isTrue, reason: '$p');
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('the four grounds fold onto Light, Dark and Auto', () {
    expect(macThemeModeFor(MarioThemeMode.system), ThemeMode.system);
    expect(macThemeModeFor(MarioThemeMode.light), ThemeMode.light);
    expect(macThemeModeFor(MarioThemeMode.white), ThemeMode.light);
    expect(macThemeModeFor(MarioThemeMode.night), ThemeMode.dark);
    expect(macThemeModeFor(MarioThemeMode.black), ThemeMode.dark);
  });

  test('the Material theme carries the macOS tokens', () {
    final light = macMaterialTheme(Brightness.light);
    final dark = macMaterialTheme(Brightness.dark);
    expect(light.colorScheme.primary, MacColors.light.accentBlue);
    expect(dark.colorScheme.primary, MacColors.dark.accentBlue);
    expect(light.scaffoldBackgroundColor, MacColors.light.windowBg);
    expect(dark.scaffoldBackgroundColor, MacColors.dark.windowBg);
    final t = light.extension<MarioTokens>()!;
    expect(t.ink, MacColors.light.labelPrimary);
    expect(t.line, MacColors.light.separator);
    expect(t.paper, MacColors.light.windowBg);
    expect(dark.extension<MarioTokens>()!.isDark, isTrue);
  });

  testWidgets('the desktop shell is the macOS window', (tester) async {
    await _pump(tester);
    expect(find.byType(MacShellScreen), findsOneWidget);
    expect(find.byType(MacWindow), findsOneWidget);
    expect(find.byType(MacNavSidebar), findsOneWidget);
    // Recents is where the app opens: the title, and the table of pages.
    expect(find.text('Recents'), findsWidgets);
    expect(find.text('3 pages'), findsOneWidget);
    expect(find.text('Torque'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Earlier'), findsOneWidget);
  }, variant: _linux);

  for (final brightness in Brightness.values) {
    testWidgets('the window fits every size on ${brightness.name}',
        (tester) async {
      for (final size in const [
        Size(800, 600),
        Size(1280, 800),
        Size(1920, 1080),
      ]) {
        await _pump(tester, size: size, brightness: brightness);
        expect(tester.takeException(), isNull, reason: 'at $size');
      }
      // The overlay scroll bars fade on a timer; let it run out.
      await tester.pump(const Duration(seconds: 3));
    }, variant: _linux);
  }

  testWidgets('opening a notebook shows its sections, and a section its pages',
      (tester) async {
    final container = await _pump(tester);
    expect(_side('Cells'), findsNothing);

    await tester.tap(_side('Biology'));
    await _settle(tester);
    expect(_side('Cells'), findsOneWidget);
    expect(_side('Genetics'), findsOneWidget);
    expect(container.read(selectionProvider).notebookId, 'n2');
    expect(container.read(selectionProvider).home, isFalse);

    await tester.tap(_side('Cells'));
    await _settle(tester);
    final s = container.read(selectionProvider);
    expect(s.sectionId, 's2');
    expect(s.pageId, isNull);
    // The section's pages, in the sidebar and in the browser beside it.
    expect(find.text('Photosynthesis'), findsNWidgets(2));
    expect(find.text('Mitosis'), findsNWidgets(2));
    expect(_side('Photosynthesis'), findsOneWidget);

    // An empty section says so rather than showing nothing.
    await tester.tap(_side('Genetics'));
    await _settle(tester);
    expect(find.text('No Pages'), findsWidgets);
  }, variant: _linux);

  testWidgets('a section in another notebook carries its notebook along',
      (tester) async {
    final container = await _pump(tester);
    await tester.tap(_side('Physics'));
    await _settle(tester);
    await tester.tap(_side('Biology'));
    await _settle(tester);
    await tester.tap(_side('Mechanics'));
    await tester.pump();
    final s = container.read(selectionProvider);
    expect(s.sectionId, 's1');
    expect(s.notebookId, 'n1');
  }, variant: _linux);

  testWidgets('the toolbar search narrows the sidebar', (tester) async {
    await _pump(tester);
    // Typing reaches the field at all: apple_ui's toolbar search field used
    // to rebuild its text field on focus and drop the input (see the Mario
    // patch in packages/apple_ui/lib/src/macos/search_fields.dart).
    await tester.enterText(_search, 'mito');
    await _settle(tester);
    // The match, with the folders that lead to it opened around it.
    expect(_side('Biology'), findsOneWidget);
    expect(_side('Cells'), findsOneWidget);
    expect(_side('Mitosis'), findsOneWidget);
    expect(_side('Photosynthesis'), findsNothing);
    expect(_side('Physics'), findsNothing);
    expect(_side('Genetics'), findsNothing);

    await tester.enterText(_search, 'zzz');
    await tester.pump();
    expect(find.text('No Results'), findsOneWidget);
  }, variant: _linux);

  testWidgets('New Page waits for a section', (tester) async {
    final container = await _pump(tester);
    MacToolbarButton newPage() =>
        tester.widget<MacToolbarButton>(find.byWidgetPredicate((w) =>
            w is MacToolbarButton && w.icon == AppleIcons.squareAndPencil));
    expect(newPage().onPressed, isNull);

    container
        .read(selectionProvider.notifier)
        .selectSection('s2', notebookId: 'n2');
    await _settle(tester);
    expect(newPage().onPressed, isNotNull);
  }, variant: _linux);

  testWidgets('Linux leaves the window buttons to its own title bar',
      (tester) async {
    await _pump(tester);
    expect(find.byType(MacWindowControls), findsNothing);
    // Hidden sidebar: the toggle moves to the toolbar, still without lights.
    await tester.tap(find.byWidgetPredicate(
        (w) => w is MacToolbarButton && w.label == 'Hide Sidebar'));
    await tester.pump();
    expect(find.byType(MacWindowControls), findsNothing);
  }, variant: _linux);

  testWidgets('the sidebar hides and comes back', (tester) async {
    final container = await _pump(tester);
    await tester.tap(find.byWidgetPredicate(
        (w) => w is MacToolbarButton && w.label == 'Hide Sidebar'));
    await tester.pump();
    expect(container.read(sidebarCollapsedProvider), isTrue);
    expect(find.byType(MacNavSidebar), findsNothing);

    await tester.tap(find.byWidgetPredicate(
        (w) => w is MacToolbarButton && w.label == 'Show Sidebar'));
    await tester.pump();
    expect(find.byType(MacNavSidebar), findsOneWidget);
  }, variant: _linux);

  testWidgets('a right-click opens exactly one menu, for the row clicked',
      (tester) async {
    await _pump(tester);
    await tester.tap(_side('Biology'));
    await _settle(tester);
    await tester.tap(_side('Cells'));
    await _settle(tester);

    await tester.tap(_side('Mitosis'), buttons: kSecondaryButton);
    await _settle(tester);
    expect(find.text('Rename…'), findsOneWidget);
    expect(find.text('Delete Page…'), findsOneWidget);
    // Neither the section's nor the notebook's menu came with it.
    expect(find.text('Edit Section…'), findsNothing);
    expect(find.text('Edit Notebook…'), findsNothing);
  }, variant: _linux);
}
