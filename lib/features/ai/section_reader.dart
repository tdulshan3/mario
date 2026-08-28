/// Reading a whole section, for quizzes and section-wide questions.
///
/// A section is N pages, and each page's content is a separate file in Google
/// Drive. Reading forty of them naively means forty sequential round-trips, or
/// forty parallel ones — and Drive answers a burst of parallel requests with
/// `403 userRateLimitExceeded`, which is exactly why [ConcurrencyGate] already
/// exists in this codebase for image sync. It is reused here for the same
/// reason.
///
/// The saved summaries are what make this affordable on a second run. A page
/// whose cached summary still matches its content contributes the summary
/// rather than its full text: far fewer tokens, no re-reading, and correct,
/// because the hash guarantees the summary describes the current page. Pages
/// that changed since their summary was made are read in full again.
library;

import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart' as afe;

import '../../core/models/note_page.dart';
import '../../core/services/ai/ai_artifacts.dart';
import '../../core/services/ai/ai_artifact_store.dart';
import '../../core/services/concurrency_gate.dart';
import '../../core/services/page_content_repository.dart';
import 'note_context.dart';

/// One page's contribution to a section read.
class SectionPageText {
  const SectionPageText({
    required this.pageId,
    required this.title,
    required this.note,
    required this.fromCachedSummary,
  });

  final String pageId;
  final String title;
  final NoteText note;

  /// True when this came from a saved summary rather than the page itself.
  final bool fromCachedSummary;
}

class SectionRead {
  const SectionRead({
    required this.pages,
    required this.failed,
  });

  final List<SectionPageText> pages;

  /// Titles of pages that could not be read — offline, or a missing Drive
  /// file. Surfaced rather than swallowed, so a quiz built from eight of ten
  /// pages does not claim to cover the section.
  final List<String> failed;

  bool get isEmpty => pages.every((p) => p.note.isEmpty);

  int get cachedCount => pages.where((p) => p.fromCachedSummary).length;

  /// Flattens to one document, with each page under its own heading so the
  /// model can attribute a fact to the page it came from.
  NoteText merge({required String title}) {
    final blocks = <NoteBlock>[];
    var index = 0;
    for (final p in pages) {
      if (p.note.isEmpty) continue;
      blocks.add(NoteBlock(
        nodeId: 'page-${p.pageId}',
        path: [index++],
        type: 'heading',
        text: '## ${p.title}',
        headingLevel: 2,
      ));
      for (final b in p.note.blocks) {
        blocks.add(NoteBlock(
          nodeId: b.nodeId,
          path: [index++],
          type: b.type,
          text: b.text,
          headingLevel: b.headingLevel,
        ));
      }
    }
    return NoteText(title: title, blocks: blocks);
  }
}

class SectionReader {
  SectionReader(this._content, this._artifacts);

  final PageContentRepository _content;
  final AiArtifactStore _artifacts;

  /// Four at a time — the same ceiling AssetSyncService uses against Drive.
  static const _parallelism = 4;

  /// Reads [pages], preferring a valid cached summary over a full fetch.
  ///
  /// [onProgress] is called with (done, total) so the panel's "Reading the
  /// section" step can count up instead of sitting still for thirty seconds.
  Future<SectionRead> read({
    required String notebookId,
    required List<NotePage> pages,
    void Function(int done, int total)? onProgress,
    bool useCachedSummaries = true,
  }) async {
    final gate = ConcurrencyGate(_parallelism);
    final artifacts =
        useCachedSummaries ? await _artifacts.load(notebookId) : null;

    final results = List<SectionPageText?>.filled(pages.length, null);
    final failed = <String>[];
    var done = 0;

    await Future.wait([
      for (var i = 0; i < pages.length; i++)
        gate.run(() async {
          final page = pages[i];
          try {
            results[i] = await _readOne(page, artifacts?.summaries[page.id]);
          } catch (_) {
            failed.add(page.title);
          } finally {
            onProgress?.call(++done, pages.length);
          }
        }),
    ]);

    return SectionRead(
      pages: [
        for (final r in results)
          if (r != null) r
      ],
      failed: failed,
    );
  }

  Future<SectionPageText> _readOne(NotePage page, NoteSummary? cached) async {
    final fileId = page.driveFileId;
    if (fileId == null) {
      return SectionPageText(
        pageId: page.id,
        title: page.title,
        note: NoteText(title: page.title, blocks: const []),
        fromCachedSummary: false,
      );
    }

    // revalidate: false — see PageContentRepository.load. The gate above
    // limits how many pages we *fetch* at once, but background revalidation is
    // detached and would escape it entirely.
    final raw = await _content.load(fileId, revalidate: false);
    final docMap = raw.containsKey('document') ? raw : {'document': raw};
    final document = afe.Document.fromJson(Map<String, dynamic>.from(docMap));
    final note = extractNoteText(document, title: page.title);

    // A summary is only usable if it describes *this* text. The hash is what
    // makes that a guarantee rather than a hope — see NoteSummary.
    if (cached != null && cached.matches(note.render())) {
      return SectionPageText(
        pageId: page.id,
        title: page.title,
        note: NoteText(
          title: page.title,
          blocks: [
            NoteBlock(
              nodeId: 'summary-${page.id}',
              path: const [0],
              type: 'paragraph',
              text: cached.summary,
            ),
            for (var i = 0; i < cached.keyPoints.length; i++)
              NoteBlock(
                nodeId: 'summary-${page.id}-$i',
                path: [i + 1],
                type: 'bulleted_list',
                text: '- ${cached.keyPoints[i]}',
              ),
          ],
        ),
        fromCachedSummary: true,
      );
    }

    return SectionPageText(
      pageId: page.id,
      title: page.title,
      note: note,
      fromCachedSummary: false,
    );
  }
}
