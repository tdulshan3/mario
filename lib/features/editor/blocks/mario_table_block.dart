/// MarioTableBlockComponentBuilder — AppFlowy's native table wrapped with a
/// bottom-right corner handle that resizes the WHOLE table by scaling every
/// column proportionally (Word/OneNote-style). Cell editing, per-column drag,
/// and the add row/column controls are the stock AppFlowy table, rendered
/// inside unchanged.
///
/// Key detail: the stock [afe.TableBlockComponentWidget] keeps `node.key` so
/// its SelectableMixin state stays registered for selection/cursor — our
/// wrapper is an unkeyed container around it. The handle uses a raw [Listener]
/// (not a GestureDetector) so the editor's horizontal scroll can't steal the
/// drag in the gesture arena.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../ui/colors.dart';

class MarioTableBlockComponentBuilder extends afe.BlockComponentBuilder {
  MarioTableBlockComponentBuilder({super.configuration});

  @override
  afe.BlockComponentWidget build(afe.BlockComponentContext ctx) {
    return _MarioTableWidget(
      node: ctx.node,
      configuration: configuration,
      showActions: showActions(ctx.node),
      actionBuilder: (context, state) => actionBuilder(ctx, state),
    );
  }

  @override
  bool validate(afe.Node node) {
    final cols = node.attributes[afe.TableBlockKeys.colsLen];
    final rows = node.attributes[afe.TableBlockKeys.rowsLen];
    return cols is int &&
        rows is int &&
        cols > 0 &&
        rows > 0 &&
        node.children.length == cols * rows;
  }
}

class _MarioTableWidget extends afe.BlockComponentStatefulWidget {
  const _MarioTableWidget({
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.configuration = const afe.BlockComponentConfiguration(),
  });

  @override
  State<_MarioTableWidget> createState() => _MarioTableWidgetState();
}

class _MarioTableWidgetState extends State<_MarioTableWidget> {
  // Snapshot of per-column widths at drag start, so scaling is stable.
  List<double> _startWidths = const [];
  double _startTotal = 0;
  double _startX = 0;

  afe.Node get _node => widget.node;

  @override
  Widget build(BuildContext context) {
    // Stock AppFlowy table — node.key stays here so its SelectableMixin state
    // remains the registered selectable for this node (cursor/selection).
    final table = afe.TableBlockComponentWidget(
      key: _node.key,
      tableNode: afe.TableNode(node: _node),
      node: _node,
      configuration: widget.configuration,
      showActions: widget.showActions,
      actionBuilder: widget.actionBuilder,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        table,
        Positioned(
          right: 0,
          bottom: 0,
          child: _ResizeHandle(
            onStart: _onStart,
            onMove: _onMove,
            onEnd: _onEnd,
          ),
        ),
      ],
    );
  }

  void _onStart(Offset global) {
    final t = afe.TableNode(node: _node);
    _startWidths = [for (var c = 0; c < t.colsLen; c++) t.getColWidth(c)];
    _startTotal = _startWidths.fold<double>(0, (a, b) => a + b);
    _startX = global.dx;
  }

  void _onMove(Offset global) {
    if (_startWidths.isEmpty || _startTotal <= 0) return;
    final dx = global.dx - _startX;
    var factor = (_startTotal + dx) / _startTotal;
    if (factor < 0.2) factor = 0.2; // never collapse the table to nothing
    final t = afe.TableNode(node: _node);
    for (var c = 0; c < _startWidths.length && c < t.colsLen; c++) {
      // Live update (no transaction) — mirrors AppFlowy's own column drag and
      // re-renders immediately.
      t.setColWidth(c, _startWidths[c] * factor);
    }
  }

  void _onEnd() {
    if (_startWidths.isEmpty) return;
    _startWidths = const [];
    // Persist the final widths in a transaction so the change is undoable and
    // gets autosaved (the live updates above bypassed the transaction system).
    final editorState = context.read<afe.EditorState>();
    final t = afe.TableNode(node: _node);
    final tx = editorState.transaction;
    for (var c = 0; c < t.colsLen; c++) {
      t.setColWidth(c, t.getColWidth(c), transaction: tx, force: true);
    }
    editorState.apply(tx);
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({
    required this.onStart,
    required this.onMove,
    required this.onEnd,
  });

  final void Function(Offset globalPosition) onStart;
  final void Function(Offset globalPosition) onMove;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => onStart(e.position),
        onPointerMove: (e) => onMove(e.position),
        onPointerUp: (_) => onEnd(),
        onPointerCancel: (_) => onEnd(),
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: MarioColors.primary.withValues(alpha: 0.65),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
            ),
          ),
          child: const Icon(Icons.code, size: 11, color: Colors.white),
        ),
      ),
    );
  }
}
