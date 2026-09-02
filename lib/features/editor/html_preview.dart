/// Reusable Chromium preview for page HTML and AI-created artifacts.
///
/// Page HTML is trusted user-authored content and is rendered directly. AI
/// artifacts use [sandboxed], which puts the generated document in an iframe
/// without same-origin, navigation, pop-up, or download privileges. Inline
/// CSS and JavaScript still work, so interactive artifacts remain useful.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_cef/webview_cef.dart';

import '../../ui/colors.dart';
import '../../ui/widgets/mario_loader.dart';

Future<void>? _cefInit;

Future<void> _ensureCef() {
  return _cefInit ??= WebviewManager().initialize();
}

/// Turns an HTML fragment into a complete document with readable defaults.
String wrapPreviewHtml(String body, {required bool isDark}) {
  final bg = isDark ? '#1f1f1f' : '#ffffff';
  final fg = isDark ? '#e6e6e6' : '#1a1a18';
  return '''<!DOCTYPE html>
<html><head>
<meta charset="UTF-8">
<style>
  html, body { margin: 0; padding: 0; }
  body {
    background: $bg;
    color: $fg;
    font-family: -apple-system, system-ui, "Segoe UI", Roboto, sans-serif;
    font-size: 15px;
    line-height: 1.6;
    padding: 24px 32px;
    max-width: 820px;
    margin: 0 auto;
  }
  h1, h2, h3, h4 { font-weight: 600; line-height: 1.25; margin-top: 1.4em; }
  p { margin: 0.5em 0; }
  ul, ol { padding-left: 1.5em; }
  blockquote { border-left: 3px solid #888; margin: 0.5em 0; padding-left: 1em; color: #888; }
  code { font-family: ui-monospace, "Fira Code", monospace; background: rgba(127,127,127,0.15); padding: 1px 4px; border-radius: 3px; font-size: 0.92em; }
  pre { background: rgba(127,127,127,0.1); padding: 12px; border-radius: 6px; overflow-x: auto; }
  img { max-width: 100%; height: auto; }
  table { border-collapse: collapse; }
  th, td { border: 1px solid rgba(127,127,127,0.4); padding: 4px 8px; }
  a { color: #5fa8e9; }
</style>
</head><body>$body</body></html>''';
}

/// The exact document written to the preview file.
///
/// Exposed for focused tests. Sandboxed previews keep generated code in a
/// credential-less iframe while still allowing self-contained interactivity.
String prepareHtmlPreviewDocument(
  String body, {
  required bool isDark,
  bool sandboxed = false,
}) {
  if (sandboxed) {
    final bg = isDark ? '#1f1f1f' : '#ffffff';
    final escaped = const HtmlEscape(HtmlEscapeMode.attribute).convert(body);
    return '''<!DOCTYPE html>
<html><head><meta charset="UTF-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: https:; font-src data: https:; media-src data: https:; connect-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
<style>html,body,iframe{width:100%;height:100%;margin:0;border:0;background:$bg}iframe{display:block}</style>
</head><body><iframe sandbox="allow-scripts allow-forms allow-modals" srcdoc="$escaped"></iframe></body></html>''';
  }

  final trimmed = body.trimLeft().toLowerCase();
  final isFullDoc =
      trimmed.startsWith('<!doctype') || trimmed.startsWith('<html');
  return isFullDoc ? body : wrapPreviewHtml(body, isDark: isDark);
}

class HtmlPreviewPane extends StatefulWidget {
  const HtmlPreviewPane({
    super.key,
    required this.html,
    required this.isDark,
    this.title = 'HTML preview',
    this.sandboxed = false,
    this.primaryActionLabel,
    this.onPrimaryAction,
  });

  final String html;
  final bool isDark;
  final String title;
  final bool sandboxed;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;

  @override
  State<HtmlPreviewPane> createState() => _HtmlPreviewPaneState();
}

class _HtmlPreviewPaneState extends State<HtmlPreviewPane> {
  WebViewController? _controller;
  String? _error;
  File? _tempFile;
  bool _dirtyDuringInit = false;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  @override
  void didUpdateWidget(HtmlPreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html ||
        oldWidget.isDark != widget.isDark ||
        oldWidget.sandboxed != widget.sandboxed) {
      _onHtmlChanged();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    final file = _tempFile;
    if (file != null) file.delete().catchError((_) => file);
    super.dispose();
  }

  Future<void> _setup() async {
    try {
      await _ensureCef().timeout(const Duration(seconds: 15));
      final controller = WebviewManager().createWebView(
        loading: const Center(child: MarioLoader(size: 18)),
      );
      final url = await _writeTempFile();
      await controller.initialize(url);
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      if (_dirtyDuringInit) {
        _dirtyDuringInit = false;
        await controller.loadUrl(await _writeTempFile());
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _onHtmlChanged() async {
    final controller = _controller;
    if (controller == null) {
      _dirtyDuringInit = true;
      return;
    }
    final url = await _writeTempFile();
    if (mounted) await controller.loadUrl(url);
  }

  Future<String> _writeTempFile() async {
    final content = prepareHtmlPreviewDocument(
      widget.html,
      isDark: widget.isDark,
      sandboxed: widget.sandboxed,
    );
    var file = _tempFile;
    if (file == null) {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      file = File('${Directory.systemTemp.path}/mario_preview_$stamp.html');
      _tempFile = file;
    }
    await file.writeAsString(content);
    return Uri.file(file.path).toString();
  }

  Future<void> _openInBrowser() async {
    final url = await _writeTempFile();
    final path = Uri.parse(url).toFilePath();
    try {
      if (Platform.isLinux) {
        await Process.start('xdg-open', [path]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [path]);
      } else if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', path]);
      }
    } catch (_) {
      // The embedded preview remains available if no desktop opener exists.
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg =
        widget.isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF7F7F7);
    final muted = widget.isDark
        ? MarioColors.onSurfaceMutedDark
        : MarioColors.onSurfaceMuted;
    final border =
        widget.isDark ? const Color(0xFF2C2C2C) : const Color(0xFFDADADA);
    final controller = _controller;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        border: Border(left: BorderSide(color: border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: muted,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                if (widget.onPrimaryAction != null &&
                    widget.primaryActionLabel != null)
                  TextButton(
                    onPressed: widget.onPrimaryAction,
                    style: TextButton.styleFrom(
                      foregroundColor: muted,
                      textStyle: GoogleFonts.inter(fontSize: 11),
                      minimumSize: const Size(0, 28),
                    ),
                    child: Text(widget.primaryActionLabel!),
                  ),
                TextButton.icon(
                  onPressed: _openInBrowser,
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: const Text('Open in browser'),
                  style: TextButton.styleFrom(
                    foregroundColor: muted,
                    textStyle: GoogleFonts.inter(fontSize: 11),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: border),
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Preview unavailable: $_error\n\nUse "Open in browser" above instead.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 12, color: muted),
                      ),
                    ),
                  )
                : controller == null
                    ? const Center(child: MarioLoader(size: 18))
                    : ValueListenableBuilder<bool>(
                        valueListenable: controller,
                        builder: (context, ready, _) => SizedBox.expand(
                          child: ready
                              ? controller.webviewWidget
                              : controller.loadingWidget,
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
