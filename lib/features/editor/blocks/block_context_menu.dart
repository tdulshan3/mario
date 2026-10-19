/// Word/OneDrive-style right-click context menu for media blocks. Right-clicking
/// any wrapped child opens a popup with Move up / Move down / Duplicate / Delete.
/// Each action runs as a single editor transaction so autosave picks it up.
///
/// The desktop builds open a macOS context menu instead of Material's popup;
/// the actions are the same function either way.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../ui/mac/mac_look.dart';

class BlockContextMenu extends StatelessWidget {
  const BlockContextMenu({super.key, required this.node, required this.child});

  final afe.Node node;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (useMacLook) return _MacBlockContextMenu(node: node, child: child);
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
    if (result == null) return;
    await _applyBlockAction(editorState, node, result);
  }
}

/// Runs one menu action on [node] as a single transaction.
Future<void> _applyBlockAction(
  afe.EditorState editorState,
  afe.Node node,
  String action,
) async {
  if (editorState.isDisposed) return;
  switch (action) {
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

/// The same menu as a macOS context menu, opened at the pointer.
///
/// apple_ui's `MacContextMenu` opens on the raw secondary pointer-down of
/// whatever it wraps, so wrapping the block in one would open it alongside
/// any other menu listening on the way down. The secondary-tap recogniser
/// keeps the gesture arena's say over who handles the click, exactly as the
/// Material version does; it then opens one menu from its controller, from a
/// zero-size anchor placed at the pointer (the trick the sidebar uses — see
/// `mac_sidebar.dart`). The anchor's paint transform carries the page zoom,
/// so the menu lands under the pointer at any zoom.
///
/// Move Up is shown dimmed on the first block rather than left out: macOS
/// menus keep their shape and disable what does not apply.
class _MacBlockContextMenu extends StatefulWidget {
  const _MacBlockContextMenu({required this.node, required this.child});

  final afe.Node node;
  final Widget child;

  @override
  State<_MacBlockContextMenu> createState() => _MacBlockContextMenuState();
}

class _MacBlockContextMenuState extends State<_MacBlockContextMenu> {
  final MacMenuController _menu = MacMenuController();
  Offset? _at;

  void _open(Offset local) {
    _menu.close();
    setState(() => _at = local);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _menu.open();
    });
  }

  void _run(String action) {
    if (!mounted) return;
    final editorState = context.read<afe.EditorState>();
    _applyBlockAction(editorState, widget.node, action);
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final canMoveUp = node.path.isNotEmpty && node.path.last > 0;
    final at = _at;
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onSecondaryTapDown: (details) => _open(details.localPosition),
      child: Stack(
        // Passthrough, so the block lays out exactly as it would unwrapped.
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (at != null)
            Positioned(
              left: at.dx,
              // A menu opened from its controller hangs 6 px under its
              // anchor; a context menu's top-left corner is the pointer.
              top: at.dy - 6,
              child: MacContextMenu(
                controller: _menu,
                items: [
                  MacMenuItem(
                    label: 'Move Up',
                    onSelected: canMoveUp ? () => _run('up') : null,
                  ),
                  MacMenuItem(
                    label: 'Move Down',
                    onSelected: () => _run('down'),
                  ),
                  MacMenuItem(
                    label: 'Duplicate',
                    onSelected: () => _run('duplicate'),
                  ),
                  const MacMenuDivider(),
                  MacMenuItem(
                    label: 'Delete',
                    onSelected: () => _run('delete'),
                  ),
                ],
                child: const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }
}
