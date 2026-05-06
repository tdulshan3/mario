/// MathBlock — full-line LaTeX equation rendered with flutter_math_fork.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../ui/colors.dart';

class MathBlockKeys {
  const MathBlockKeys._();
  static const String type = 'math_equation';
  static const String formula = 'formula';
}

afe.Node mathEquationNode({String formula = ''}) => afe.Node(
      type: MathBlockKeys.type,
      attributes: {MathBlockKeys.formula: formula},
    );

class MathBlockComponentBuilder extends afe.BlockComponentBuilder {
  MathBlockComponentBuilder({super.configuration});

  @override
  afe.BlockComponentWidget build(afe.BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return MathBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
    );
  }

  @override
  bool validate(afe.Node node) =>
      node.attributes[MathBlockKeys.formula] is String;
}

class MathBlockComponentWidget extends afe.BlockComponentStatefulWidget {
  const MathBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.configuration = const afe.BlockComponentConfiguration(),
  });

  @override
  State<MathBlockComponentWidget> createState() =>
      _MathBlockComponentWidgetState();
}

class _MathBlockComponentWidgetState extends State<MathBlockComponentWidget> {
  late TextEditingController _controller;
  bool _editing = false;

  String get _formula =>
      (widget.node.attributes[MathBlockKeys.formula] as String?) ?? '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formula);
    if (_formula.isEmpty) _editing = true;
  }

  @override
  void didUpdateWidget(covariant MathBlockComponentWidget old) {
    super.didUpdateWidget(old);
    if (!_editing && _controller.text != _formula) {
      _controller.text = _formula;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _commit() async {
    final editorState = context.read<afe.EditorState>();
    final tx = editorState.transaction
      ..updateNode(widget.node, {MathBlockKeys.formula: _controller.text});
    await editorState.apply(tx);
    if (!mounted) return;
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? MarioColors.onSurfaceMutedDark : MarioColors.onSurfaceMuted;
    final fg = isDark ? MarioColors.onSurfaceDark : MarioColors.onSurface;
    final bg = isDark
        ? MarioColors.surfaceVariantDark
        : MarioColors.surfaceVariant;

    final body = _editing
        ? Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _controller,
                  autofocus: true,
                  maxLines: null,
                  style: GoogleFonts.jetBrainsMono(fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: r'\frac{a}{b} \cdot \sum_{i=1}^{n} x_i',
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _commit(),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        _controller.text = _formula;
                        _editing = false;
                      }),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _commit,
                      child: const Text('Render'),
                    ),
                  ],
                ),
              ],
            ),
          )
        : InkWell(
            onTap: () => setState(() => _editing = true),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: Center(
                child: _formula.trim().isEmpty
                    ? Text('Tap to enter equation',
                        style: GoogleFonts.inter(color: muted, fontSize: 13))
                    : Math.tex(
                        _formula,
                        textStyle: TextStyle(fontSize: 18, color: fg),
                        onErrorFallback: (err) => Text(
                          'LaTeX error: ${err.message}',
                          style: GoogleFonts.inter(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12),
                        ),
                      ),
              ),
            ),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border(
              left: BorderSide(color: MarioColors.primary, width: 3)),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(6),
            bottomRight: Radius.circular(6),
          ),
        ),
        child: body,
      ),
    );
  }
}

/// Slash menu entry for `/math`.
afe.SelectionMenuItem mathSelectionMenuItem = afe.SelectionMenuItem.node(
  getName: () => 'Math equation',
  iconData: Icons.functions,
  keywords: const ['math', 'equation', 'latex', 'tex'],
  nodeBuilder: (editorState, _) => mathEquationNode(),
  replace: (editorState, node) =>
      node.delta?.toPlainText().isEmpty ?? false,
);
