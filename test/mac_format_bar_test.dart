/// The macOS format bar: the desktop builds' counterpart of the editor's
/// Material ribbon.
///
/// Widget tests run as Android, which draws the ribbon; these switch the
/// platform to Linux, which is what puts the format bar on screen. The bar
/// has to fit the 800 px minimum window with the sidebar open — a content
/// pane of about 560 px — and every control has to drive the editor exactly
/// as the ribbon's does, because they run the same commands.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/editor/canvas_toolbar.dart';
import 'package:mario/features/editor/save_status.dart';
import 'package:mario/features/editor/mac_format_bar.dart';
import 'package:mario/features/editor/mac_page_actions.dart';
import 'package:mario/ui/mac/mac_look.dart';
import 'package:mario/ui/mac/mac_theme.dart';
import 'package:mario/ui/theme.dart';

/// Widget tests run as Android; Linux is what draws the macOS look.
final _linux = TargetPlatformVariant.only(TargetPlatform.linux);

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

/// Loads apple_ui's Inter, the face the desktop draws its chrome in, so
/// that widths are measured in real text rather than the test font's
/// one-em squares (which make every label half as wide again).
Future<void> _loadInter() async {
  final loader = FontLoader('packages/apple_ui/Inter');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader
        .addFont(rootBundle.load('packages/apple_ui/fonts/Inter-$weight.ttf'));
  }
  await loader.load();
}

/// AppFlowy seals each edit into its undo history after a short debounce;
/// let it run so no timer outlives the test.
Future<void> _settleHistory(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 1));

/// Selects the whole first block.
void _selectFirst(afe.EditorState state, int length) {
  state.selection = afe.Selection(
    start: afe.Position(path: [0], offset: 0),
    end: afe.Position(path: [0], offset: length),
  );
}

/// The page actions as the editor builds them, at their longest: every
/// suffix the save line can carry.
Widget _actions({
  VoidCallback? onTogglePreview,
  VoidCallback? onSaveNow,
  bool previewMode = false,
  SaveStatus status = SaveStatus.saved,
}) =>
    MacPageActions(
      status: status,
      lastSavedAt: DateTime(2026),
      pendingImages: 2,
      pendingChanges: 3,
      drawMode: false,
      previewMode: previewMode,
      onExport: () {},
      onToggleDraw: () {},
      onTogglePreview: onTogglePreview ?? () {},
      onSaveNow: onSaveNow ?? () {},
      // The real dictation button reaches for the voice service when it is
      // disposed; a stand-in of the same size keeps the test self-contained.
      dictate: MacButton(
        icon: AppleIcons.mic,
        semanticLabel: 'Voice dictation',
        onPressed: () {},
      ),
    );

Future<void> _pump(
  WidgetTester tester,
  afe.EditorState state, {
  double width = 560,
  Widget? trailing,
}) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: macMaterialTheme(Brightness.light),
    builder: (context, child) => MacLookScope(child: child!),
    home: Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CanvasToolbar(
            editorState: state,
            zoom: 1,
            onZoomIn: () {},
            onZoomOut: () {},
            onZoomReset: () {},
            drawMode: false,
            onToggleDraw: () {},
            trailing: trailing ?? _actions(),
          ),
          const Expanded(child: SizedBox()),
        ],
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The ribbon as the web builds it.
Future<void> _pumpRibbon(WidgetTester tester) => tester.pumpWidget(MaterialApp(
      theme: MarioTheme.light(),
      home: Scaffold(
        body: CanvasToolbar(
          editorState: _editor(['Hello world']),
          zoom: 1,
          onZoomIn: () {},
          onZoomOut: () {},
          onZoomReset: () {},
          drawMode: false,
          onToggleDraw: () {},
        ),
      ),
    ));

void main() {
  setUpAll(_loadInter);

  testWidgets('the desktop draws the format bar, not the ribbon',
      (tester) async {
    await _pump(tester, _editor(['Hello world']));
    expect(find.byType(MacFormatBar), findsOneWidget);
    expect(find.byType(DropdownButton<int?>), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  }, variant: _linux);

  testWidgets('the web and mobile keep the Material ribbon', (tester) async {
    tester.view.physicalSize = const Size(1200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // The ribbon's fixed-width dropdowns are sized for the app's fonts and
    // overflow in the test font. That is the Material path's own layout,
    // untouched here; this test is only about which bar is drawn.
    final reportError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details.toString().contains('overflowed')) {
        reportError?.call(details);
      }
    };
    try {
      await _pumpRibbon(tester);
    } finally {
      FlutterError.onError = reportError;
    }
    expect(find.byType(MacFormatBar), findsNothing);
    expect(find.byType(DropdownButton<int?>), findsOneWidget);
  });

  for (final width in [400.0, 560.0, 800.0, 1040.0, 1680.0]) {
    testWidgets('fits a ${width.round()} px content pane', (tester) async {
      await _pump(tester, _editor(['Hello world']), width: width);
      expect(tester.takeException(), isNull);
      final bar = tester.getRect(find.byType(MacFormatBar));
      // Every control stays inside the bar, and the page actions keep the
      // end of the first row.
      for (final element in find
          .descendant(
            of: find.byType(MacFormatBar),
            matching: find.byWidgetPredicate((w) =>
                w is MacButton ||
                w is MacPopUpButton ||
                w is MacSegmentedControl ||
                w is MacColorWell ||
                w is MacPullDownButton),
          )
          .evaluate()) {
        final rect = tester.getRect(find.byWidget(element.widget));
        expect(rect.left, greaterThanOrEqualTo(bar.left), reason: '$width');
        expect(rect.right, lessThanOrEqualTo(bar.right), reason: '$width');
      }
      final more = tester.getRect(find.bySemanticsLabel('More').first);
      expect(more.right, closeTo(bar.right - 12, 1));
      expect(more.top, lessThan(bar.top + 12));
    }, variant: _linux);
  }

  testWidgets('the 800 px window takes no more than three rows',
      (tester) async {
    await _pump(tester, _editor(['Hello world']), width: 560);
    // A small control is 20 px; three rows, the gaps between them and the
    // bar's own padding come to 84.
    expect(tester.getSize(find.byType(MacFormatBar)).height,
        lessThanOrEqualTo(85));
  }, variant: _linux);

  testWidgets('Bold toggles bold on the selection, and shows it',
      (tester) async {
    final state = _editor(['Hello world']);
    await _pump(tester, state, width: 1280);
    _selectFirst(state, 5);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Bold'));
    await tester.pumpAndSettle();
    final delta = state.document.root.children.first.delta!;
    expect(delta.first.attributes?[afe.AppFlowyRichTextKeys.bold], isTrue);

    // Rebuilt, the segment reads as on.
    await _pump(tester, state, width: 1280);
    final marks = tester.widget<MacSegmentedControl<String>>(
        find.byWidgetPredicate((w) =>
            w is MacSegmentedControl<String> &&
            w.semanticLabel == 'Text style'));
    expect(marks.values, contains(afe.AppFlowyRichTextKeys.bold));

    // A second click turns it off again.
    await tester.tap(find.bySemanticsLabel('Bold'));
    await tester.pumpAndSettle();
    expect(
        state.document.root.children.first.delta!.first
            .attributes?[afe.AppFlowyRichTextKeys.bold],
        isNot(true));
    await _settleHistory(tester);
  }, variant: _linux);

  testWidgets('the style pop-up turns the block into a heading',
      (tester) async {
    final state = _editor(['Hello world']);
    await _pump(tester, state, width: 1280);
    _selectFirst(state, 5);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Paragraph style'), findsOneWidget);
    final popUp =
        tester.widget<MacPopUpButton<int>>(find.byType(MacPopUpButton<int>));
    expect(popUp.value, 0); // Normal

    await tester.tap(find.bySemanticsLabel('Paragraph style'));
    await tester.pumpAndSettle();
    // The menu's row, not the pop-up's hidden sizing label.
    await tester.tap(find.text('Heading 2').hitTestable());
    await tester.pumpAndSettle();

    final node = state.document.root.children.first;
    expect(node.type, afe.HeadingBlockKeys.type);
    expect(node.attributes[afe.HeadingBlockKeys.level], 2);
    expect(node.delta?.toPlainText(), 'Hello world');
    await _settleHistory(tester);
  }, variant: _linux);

  testWidgets('alignment and lists act on the block under the caret',
      (tester) async {
    final state = _editor(['Hello world']);
    await _pump(tester, state, width: 1280);
    state.selection = afe.Selection.collapsed(afe.Position(path: [0]));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Align Center'));
    await tester.pumpAndSettle();
    expect(
        state.document.root.children.first.attributes[afe.blockComponentAlign],
        'center');

    await tester.tap(find.bySemanticsLabel('Bullet List'));
    await tester.pumpAndSettle();
    expect(state.document.root.children.first.type, 'bulleted_list');

    // The list segment shows the block's type, and choosing it again turns
    // the block back into a paragraph, as the ribbon's button does.
    await _pump(tester, state, width: 1280);
    final lists = tester.widget<MacSegmentedControl<String>>(
        find.byWidgetPredicate((w) =>
            w is MacSegmentedControl<String> && w.semanticLabel == 'Lists'));
    expect(lists.values, {'bulleted_list'});
    await tester.tap(find.bySemanticsLabel('Bullet List'));
    await tester.pumpAndSettle();
    expect(
        state.document.root.children.first.type, afe.ParagraphBlockKeys.type);
    await _settleHistory(tester);
  }, variant: _linux);

  testWidgets('the text colour well applies a palette colour, and None clears',
      (tester) async {
    final state = _editor(['Hello world']);
    await _pump(tester, state, width: 1280);
    _selectFirst(state, 5);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Text color'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('#E57373'));
    await tester.pumpAndSettle();
    expect(
        state.document.root.children.first.delta!.first
            .attributes?[afe.AppFlowyRichTextKeys.textColor],
        '0xffe57373');

    await tester.tap(find.bySemanticsLabel('Text color'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    expect(
        state.document.root.children.first.delta!.first
            .attributes?[afe.AppFlowyRichTextKeys.textColor],
        isNull);
    await _settleHistory(tester);
  }, variant: _linux);

  testWidgets('inserts add their block after the caret', (tester) async {
    final state = _editor(['Hello world']);
    await _pump(tester, state, width: 1280);
    state.selection = afe.Selection.collapsed(afe.Position(path: [0]));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Insert Divider'));
    await tester.pumpAndSettle();
    expect(state.document.root.children.map((n) => n.type),
        [afe.ParagraphBlockKeys.type, 'divider']);
    await _settleHistory(tester);
  }, variant: _linux);

  testWidgets('More holds the preview toggle and Save Now', (tester) async {
    var previews = 0;
    var saves = 0;
    await _pump(
      tester,
      _editor(['Hello world']),
      width: 1280,
      trailing: _actions(
        onTogglePreview: () => previews++,
        onSaveNow: () => saves++,
      ),
    );
    // Every suffix of the save line is still there.
    expect(find.text('Saved · 2 images not synced · 3 changes waiting to sync'),
        findsOneWidget);

    await tester.tap(find.bySemanticsLabel('More').first);
    await tester.pumpAndSettle();
    expect(find.text('Show HTML Preview'), findsOneWidget);
    await tester.tap(find.text('Save Now'));
    await tester.pumpAndSettle();
    expect(saves, 1);

    await tester.tap(find.bySemanticsLabel('More').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show HTML Preview'));
    await tester.pumpAndSettle();
    expect(previews, 1);
  }, variant: _linux);
}
