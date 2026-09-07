import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:webview_cef/webview_cef.dart';

void main() => runApp(const MaterialApp(home: Smoke()));

class Smoke extends StatefulWidget {
  const Smoke({super.key});
  @override
  State<Smoke> createState() => _SmokeState();
}

class _SmokeState extends State<Smoke> {
  final text = TextEditingController();
  final fieldFocus = FocusNode();
  final editorFocus = FocusNode();
  final editor = afe.EditorState.blank();
  final previewKey = GlobalKey();
  WebViewController? browser;
  String title = '';
  String phase = 'field';
  String error = '';
  @override
  void initState() {
    super.initState();
    FlutterError.onError = (details) {
      error += '${details.exceptionAsString()}\n';
    };
    Timer.periodic(const Duration(milliseconds: 500), (_) async {
      final command = File('smoke-command.txt');
      if (command.existsSync()) {
        final next = command.readAsStringSync().trim();
        if (next != phase) {
          phase = next;
          if (phase == 'editor') {
            editorFocus.requestFocus();
            await WidgetsBinding.instance.endOfFrame;
            editor.updateSelectionWithReason(
                afe.Selection.collapsed(afe.Position(path: [0], offset: 0)));
          } else if (phase == 'field') {
            fieldFocus.requestFocus();
          } else if (phase == 'preview') {
            await preview();
          } else if (phase == 'capture') {
            final boundary = previewKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes = await image.toByteData(format: ImageByteFormat.png);
            await File('smoke-preview.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          }
        }
      }
      File('smoke-result.json').writeAsStringSync(jsonEncode({
        'phase': phase,
        'field': text.text,
        'editor': editor.document.toJson(),
        'previewTitle': title,
        'error': error,
      }));
    });
  }

  Future<void> preview() async {
    try {
      await WebviewManager().initialize().timeout(const Duration(seconds: 10));
      final view = WebviewManager().createWebView();
      view.setWebviewListener(
          WebviewEventsListener(onTitleChanged: (value) => title = value));
      final html = File('smoke-preview.html').absolute;
      await html.writeAsString(
          '<!doctype html><title>MARIO_PREVIEW_READY</title><body style="background:#00ff00"><input style="position:absolute;top:0;left:0;width:100%;height:80px" oninput="document.title=\'INPUT:\'+this.value" placeholder="Type in preview"><h1 style="margin-top:100px">Preview renders</h1></body>');
      await view
          .initialize(html.uri.toString())
          .timeout(const Duration(seconds: 10));
      setState(() => browser = view);
    } catch (e) {
      error += '$e\n';
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
          body: Row(children: [
        Expanded(
            child: Column(children: [
          TextField(controller: text, focusNode: fieldFocus, autofocus: true),
          Expanded(
              child: afe.AppFlowyEditor(
                  editorState: editor, focusNode: editorFocus)),
        ])),
        Expanded(
            child: RepaintBoundary(
                key: previewKey,
                child: browser == null
                    ? const Text('Preview pending')
                    : browser!.webviewWidget)),
      ]));
}
