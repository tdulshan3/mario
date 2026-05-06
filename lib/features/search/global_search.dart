/// Global search — title-only first pass over notebook/section/page indexes.
///
/// Full-text content search is deferred until the Drift FTS5 index is built;
/// this modal already covers most of the OneNote "where is that page?" use case.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/note_page.dart';
import '../../ui/colors.dart';
import '../shell/shell_state.dart';

class _SearchHit {
  final String notebookId;
  final String notebookName;
  final String sectionId;
  final String? sectionName;
  final NotePage page;

  const _SearchHit({
    required this.notebookId,
    required this.notebookName,
    required this.sectionId,
    required this.sectionName,
    required this.page,
  });
}

void showGlobalSearch(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => const _GlobalSearchDialog(),
  );
}

class _GlobalSearchDialog extends ConsumerStatefulWidget {
  const _GlobalSearchDialog();

  @override
  ConsumerState<_GlobalSearchDialog> createState() =>
      _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends ConsumerState<_GlobalSearchDialog> {
  String _query = '';

  Future<List<_SearchHit>> _search() async {
    final notebooks = ref.read(notebooksStreamProvider).valueOrNull ?? [];
    final hits = <_SearchHit>[];
    final lower = _query.toLowerCase();
    if (lower.isEmpty) return hits;

    for (final nb in notebooks) {
      final sections =
          ref.read(sectionsStreamProvider(nb.id)).valueOrNull ?? [];
      for (final s in sections) {
        final pages = ref
                .read(pagesStreamProvider(
                    (notebookId: nb.id, sectionId: s.id)))
                .valueOrNull ??
            [];
        for (final p in pages) {
          final hay =
              '${nb.name} ${s.name} ${p.title}'.toLowerCase();
          if (hay.contains(lower)) {
            hits.add(_SearchHit(
              notebookId: nb.id,
              notebookName: nb.name,
              sectionId: s.id,
              sectionName: s.name,
              page: p,
            ));
          }
        }
      }
    }
    return hits;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 480),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: const InputDecoration(
                  hintText: 'Search notebooks, sections, pages…',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<_SearchHit>>(
                  future: _search(),
                  builder: (context, snap) {
                    final hits = snap.data ?? const [];
                    if (_query.isEmpty) {
                      return _Hint(
                          'Search by title — full-text search lands with the FTS5 index.');
                    }
                    if (hits.isEmpty) {
                      return _Hint('No matches.');
                    }
                    return ListView.builder(
                      itemCount: hits.length,
                      itemBuilder: (_, i) {
                        final h = hits[i];
                        return ListTile(
                          dense: true,
                          title: Text(h.page.title,
                              style:
                                  GoogleFonts.inter(fontWeight: FontWeight.w500)),
                          subtitle: Text(
                              '${h.notebookName} › ${h.sectionName ?? ''}',
                              style: GoogleFonts.inter(fontSize: 11)),
                          onTap: () {
                            ref
                                .read(selectionProvider.notifier)
                                .selectNotebook(h.notebookId);
                            ref
                                .read(selectionProvider.notifier)
                                .selectSection(h.sectionId);
                            ref
                                .read(selectionProvider.notifier)
                                .selectPage(h.page.id);
                            Navigator.of(context).pop();
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? MarioColors.onSurfaceMutedDark : MarioColors.onSurfaceMuted;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 12, color: muted),
        ),
      ),
    );
  }
}
