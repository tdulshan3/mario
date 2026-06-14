/// pageContentProvider — loads a page's raw Drive JSON.
///
/// Returns the raw map rather than a parsed [afe.Document]. The document is
/// owned (and disposed) by the editor State that mounts it; if we cached a
/// Document here, navigating away from a page would dispose it and the next
/// remount would hit "Node was used after dispose" when AppFlowy tried to
/// subscribe to its now-defunct nodes.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';

import '../../core/services/page_content_repository.dart';

/// `autoDispose` so navigating away from a page clears the in-memory JSON; the
/// next visit re-reads through [PageContentRepository]. Without this, the
/// in-memory cache wins after a paste-then-switch-back round trip — the editor
/// would mount with the pre-paste snapshot.
///
/// The repository serves from the local disk cache first (instant), so this is
/// no longer a Drive round-trip on every open; it revalidates against Drive in
/// the background and refreshes the cache for next time.
final pageContentProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
        (ref, driveFileId) async {
  final repo = GetIt.I<PageContentRepository>();
  final raw = await repo.load(driveFileId);
  return raw.containsKey('document') ? raw : <String, dynamic>{'document': raw};
});
