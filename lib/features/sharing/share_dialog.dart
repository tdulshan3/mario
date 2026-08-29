/// Share dialog — invite collaborators to a notebook by email + role
/// (artboard 2h).
///
/// What the design draws that this deliberately does NOT:
///
///  · "Anyone with the link · Off — invited people only". There is no link
///    sharing in this app: no public link, no share token, no field for one in
///    [Notebook], in the notebook document or in [MarioFirestore]. A row drawn
///    switched-off and disabled still tells the reader the feature exists and
///    is merely turned off, so it is omitted outright rather than mocked.
///
///  · A role dropdown on an existing collaborator. The `collaborators` array is
///    written in exactly one place — [_ShareDialogState._invite] below, via
///    [MarioFirestore.arrayUnion]. The facade has no arrayRemove and no
///    element-level write, so a role cannot be changed once it is in the array.
///    Existing people therefore render their role as static text; a dropdown
///    there would be a control with nothing to commit to.
///
/// Where the people list comes from is worth stating, because it is not the
/// obvious field. [Notebook.collaboratorUids] is only ever written at creation
/// (always empty), and [Notebook.fromMap] does not parse `collaborators` at
/// all — so the invited people are in the raw document and nowhere else. This
/// reads that document back through the same query [SyncService.watchNotebooks]
/// uses, which is the only doc read available on both backends:
/// [CloudFirestoreClient] has a `getDoc`, but [FiredartClient] — the Linux
/// build — does not, so a doc-path read would compile and then fail on the
/// platform the app actually ships on.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';

import '../../core/models/collaborator.dart';
import '../../core/models/notebook.dart';
import '../../core/services/mario_firestore.dart';
import '../../ui/colors.dart';
import '../../ui/organic.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/mario_loader.dart';
import '../auth/auth_notifier.dart';
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
  // The design dims the page behind a dialog with neutral-900 — the mark's
  // navy. Right on three grounds, wrong on Black, where a navy scrim over pure
  // #000 is just a blue wash with no navy in the ground to agree with.
  final black = marioMode(context) == MarioThemeMode.black;
  showDialog(
    context: context,
    barrierColor: black
        ? Colors.black.withValues(alpha: 0.66)
        : MarioColors.navy.withValues(alpha: 0.42),
    builder: (_) => _ShareDialog(notebook: notebook),
  );
}

/// The notebook's raw Firestore document, fetched once when the dialog opens.
///
/// Only the `collaborators` array is wanted, and [Notebook] drops it. The query
/// is the same one [SyncService.watchNotebooks] runs, so it reads exactly the
/// documents this user can already see and needs no rule of its own; the
/// notebook is guaranteed to be in the result because it came from that very
/// stream. A one-shot future is enough: a successful invite closes the dialog,
/// so the list never has to update underneath itself.
final _notebookDocProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
        (ref, notebookId) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return const {};
  final docs = await GetIt.I<MarioFirestore>().fetchCollection(
    'notebooks',
    where: MarioFilter.contains('memberUids', user.uid),
  );
  for (final doc in docs) {
    if (doc.id == notebookId) return doc.data;
  }
  return const {};
});

/// One row of "People with access", already resolved to what can be shown.
class _Person {
  const _Person({
    required this.initials,
    required this.name,
    this.detail,
    this.role,
    this.isOwner = false,
  });

  final String initials;
  final String name;

  /// The muted second line — an email, or the bare uid when that is genuinely
  /// all the app stores about them.
  final String? detail;

  /// Null when no role is recorded for this person, which happens only for a
  /// uid in [Notebook.collaboratorUids] with no matching `collaborators` entry.
  /// An empty slot is the honest render; a guessed "Editor" would not be.
  final String? role;
  final bool isOwner;
}

/// Two initials from a name or an email, falling back to "?" when the app has
/// nothing to build them from (an owner who is not the current user is a uid
/// and nothing else — there is no user directory to resolve it against).
String _initials(String? source) {
  final cleaned = (source ?? '').trim();
  if (cleaned.isEmpty) return '?';
  final local = cleaned.split('@').first;
  final words = local
      .split(RegExp(r'[\s._\-+]+'))
      .where((w) => w.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return '?';
  String head(String w) => String.fromCharCodes(w.runes.take(1)).toUpperCase();
  if (words.length == 1) return head(words.first);
  return '${head(words[0])}${head(words[1])}';
}

String _roleLabel(CollaboratorRole role) => switch (role) {
      CollaboratorRole.owner => 'Owner',
      CollaboratorRole.editor => 'Editor',
      CollaboratorRole.viewer => 'Viewer',
    };

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

  @override
  void initState() {
    super.initState();
    // Drives the Invite button's enabled state. `_invite` already returns
    // silently on an address it will not send — a button that looks live and
    // does nothing is the thing this system is least willing to ship, so the
    // same test now greys it out instead.
    _email.addListener(_onEmailChanged);
  }

  void _onEmailChanged() => setState(() {});

  /// The exact test [_invite] applies before it will send anything.
  bool get _canInvite {
    final email = _email.text.trim();
    return email.isNotEmpty && email.contains('@');
  }

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
    _email.removeListener(_onEmailChanged);
    _email.dispose();
    super.dispose();
  }

  /// The notebook's real page count, or null while any of it is still loading.
  ///
  /// Pages are stored per section — there is no "pages in this notebook"
  /// provider to read — so this walks the notebook's sections and sums the
  /// section page streams. Every section has to have arrived before the total
  /// means anything: a partial sum is a smaller, wrong number that silently
  /// grows as the rest land, so one unresolved section makes the whole thing
  /// null and the sentence drops the count rather than misstating it.
  int? _pageCount() {
    final sections =
        ref.watch(sectionsStreamProvider(widget.notebook.id)).valueOrNull;
    if (sections == null) return null;
    final counts = [
      for (final section in sections)
        ref
            .watch(pagesStreamProvider(
                (notebookId: widget.notebook.id, sectionId: section.id)))
            .valueOrNull
            ?.length,
    ];
    if (counts.any((c) => c == null)) return null;
    return counts.fold<int>(0, (sum, c) => sum + c!);
  }

  String _accessLine(int? pages) {
    if (pages == null || pages == 0) {
      return 'Everyone you add sees every page in this notebook.';
    }
    if (pages == 1) return 'Everyone you add sees the one page in this notebook.';
    return 'Everyone you add sees all $pages pages.';
  }

  /// Everyone the notebook document actually records, owner first.
  ///
  /// Duplicate invites of one address collapse to the most recent entry:
  /// arrayUnion only dedupes elements that are identical, so inviting the same
  /// person twice at different roles leaves two entries, and the later one is
  /// the role that was last asked for.
  List<_Person> _people(Map<String, dynamic> doc) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final notebook = widget.notebook;
    final myUid = user?.uid;
    final myEmail = user?.email?.toLowerCase();

    final ownerIsMe = myUid != null && myUid == notebook.ownerId;
    final people = <_Person>[
      if (ownerIsMe)
        _Person(
          initials: _initials(user?.displayName ?? user?.email),
          name: 'You',
          detail: user?.email,
          role: 'Owner',
          isOwner: true,
        )
      else
        _Person(
          // No user directory exists to turn an owner's uid into a name, so
          // the uid is shown as-is rather than dressed up as a person.
          initials: '?',
          name: 'Notebook owner',
          detail: notebook.ownerId.isEmpty ? null : notebook.ownerId,
          role: 'Owner',
          isOwner: true,
        ),
    ];

    final raw = doc['collaborators'];
    final byKey = <String, Collaborator>{};
    if (raw is List) {
      for (final entry in raw) {
        if (entry is! Map) continue;
        final c = Collaborator.fromMap(Map<String, dynamic>.from(entry));
        final key = c.email.isNotEmpty ? c.email.toLowerCase() : c.uid;
        if (key.isEmpty) continue;
        byKey[key] = c;
      }
    }

    final seenUids = <String>{notebook.ownerId};
    for (final c in byKey.values) {
      if (c.uid.isNotEmpty && !seenUids.add(c.uid)) continue;
      final isMe = (myUid != null && c.uid == myUid) ||
          (myEmail != null && c.email.toLowerCase() == myEmail);
      if (isMe && ownerIsMe) continue; // already listed, as the owner
      people.add(_Person(
        initials: _initials(c.email.isNotEmpty ? c.email : c.uid),
        name: isMe ? 'You' : (c.email.isNotEmpty ? c.email : c.uid),
        detail: isMe && c.email.isNotEmpty ? c.email : null,
        role: _roleLabel(c.role),
      ));
    }

    // A uid on the notebook with no `collaborators` entry carries no role, so
    // its row leaves the role slot empty. In practice this list is empty —
    // nothing writes collaboratorUids after creation — but it is still real
    // data on the model, and dropping it silently would be worse than showing
    // it plainly.
    for (final uid in notebook.collaboratorUids) {
      if (uid.isEmpty || !seenUids.add(uid)) continue;
      people.add(_Person(
        initials: '?',
        name: uid == myUid ? 'You' : uid,
        role: null,
      ));
    }
    return people;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final notebook = widget.notebook;
    final docAsync = ref.watch(_notebookDocProvider(notebook.id));

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(MarioSpace.x6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 620),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MarioRadius.card),
            boxShadow: marioShadow(context, level: 2),
          ),
          child: MarioGlass(
            borderRadius: BorderRadius.circular(MarioRadius.card),
            border: Border.all(color: marioDivider(context)),
            // A heavy blur buys the transparency back: once the page behind is
            // smeared to a wash the veil no longer has to be near-opaque to
            // carry text. Both are stated outright rather than left to the
            // chrome defaults — this surface has to be READ through, and the
            // dark grounds' ~6% chrome veil would leave it unreadable.
            blur: 56,
            tint: scheme.surfaceContainerHigh,
            strength: 0.72,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(MarioRadius.card),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(scheme, text),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                          MarioSpace.x6, MarioSpace.x6, MarioSpace.x6, 0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const MarioKicker('Email address'),
                          const SizedBox(height: MarioSpace.x2),
                          _inviteRow(scheme, text),
                          const SizedBox(height: MarioSpace.x6),
                          const MarioKicker('People with access'),
                          const SizedBox(height: MarioSpace.x3),
                          ...switch (docAsync) {
                            AsyncData(:final value) => [
                                for (final person in _people(value))
                                  _PersonRow(person: person),
                              ],
                            AsyncError() => [
                                Text(
                                  'Could not load who has access.',
                                  style: text.bodySmall
                                      ?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                              ],
                            _ => [
                                const Padding(
                                  padding:
                                      EdgeInsets.only(bottom: MarioSpace.x2),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: MarioLoader(size: 18),
                                  ),
                                ),
                              ],
                          },
                          const SizedBox(height: MarioSpace.x6),
                        ],
                      ),
                    ),
                  ),
                  _footer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme, TextTheme text) {
    final notebook = widget.notebook;
    return Container(
      padding: const EdgeInsets.fromLTRB(
          MarioSpace.x6, MarioSpace.x6, MarioSpace.x6, MarioSpace.x4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: marioDivider(context))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: notebook.color,
              shape: BoxShape.circle,
            ),
            // The label palette is six mid-tones picked to hold up on cream and
            // on navy alike, so the ink on the dot is the mark's navy on every
            // ground — it is reading against the notebook's colour, not against
            // whichever ground is behind it.
            child: Text(
              _initials(notebook.name),
              style: text.titleLarge?.copyWith(
                fontSize: 17,
                color: MarioColors.navy,
              ),
            ),
          ),
          const SizedBox(width: MarioSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Share ${notebook.name}',
                  style: text.headlineSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: MarioSpace.x1),
                Text(
                  _accessLine(_pageCount()),
                  style: text.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inviteRow(ColorScheme scheme, TextTheme text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: TextField(
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              // Matched to the input theme's own 14px hint, so the address and
              // the placeholder it replaces are the same size.
              style: text.bodySmall?.copyWith(fontSize: 14),
              onSubmitted:
                  (_saving || !_canInvite) ? null : (_) => _invite(),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'someone@example.com',
              ),
            ),
          ),
        ),
        const SizedBox(width: MarioSpace.x2),
        _roleField(scheme, text),
        const SizedBox(width: MarioSpace.x2),
        ElevatedButton(
          // Sized to the field beside it rather than wrapped in a fixed box:
          // the default `padded` tap target pads a button out to 48, which
          // would overflow a 44 slot instead of filling it.
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(0, 44),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: (_saving || !_canInvite) ? null : _invite,
          child: _saving
              // Disabled while saving, so the fill is onSurface@12% rather
              // than primary; the theme default is what stays legible on it.
              ? const MarioLoader(size: 18)
              : const Text('Invite'),
        ),
      ],
    );
  }

  /// The role for the *next* invite. Pill-cased to sit with the input theme,
  /// but the same [DropdownButton] and the same two options as before.
  Widget _roleField(ColorScheme scheme, TextTheme text) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: MarioSpace.x3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(MarioRadius.pill),
        border: Border.all(color: scheme.outline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<CollaboratorRole>(
          value: _role,
          isDense: true,
          borderRadius: BorderRadius.circular(MarioRadius.md),
          dropdownColor: scheme.surfaceContainerHigh,
          focusColor: Colors.transparent,
          style: text.bodySmall,
          icon: Icon(Icons.expand_more,
              size: 18, color: scheme.onSurfaceVariant),
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
      ),
    );
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: MarioSpace.x6, vertical: MarioSpace.x3),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: marioDivider(context))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            // Invites commit as they are sent, so there is nothing here to
            // cancel — this only dismisses, which is what the old Cancel did.
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              // The theme paints text buttons in the primary, and the primary
              // is gold — 1.59:1 on the light grounds. Gold is a fill colour
              // here, not an ink one, so the light grounds take the gold ramp's
              // dark step instead and only the dark grounds use the primary.
              foregroundColor: marioMode(context).isDark
                  ? Theme.of(context).colorScheme.primary
                  : MarioColors.accent700,
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person});

  final _Person person;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: MarioSpace.x3),
      child: Row(
        children: [
          MarioAvatar(initials: person.initials, size: 34),
          const SizedBox(width: MarioSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  person.name,
                  style: text.labelLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (person.detail != null)
                  Text(
                    person.detail!,
                    style: text.bodySmall?.copyWith(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: MarioSpace.x2),
          // Static, not a dropdown: nothing in the app can rewrite a role once
          // it is in the `collaborators` array. See the library comment.
          if (person.role != null)
            MarioTag(
              person.role!,
              tone: person.isOwner ? MarioTagTone.accent : MarioTagTone.neutral,
            ),
        ],
      ),
    );
  }
}
