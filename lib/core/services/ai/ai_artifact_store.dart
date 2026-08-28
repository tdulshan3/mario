/// AiArtifactStore — where summaries, saved answers, quizzes and marks live.
///
/// They go to Google Drive, in the same private `appDataFolder` as the notes
/// themselves: one JSON file per notebook, named `mario-ai-<notebookId>.json`.
/// That means a quiz generated on the desktop is there on another machine, and
/// a summary survives a reinstall. It also means the data is exactly as
/// portable as the notes it describes — if the notes sync, the study material
/// syncs with them.
///
/// The access pattern follows [PageContentRepository] deliberately, because
/// the constraints are the same:
///
///  * **Local first.** Every read is served from an on-disk cache, so opening
///    the quiz panel does not wait on a network round-trip, and everything
///    keeps working on a train.
///  * **Write-through, local wins.** A mutation is written to the cache before
///    it is uploaded. If the upload fails the change is still there and the
///    next save pushes it; a failed upload never costs the user a mark they
///    just earned.
///  * **Serialized mutations.** Every change is read-modify-write on a whole
///    notebook's data, so two features mutating at once — a summary landing
///    while a quiz is being graded — would otherwise silently drop one of
///    them. All mutations for a notebook queue on one chain.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import '../drive_service.dart';
import 'ai_artifacts.dart';

class AiArtifactStore {
  AiArtifactStore(this._drive);

  final DriveService _drive;

  final _memory = <String, NotebookAiData>{};
  final _driveIds = <String, String>{};
  final _locks = <String, Future<void>>{};

  /// Notebooks whose local copy is ahead of Drive because an upload failed.
  /// Retried on the next mutation rather than on a timer — the user is
  /// probably still working, and a retry storm helps nobody.
  final _dirty = <String>{};

  Future<Directory>? _dirFuture;

  static String _fileName(String notebookId) => 'mario-ai-$notebookId.json';

  Future<Directory> _cacheDir() {
    return _dirFuture ??= () async {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/ai_artifacts');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }();
  }

  File _cacheFile(Directory dir, String notebookId) =>
      File('${dir.path}/${_safe(notebookId)}.json');

  String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  /// Reads a notebook's artifacts — memory, then disk, then Drive.
  Future<NotebookAiData> load(String notebookId) async {
    final cached = _memory[notebookId];
    if (cached != null) return cached;

    final local = await _readLocal(notebookId);
    if (local != null) {
      _memory[notebookId] = local;
      // Refresh from Drive in the background; a newer remote copy replaces the
      // cache for next time, but never interrupts this read.
      unawaited(_refreshFromDrive(notebookId));
      return local;
    }

    final remote = await _readDrive(notebookId);
    final data = remote ?? const NotebookAiData();
    _memory[notebookId] = data;
    await _writeLocal(notebookId, data);
    return data;
  }

  /// Applies [mutate] to a notebook's data and persists the result.
  ///
  /// Queued per notebook: the read, the change and the write happen with no
  /// other mutation interleaved, so concurrent callers cannot clobber each
  /// other's work.
  Future<NotebookAiData> update(
    String notebookId,
    NotebookAiData Function(NotebookAiData) mutate,
  ) {
    final previous = _locks[notebookId] ?? Future<void>.value();
    final completer = Completer<NotebookAiData>();

    _locks[notebookId] = previous.then((_) async {
      try {
        final current = await load(notebookId);
        final next = mutate(current);
        _memory[notebookId] = next;
        await _writeLocal(notebookId, next);
        await _pushToDrive(notebookId, next);
        completer.complete(next);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });

    return completer.future;
  }

  // ---------------------------------------------------------------- helpers

  Future<NoteSummary?> summaryFor(String notebookId, String pageId) async =>
      (await load(notebookId)).summaries[pageId];

  /// Stores a summary, replacing any previous one for the same page.
  Future<void> putSummary(String notebookId, NoteSummary summary) => update(
        notebookId,
        (d) => d.copyWith(
          summaries: {...d.summaries, summary.pageId: summary},
        ),
      );

  /// Appends a saved question and answer.
  ///
  /// Capped at the most recent 200 per notebook: this file is downloaded on
  /// every cold start, and an unbounded chat log would eventually make opening
  /// the panel slow for a feature nobody scrolls back that far in.
  Future<void> addAsk(String notebookId, AskEntry entry) => update(
        notebookId,
        (d) => d.copyWith(
            asks: [...d.asks, entry]
                .reversed
                .take(200)
                .toList()
                .reversed
                .toList()),
      );

  Future<void> markAskInserted(String notebookId, String askId) => update(
        notebookId,
        (d) => d.copyWith(asks: [
          for (final a in d.asks)
            if (a.id == askId) a.copyWith(insertedIntoPage: true) else a,
        ]),
      );

  Future<void> addQuiz(String notebookId, Quiz quiz) => update(
        notebookId,
        (d) => d.copyWith(quizzes: [...d.quizzes, quiz]),
      );

  Future<void> putAttempt(String notebookId, QuizAttempt attempt) => update(
        notebookId,
        (d) => d.copyWith(attempts: [
          for (final a in d.attempts)
            if (a.id != attempt.id) a,
          attempt,
        ]),
      );

  /// Drops everything derived from a page that no longer exists.
  Future<void> forgetPage(String notebookId, String pageId) =>
      update(notebookId, (d) => d.withoutPage(pageId));

  /// Drops a whole notebook's artifacts — local cache and Drive file both.
  ///
  /// Called when the notebook itself is deleted, so its study material does
  /// not outlive the notes it was derived from.
  Future<void> forgetNotebook(String notebookId) async {
    _memory.remove(notebookId);
    _dirty.remove(notebookId);
    if (!kIsWeb) {
      try {
        final file = _cacheFile(await _cacheDir(), notebookId);
        if (await file.exists()) await file.delete();
      } catch (_) {/* best-effort */}
    }
    try {
      final id = await _resolveDriveId(notebookId);
      if (id != null) await _drive.deleteFile(id);
    } catch (_) {/* offline: the file is orphaned, not the user's problem */}
    _driveIds.remove(notebookId);
  }

  // ------------------------------------------------------------ persistence

  Future<NotebookAiData?> _readLocal(String notebookId) async {
    if (kIsWeb) return null; // no filesystem; Drive is the only store
    try {
      final f = _cacheFile(await _cacheDir(), notebookId);
      if (!await f.exists()) return null;
      final decoded = jsonDecode(await f.readAsString());
      return decoded is Map<String, dynamic>
          ? NotebookAiData.fromJson(decoded)
          : null;
    } catch (_) {
      return null; // a corrupt entry behaves as a miss, same as PageContentCache
    }
  }

  Future<void> _writeLocal(String notebookId, NotebookAiData data) async {
    if (kIsWeb) return;
    try {
      final dir = await _cacheDir();
      final file = _cacheFile(dir, notebookId);
      // Write-then-rename: a crash mid-write must not leave a half-JSON file
      // where a valid one used to be.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(data.toJson()), flush: true);
      await tmp.rename(file.path);
    } catch (_) {/* best-effort, same contract as the page cache */}
  }

  Future<NotebookAiData?> _readDrive(String notebookId) async {
    try {
      final id = await _resolveDriveId(notebookId);
      if (id == null) return null;
      final json = await _drive.readPageFile(id);
      return NotebookAiData.fromJson(json);
    } catch (_) {
      return null; // signed out, offline, or the file is gone
    }
  }

  Future<void> _pushToDrive(String notebookId, NotebookAiData data) async {
    try {
      final existing = await _resolveDriveId(notebookId);
      if (existing == null) {
        // createPageFile appends ".json" itself, so pass the stem.
        final created = await _drive.createPageFile(
          'mario-ai-$notebookId',
          data.toJson(),
        );
        _driveIds[notebookId] = created;
      } else {
        await _drive.updatePageFile(existing, data.toJson());
      }
      _dirty.remove(notebookId);
    } catch (_) {
      // Offline or signed out. The local copy is already written, so nothing is
      // lost; flag it and the next mutation re-uploads the whole file.
      _dirty.add(notebookId);
    }
  }

  Future<String?> _resolveDriveId(String notebookId) async {
    final known = _driveIds[notebookId];
    if (known != null) return known;
    final found = await _drive.findFileByName(_fileName(notebookId));
    if (found != null) _driveIds[notebookId] = found;
    return found;
  }

  Future<void> _refreshFromDrive(String notebookId) async {
    // A local copy that has not been uploaded yet is *newer* than Drive by
    // definition — overwriting it with the remote version would discard the
    // user's most recent work.
    if (_dirty.contains(notebookId)) return;

    final remote = await _readDrive(notebookId);
    if (remote == null) return;

    // Join the mutation chain rather than writing behind it. The download takes
    // seconds; a quiz saved, or a mark recorded, while it was in flight is
    // already in memory and on disk, and a bare assignment here would replace
    // it with the pre-save copy that Drive returned. That is silent data loss —
    // the user sees the mark, closes the panel, and it is gone.
    await update(notebookId, (current) {
      // Only take the remote copy if nothing changed underneath us.
      if (!identical(current, _memory[notebookId])) return current;
      return _hasMoreThan(remote, current) ? remote : current;
    });
  }

  /// Whether [remote] is a superset worth adopting.
  ///
  /// Deliberately conservative: with no per-record timestamps to merge on, the
  /// only safe rule is to prefer whichever copy holds strictly more, and to keep
  /// the local one whenever that is ambiguous. Losing an unsynced mark is much
  /// worse than briefly missing one made on another device, which the next
  /// refresh picks up anyway.
  bool _hasMoreThan(NotebookAiData remote, NotebookAiData local) =>
      remote.asks.length >= local.asks.length &&
      remote.quizzes.length >= local.quizzes.length &&
      remote.attempts.length >= local.attempts.length &&
      remote.summaries.length >= local.summaries.length &&
      (remote.asks.length + remote.quizzes.length + remote.attempts.length >
          local.asks.length + local.quizzes.length + local.attempts.length);

  /// True when a notebook has local changes Drive has not accepted yet.
  bool isPendingUpload(String notebookId) => _dirty.contains(notebookId);
}
