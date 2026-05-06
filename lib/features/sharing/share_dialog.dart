/// Share dialog — invite collaborators to a notebook by email + role.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/collaborator.dart';
import '../../core/models/notebook.dart';
import '../../core/services/mario_firestore.dart';
import '../shell/shell_state.dart';

void showShareDialog(BuildContext context, WidgetRef ref) {
  final selection = ref.read(selectionProvider);
  final notebooks = ref.read(notebooksStreamProvider).valueOrNull ?? [];
  final notebook =
      notebooks.where((n) => n.id == selection.notebookId).firstOrNull;
  if (notebook == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Pick a notebook first'),
    ));
    return;
  }
  showDialog(
    context: context,
    builder: (_) => _ShareDialog(notebook: notebook),
  );
}

class _ShareDialog extends ConsumerStatefulWidget {
  const _ShareDialog({required this.notebook});
  final Notebook notebook;

  @override
  ConsumerState<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends ConsumerState<_ShareDialog> {
  final _email = TextEditingController();
  CollaboratorRole _role = CollaboratorRole.editor;
  bool _saving = false;

  Future<void> _invite() async {
    final email = _email.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final db = GetIt.I<MarioFirestore>();
      final docPath = 'notebooks/${widget.notebook.id}';
      final collaborator = Collaborator(uid: '', email: email, role: _role);
      await db.arrayUnion(docPath, 'collaborators', [collaborator.toMap()]);
      await db.arrayUnion(docPath, 'invitedEmails', [email]);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Invited $email')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Invite failed: $e')));
      setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Share "${widget.notebook.name}"',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'someone@example.com',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Role',
                    style: GoogleFonts.inter(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                DropdownButton<CollaboratorRole>(
                  value: _role,
                  items: const [
                    DropdownMenuItem(
                        value: CollaboratorRole.editor, child: Text('Editor')),
                    DropdownMenuItem(
                        value: CollaboratorRole.viewer, child: Text('Viewer')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _role = v);
                  },
                ),
              ],
            ),
            if (widget.notebook.collaboratorUids.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('People with access',
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55))),
              const SizedBox(height: 8),
              ...widget.notebook.collaboratorUids
                  .map((uid) => Text(uid, style: GoogleFonts.inter(fontSize: 12))),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _invite,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Invite'),
        ),
      ],
    );
  }
}
