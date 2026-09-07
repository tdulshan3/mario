import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_cef/src/webview_textinput.dart';

class _PreviewInput with WebeViewTextInput {
  @override
  int? get textInputViewId => 42;

  @override
  bool onFocusReceived() => false;

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> deltas) {}
}

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    testWidgets('editor input attaches and types on ${platform.name}',
        (tester) async {
      final editor = afe.EditorState.blank();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
        body: afe.AppFlowyEditor(editorState: editor),
      )));
      editor.updateSelectionWithReason(
        afe.Selection.collapsed(afe.Position(path: [0], offset: 0)),
      );
      await tester.pump();
      final call = tester.testTextInput.log
          .lastWhere((call) => call.method == 'TextInput.setClient');
      final config = (call.arguments as List)[1] as Map;
      expect(config['viewId'],
          platform == TargetPlatform.windows ? tester.view.viewId : null);
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'Windows typing works',
        selection: TextSelection.collapsed(offset: 20),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(editor.document.root.children.first.delta!.toPlainText(),
          'Windows typing works');
      await tester.pumpWidget(const SizedBox());
      editor.dispose();
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets('preview input passes its owning view to the platform',
      (tester) async {
    final input = _PreviewInput();
    input.attachTextInputClient();
    await tester.pump();
    final call = tester.testTextInput.log
        .lastWhere((call) => call.method == 'TextInput.setClient');
    expect((call.arguments as List)[1]['viewId'], 42);
    input.detachTextInputClient();
  });
}
