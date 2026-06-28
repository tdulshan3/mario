/// CodeBlock — an IDE-style, syntax-highlighted code block.
///
/// Follows the same self-contained pattern as [MathBlock]/[DrawingBlock]: the
/// source text + language live in node *attributes* (not the AppFlowy delta),
/// and editing happens in a plain Flutter [TextField]. The twist is a custom
/// [TextEditingController] whose `buildTextSpan` runs the `re_highlight` engine
/// (a pure-Dart highlight.js port — the same one AppFlowy uses) so tokens are
/// coloured live as you type.
library;

import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/github.dart';

// A curated language set — importing all 197 grammars would bloat the binary.
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/dockerfile.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/objectivec.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/plaintext.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/scss.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';

import '../../../ui/colors.dart';
import '_safe_transaction.dart';
import 'block_context_menu.dart';

class CodeBlockKeys {
  const CodeBlockKeys._();
  static const String type = 'code';

  /// Source text. Stored as a plain attribute rather than a delta so the
  /// [TextField] owns editing; the PDF/markdown exporters read this directly.
  static const String code = 'code';

  /// Language id understood by `re_highlight` (e.g. `dart`, `python`). Defaults
  /// to `plaintext` for no highlighting.
  static const String language = 'language';
}

afe.Node codeBlockNode({String code = '', String language = 'plaintext'}) =>
    afe.Node(
      type: CodeBlockKeys.type,
      attributes: {
        CodeBlockKeys.code: code,
        CodeBlockKeys.language: language,
      },
    );

/// Languages offered in the picker, in display order. `id` must match the key
/// registered in [_highlighter].
const List<({String id, String label})> _languages = [
  (id: 'plaintext', label: 'Plain text'),
  (id: 'bash', label: 'Bash / Shell'),
  (id: 'c', label: 'C'),
  (id: 'cpp', label: 'C++'),
  (id: 'csharp', label: 'C#'),
  (id: 'css', label: 'CSS'),
  (id: 'dart', label: 'Dart'),
  (id: 'dockerfile', label: 'Dockerfile'),
  (id: 'go', label: 'Go'),
  (id: 'java', label: 'Java'),
  (id: 'javascript', label: 'JavaScript'),
  (id: 'json', label: 'JSON'),
  (id: 'kotlin', label: 'Kotlin'),
  (id: 'markdown', label: 'Markdown'),
  (id: 'objectivec', label: 'Objective-C'),
  (id: 'php', label: 'PHP'),
  (id: 'python', label: 'Python'),
  (id: 'ruby', label: 'Ruby'),
  (id: 'rust', label: 'Rust'),
  (id: 'scss', label: 'SCSS'),
  (id: 'sql', label: 'SQL'),
  (id: 'swift', label: 'Swift'),
  (id: 'typescript', label: 'TypeScript'),
  (id: 'xml', label: 'HTML / XML'),
  (id: 'yaml', label: 'YAML'),
];

/// Single shared engine — registering grammars is one-time work and the
/// instance is immutable once built.
final Highlight _highlighter = () {
  final h = Highlight();
  h.registerLanguages({
    'plaintext': langPlaintext,
    'bash': langBash,
    'c': langC,
    'cpp': langCpp,
    'csharp': langCsharp,
    'css': langCss,
    'dart': langDart,
    'dockerfile': langDockerfile,
    'go': langGo,
    'java': langJava,
    'javascript': langJavascript,
    'json': langJson,
    'kotlin': langKotlin,
    'markdown': langMarkdown,
    'objectivec': langObjectivec,
    'php': langPhp,
    'python': langPython,
    'ruby': langRuby,
    'rust': langRust,
    'scss': langScss,
    'sql': langSql,
    'swift': langSwift,
    'typescript': langTypescript,
    'xml': langXml,
    'yaml': langYaml,
  });
  return h;
}();

final Set<String> _registered = _languages.map((l) => l.id).toSet();

/// A controller that paints syntax-highlighted spans live while editing.
class _CodeHighlightController extends TextEditingController {
  _CodeHighlightController({required String text, required this.language})
      : super(text: text);

  String language;
  Map<String, TextStyle> theme = atomOneDarkTheme;

  /// Swap the active language and repaint without disturbing text/selection.
  void setLanguage(String lang) {
    if (lang == language) return;
    language = lang;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final source = text;
    if (source.isEmpty || language == 'plaintext' || !_registered.contains(language)) {
      return TextSpan(text: source, style: style);
    }
    try {
      final result = _highlighter.highlight(code: source, language: language);
      final renderer = TextSpanRenderer(style, theme);
      result.render(renderer);
      return renderer.span ?? TextSpan(text: source, style: style);
    } catch (_) {
      // Unknown grammar / engine hiccup — fall back to unstyled text.
      return TextSpan(text: source, style: style);
    }
  }
}

class CodeBlockComponentBuilder extends afe.BlockComponentBuilder {
  CodeBlockComponentBuilder({super.configuration});

  @override
  afe.BlockComponentWidget build(afe.BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return CodeBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
    );
  }

  @override
  bool validate(afe.Node node) => node.attributes[CodeBlockKeys.code] is String;
}

class CodeBlockComponentWidget extends afe.BlockComponentStatefulWidget {
  const CodeBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.configuration = const afe.BlockComponentConfiguration(),
  });

  @override
  State<CodeBlockComponentWidget> createState() =>
      _CodeBlockComponentWidgetState();
}

class _CodeBlockComponentWidgetState extends State<CodeBlockComponentWidget> {
  late final _CodeHighlightController _controller;
  late final FocusNode _focusNode;
  Timer? _debounce;

  String get _code => (widget.node.attributes[CodeBlockKeys.code] as String?) ?? '';
  String get _language =>
      (widget.node.attributes[CodeBlockKeys.language] as String?) ?? 'plaintext';

  @override
  void initState() {
    super.initState();
    _controller = _CodeHighlightController(text: _code, language: _language);
    _focusNode = FocusNode(onKeyEvent: _onKey);
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant CodeBlockComponentWidget old) {
    super.didUpdateWidget(old);
    // Sync from external changes (undo, sync) only when we're not editing, to
    // avoid yanking the cursor while the user types.
    if (!_focusNode.hasFocus && _controller.text != _code) {
      _controller.text = _code;
    }
    if (_controller.language != _language) _controller.setLanguage(_language);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _debounce?.cancel();
      _commit();
    }
  }

  // Tab inserts two spaces instead of moving focus — basic IDE indentation.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
      final sel = _controller.selection;
      if (!sel.isValid) return KeyEventResult.ignored;
      final text = _controller.text;
      final newText = text.replaceRange(sel.start, sel.end, '  ');
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start + 2),
      );
      _scheduleCommit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onChanged(String _) => _scheduleCommit();

  void _scheduleCommit() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _commit);
  }

  Future<void> _commit() async {
    if (!mounted) return;
    if (_controller.text == _code) return;
    final editorState = context.read<afe.EditorState>();
    await safeApply(editorState, (tx) {
      tx.updateNode(widget.node, {CodeBlockKeys.code: _controller.text});
    });
  }

  Future<void> _setLanguage(String lang) async {
    _controller.setLanguage(lang);
    final editorState = context.read<afe.EditorState>();
    await safeApply(editorState, (tx) {
      tx.updateNode(widget.node, {CodeBlockKeys.language: lang});
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _controller.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Code copied'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = isDark ? atomOneDarkTheme : githubTheme;
    _controller.theme = theme;

    final root = theme['root'];
    final codeBg = root?.backgroundColor ?? (isDark ? const Color(0xFF282C34) : const Color(0xFFF6F8FA));
    final codeFg = root?.color ?? (isDark ? const Color(0xFFABB2BF) : const Color(0xFF24292E));
    final headerBg = isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03);
    final muted = isDark ? MarioColors.onSurfaceMutedDark : MarioColors.onSurfaceMuted;

    final mono = GoogleFonts.jetBrainsMono(
      fontSize: 13,
      height: 1.45,
      color: codeFg,
    );

    return BlockContextMenu(
      node: widget.node,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: codeBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? MarioColors.borderDark : MarioColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header: language picker + copy.
              Container(
                color: headerBg,
                padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
                child: Row(
                  children: [
                    _LanguagePicker(
                      value: _registered.contains(_language) ? _language : 'plaintext',
                      muted: muted,
                      onChanged: (v) {
                        if (v != null) _setLanguage(v);
                      },
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Copy code',
                      icon: Icon(Icons.copy_rounded, size: 16, color: muted),
                      visualDensity: VisualDensity.compact,
                      onPressed: _copy,
                    ),
                  ],
                ),
              ),
              // Editable, highlighted body.
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxLines: null,
                  expands: false,
                  cursorColor: codeFg,
                  style: mono,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  onChanged: _onChanged,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: '// Write code…',
                    hintStyle: mono.copyWith(color: muted),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact, borderless language dropdown for the header bar.
class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({
    required this.value,
    required this.muted,
    required this.onChanged,
  });

  final String value;
  final Color muted;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isDense: true,
        icon: Icon(Icons.arrow_drop_down, size: 18, color: muted),
        dropdownColor: Theme.of(context).colorScheme.surface,
        style: GoogleFonts.inter(fontSize: 12, color: muted),
        borderRadius: BorderRadius.circular(8),
        onChanged: onChanged,
        items: [
          for (final lang in _languages)
            DropdownMenuItem(value: lang.id, child: Text(lang.label)),
        ],
      ),
    );
  }
}

/// Slash-menu entry for `/code`.
afe.SelectionMenuItem codeSelectionMenuItem = afe.SelectionMenuItem.node(
  getName: () => 'Code block',
  iconData: Icons.code,
  keywords: const ['code', 'snippet', 'syntax', 'highlight'],
  nodeBuilder: (editorState, _) => codeBlockNode(),
  replace: (editorState, node) => node.delta?.toPlainText().isEmpty ?? false,
);
