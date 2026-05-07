/// Word/OneDrive-style right-click context menu for media blocks. Right-clicking
/// any wrapped child opens a popup with Move up / Move down / Duplicate / Delete.
/// Each action runs as a single editor transaction so autosave picks it up.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class BlockContextMenu extends StatelessWidget {
  const BlockContextMenu({super.key, required this.node, required this.child});

  final afe.Node node;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onSecondaryTapDown: (details) => _show(context, details.globalPosition),
      child: child,
    );
  }

  Future<void> _show(BuildContext context, Offset pos) async {
    final editorState = context.read<afe.EditorState>();
    final canMoveUp = node.path.isNotEmpty && node.path.last > 0;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        if (canMoveUp)
          const PopupMenuItem(value: 'up', child: Text('Move up')),
        const PopupMenuItem(value: 'down', child: Text('Move down')),
        const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    if (result == null || editorState.isDisposed) return;
    switch (result) {
      case 'up':
        if (node.path.isEmpty || node.path.last == 0) return;
        final tx = editorState.transaction..moveNode(node.path.previous, node);
        await editorState.apply(tx);
      case 'down':
        // moveNode = delete + insert: target path is in the post-delete coord
        // space, so `path.next` correctly hops past the next sibling.
        final tx = editorState.transaction..moveNode(node.path.next, node);
        await editorState.apply(tx);
      case 'duplicate':
        final tx = editorState.transaction
          ..insertNode(node.path.next, node.copyWith());
        await editorState.apply(tx);
      case 'delete':
        final tx = editorState.transaction..deleteNode(node);
        await editorState.apply(tx);
    }
  }
}
