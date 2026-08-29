/// Export dialog — the four grounds render it, and the choice it returns is
/// the choice that was made.
///
/// The format/paper round-trip matters because the dialog is the only thing
/// that decides them: the editor hands whatever comes back straight to
/// PdfExporter.exportPageToFile.
library;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/models/note_page.dart';
import 'package:mario/features/export/export_dialog.dart';
import 'package:mario/features/export/pdf_exporter.dart';
import 'package:mario/ui/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final page = NotePage(
    id: 'p1', sectionId: 's1', notebookId: 'n1',
    title: 'Photosynthesis', driveFileId: 'f1', order: 0,
    createdAt: DateTime(2026), updatedAt: DateTime(2026),
  );

  final builders = <String, ThemeData Function()>{
    'light': MarioTheme.light, 'white': MarioTheme.white,
    'night': MarioTheme.night, 'black': MarioTheme.black,
  };
  for (final entry in builders.entries) {
    testWidgets('renders on ${entry.key}', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      ExportRequest? got;
      await tester.pumpWidget(ProviderScope(child: MaterialApp(
        theme: entry.value(),
        home: Builder(builder: (c) => Scaffold(
          body: Center(child: ElevatedButton(
            onPressed: () async { got = await showExportDialog(c, page: page); },
            child: const Text('open'),
          )),
        )),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Export this page'), findsOneWidget);
      expect(find.text('Photosynthesis'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('Markdown'), findsOneWidget);
      expect(find.text('Paper size'), findsOneWidget);
      expect(find.text('A4'), findsOneWidget);
      expect(find.text('Letter'), findsOneWidget);
      expect(find.textContaining('Noto fonts'), findsOneWidget);
      expect(find.text('Export PDF'), findsOneWidget);

      // Markdown hides paper + the font note, and relabels the action.
      await tester.tap(find.text('Markdown'));
      await tester.pumpAndSettle();
      expect(find.text('Paper size'), findsNothing);
      expect(find.textContaining('Noto fonts'), findsNothing);
      expect(find.text('Export Markdown'), findsOneWidget);

      // Back to PDF, pick Letter, export.
      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Letter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export PDF'));
      await tester.pumpAndSettle();
      expect(got?.format, ExportFormat.pdf);
      expect(got?.paper, PdfPaperSize.letter);
    });
  }

  testWidgets('a long title wraps, and unresolved crumbs simply drop out',
      (tester) async {
    // No notebook/section stream data is available here, so the notebook and
    // section crumbs are unresolvable — the line must shorten to the page
    // itself rather than print a stand-in.
    final long = NotePage(
      id: 'p2', sectionId: 's1', notebookId: 'n1',
      title: 'A very long page title that has to wrap inside the dialog '
          'rather than overflow it, because titles are the user\'s and not '
          'ours to keep short',
      driveFileId: 'f2', order: 0,
      createdAt: DateTime(2026), updatedAt: DateTime(2026),
    );
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(
      theme: MarioTheme.light(),
      home: Scaffold(body: ExportDialog(page: long)),
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('A very long page title'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
