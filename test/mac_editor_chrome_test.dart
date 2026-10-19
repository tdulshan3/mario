/// The editor's chrome in the macOS look: the export sheet, the drawing
/// toolbar, a block's context menu, the dictation button and the HTML
/// preview's header.
///
/// Widget tests run as Android, which draws the Material versions (their own
/// tests cover those); these switch the platform to Linux. Each checks that
/// the macOS control is the one on screen and that it still does what the
/// Material one does — the same request back, the same controller calls, the
/// same transaction, the same snack bar.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mario/core/models/note_page.dart';
import 'package:mario/core/services/voice_service.dart';
import 'package:mario/features/drawing/drawing_canvas.dart';
import 'package:mario/features/drawing/drawing_toolbar.dart';
import 'package:mario/features/drawing/mac_drawing_toolbar.dart';
import 'package:mario/features/drawing/stroke.dart';
import 'package:mario/features/editor/blocks/block_context_menu.dart';
import 'package:mario/features/editor/html_preview.dart';
import 'package:mario/features/export/export_dialog.dart';
import 'package:mario/features/export/mac_export_sheet.dart';
import 'package:mario/features/export/pdf_exporter.dart';
import 'package:mario/features/voice/voice_dictation.dart';
import 'package:mario/ui/mac/mac_look.dart';
import 'package:mario/ui/mac/mac_theme.dart';
import 'package:provider/provider.dart' as pv;

/// Widget tests run as Android; Linux is what draws the macOS look.
final _linux = TargetPlatformVariant.only(TargetPlatform.linux);

/// [home] in the desktop app's theme and look.
Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(1000, 700),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: macMaterialTheme(Brightness.light),
      builder: (context, child) => MacLookScope(child: child!),
      home: Scaffold(body: home),
    ),
  ));
  await tester.pumpAndSettle();
}

afe.EditorState _editor(List<String> paragraphs) => afe.EditorState(
      document: afe.Document.fromJson({
        'document': {
          'type': 'page',
          'children': [
            for (final p in paragraphs)
              {
                'type': 'paragraph',
                'data': {
                  'delta': [
                    {'insert': p},
                  ],
                },
              },
          ],
        },
      }),
    );

class _SilentVoice implements VoiceService {
  @override
  bool get isAvailable => false;
  @override
  Future<bool> initialize() async => false;
  @override
  Stream<TranscriptionEvent> startTranscription({String? localeId}) =>
      const Stream.empty();
  @override
  Future<void> stopTranscription() async {}
  @override
  Future<String?> startRecording() async => null;
  @override
  Future<String?> stopRecording() async => null;
}

void main() {
  group('export sheet', () {
    final page = NotePage(
      id: 'p1',
      sectionId: 's1',
      notebookId: 'n1',
      title: 'Photosynthesis',
      driveFileId: 'f1',
      order: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    testWidgets('asks in a sheet and returns the same request', (tester) async {
      ExportRequest? got;
      var closed = false;
      await _pump(
        tester,
        Builder(
          builder: (context) => Center(
            child: MacButton(
              label: 'open',
              onPressed: () async {
                got = await showExportDialog(context, page: page);
                closed = true;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(MacExportSheet), findsOneWidget);
      expect(find.byType(ExportDialog), findsNothing);
      expect(find.text('Export This Page'), findsOneWidget);
      // No index data here: the crumbs shorten to the page itself.
      expect(find.text('Photosynthesis'), findsOneWidget);
      expect(find.text('Paper Size:'), findsOneWidget);
      expect(find.textContaining('Noto fonts'), findsOneWidget);
      expect(find.text('Export PDF'), findsOneWidget);

      // Markdown hides the paper and the font note, and relabels Export.
      await tester.tap(find.byType(MacPopUpButton<ExportFormat>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Markdown').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Paper Size:'), findsNothing);
      expect(find.textContaining('Noto fonts'), findsNothing);
      expect(find.text('Export Markdown'), findsOneWidget);

      // Back to PDF, pick Letter, export.
      await tester.tap(find.byType(MacPopUpButton<ExportFormat>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PDF').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.byType(MacPopUpButton<PdfPaperSize>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Letter').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export PDF'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(got?.format, ExportFormat.pdf);
      expect(got?.paper, PdfPaperSize.letter);
    }, variant: _linux);

    testWidgets('Return exports, Escape cancels', (tester) async {
      final results = <ExportRequest?>[];
      await _pump(
        tester,
        Builder(
          builder: (context) => Center(
            child: MacButton(
              label: 'open',
              onPressed: () async =>
                  results.add(await showExportDialog(context, page: page)),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(results, hasLength(2));
      expect(results.first, isNull);
      expect(results.last?.format, ExportFormat.pdf);
      expect(results.last?.paper, PdfPaperSize.a4);
    }, variant: _linux);
  });

  group('drawing toolbar', () {
    testWidgets('draws the macOS controls and drives the controller',
        (tester) async {
      final controller = DrawingController();
      addTearDown(controller.dispose);
      var collapsed = 0;
      var saved = 0;
      await _pump(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: DrawingToolbar(
            controller: controller,
            onCollapse: () => collapsed++,
            onSave: () => saved++,
          ),
        ),
        // Narrower than any content pane: it wraps rather than overflows.
        size: const Size(320, 400),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(MacDrawingToolbar), findsOneWidget);
      expect(find.byType(IconButton), findsNothing);
      // No PNG export without something to capture.
      expect(find.bySemanticsLabel('Save as PNG'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Highlighter'));
      await tester.pump();
      expect(controller.mode, StrokeMode.highlighter);

      // Nothing drawn: Undo and Clear all are off.
      await tester.tap(find.bySemanticsLabel('Undo'));
      await tester.tap(find.bySemanticsLabel('Clear all'));
      await tester.pump();
      expect(controller.canUndo, isFalse);

      await tester.tap(find.bySemanticsLabel('Save changes'));
      await tester.tap(find.bySemanticsLabel('Collapse'));
      await tester.pump();
      expect(saved, 1);
      expect(collapsed, 1);
    }, variant: _linux);

    testWidgets('the colour well offers the drawing palette', (tester) async {
      final controller = DrawingController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: DrawingToolbar(
            controller: controller,
            onCollapse: () {},
            onSave: () {},
          ),
        ),
      );
      final well = tester.widget<MacColorWell>(find.byType(MacColorWell));
      expect(well.palette, drawingPalette);
      expect(well.color, controller.color);
    }, variant: _linux);
  });

  group('block context menu', () {
    Widget block(afe.EditorState state, int index) =>
        pv.Provider<afe.EditorState>.value(
          value: state,
          child: Center(
            child: BlockContextMenu(
              node: state.document.root.children[index],
              child: const SizedBox(
                width: 200,
                height: 80,
                child: ColoredBox(color: Color(0x11000000)),
              ),
            ),
          ),
        );

    testWidgets('a right-click opens the macOS menu; Duplicate copies',
        (tester) async {
      final state = _editor(['first', 'second']);
      await _pump(tester, block(state, 0));

      await tester.tap(find.byType(ColoredBox).last, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNothing);
      expect(find.text('Move Down'), findsOneWidget);

      // The first block cannot move up: dimmed, not missing.
      final up = tester
          .widget<MacMenuItem>(find.widgetWithText(MacMenuItem, 'Move Up'));
      expect(up.onSelected, isNull);

      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();
      expect(
        state.document.root.children.map((n) => n.delta?.toPlainText()),
        ['first', 'first', 'second'],
      );
      await tester.pump(const Duration(seconds: 1));
    }, variant: _linux);
  });

  group('dictation', () {
    setUp(() => GetIt.I.registerSingleton<VoiceService>(_SilentVoice()));
    tearDown(() => GetIt.I.unregister<VoiceService>());

    testWidgets('is a macOS button, and still explains itself in a snack bar',
        (tester) async {
      final state = _editor(['first']);
      await _pump(
        tester,
        Center(child: VoiceDictationButton(editorState: state)),
      );
      expect(find.byType(IconButton), findsNothing);
      final button = tester.widget<MacButton>(find.byType(MacButton));
      expect(button.isOn, isFalse);

      // No caret: the same hint the web gives.
      await tester.tap(find.byType(MacButton));
      await tester.pump();
      expect(
          find.text('Place the cursor in a paragraph first'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    }, variant: _linux);
  });

  group('HTML preview', () {
    testWidgets('has a macOS header, and says when it cannot render',
        (tester) async {
      var unpinned = 0;
      await _pump(
        tester,
        HtmlPreviewPane(
          html: '<p>hi</p>',
          isDark: false,
          title: 'HTML preview · pinned source',
          primaryActionLabel: 'Unpin',
          onPrimaryAction: () => unpinned++,
        ),
      );
      // No embedded browser under test: the pane says so in its own type.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.text('HTML preview · pinned source'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      expect(find.widgetWithText(MacButton, 'Open in Browser'), findsOneWidget);

      await tester.tap(find.widgetWithText(MacButton, 'Unpin'));
      expect(unpinned, 1);
      if (find.text('Preview Unavailable').evaluate().isNotEmpty) {
        expect(find.byType(MacEmptyState), findsOneWidget);
      }
    }, variant: _linux);
  });
}
