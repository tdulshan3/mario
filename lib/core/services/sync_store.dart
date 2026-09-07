/// Where offline work is kept: the outbox of changes waiting for the server,
/// and the last snapshot of the notebook tree the server sent.
///
/// Plain JSON files under the app's support directory, one per name, written
/// temp-then-rename and one at a time — the same discipline the page-content
/// cache and the AI artifact store use, so a crash mid-write leaves the old
/// file rather than half of a new one. An in-memory store stands in for tests.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

abstract class SyncStore {
  Future<Map<String, dynamic>?> read(String name);
  Future<void> write(String name, Map<String, dynamic> data);
}

/// `<app support dir>/sync/<name>.json`.
class FileSyncStore implements SyncStore {
  Future<Directory>? _dirFuture;
  Future<void> _queue = Future.value();

  Future<Directory> _dir() => _dirFuture ??= () async {
        final base = await getApplicationSupportDirectory();
        final dir = Directory('${base.path}/sync');
        if (!await dir.exists()) await dir.create(recursive: true);
        return dir;
      }();

  String _safe(String name) => name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  @override
  Future<Map<String, dynamic>?> read(String name) async {
    if (kIsWeb) return null;
    try {
      final f = File('${(await _dir()).path}/${_safe(name)}.json');
      if (!await f.exists()) return null;
      final decoded = jsonDecode(await f.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null; // a corrupt file behaves as an empty one
    }
  }

  @override
  Future<void> write(String name, Map<String, dynamic> data) {
    if (kIsWeb) return Future.value();
    final encoded = jsonEncode(data);
    return _queue = _queue.then((_) async {
      try {
        final target = File('${(await _dir()).path}/${_safe(name)}.json');
        final tmp = File('${target.path}.tmp');
        await tmp.writeAsString(encoded, flush: true);
        await tmp.rename(target.path);
      } catch (_) {
        // Best-effort: the in-memory copy still serves this session.
      }
    });
  }
}

/// Holds everything in memory. For tests, and for the web, which has no
/// folder to keep files in.
class MemorySyncStore implements SyncStore {
  final files = <String, Map<String, dynamic>>{};

  @override
  Future<Map<String, dynamic>?> read(String name) async {
    final data = files[name];
    if (data == null) return null;
    return jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
  }

  @override
  Future<void> write(String name, Map<String, dynamic> data) async {
    files[name] = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
  }
}

/// A document id minted on this device.
///
/// Firestore would mint one for us, but only once it has been reached — and
/// a page created on a train needs an id now: for the sidebar to show it, the
/// editor to open it, and the outbox to name it when the server is back.
/// Time first, so ids sort by creation, then ten random letters, so two
/// devices minting in the same millisecond cannot collide.
String newClientId(String prefix) {
  final rnd = Random.secure();
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final tail = List.generate(
    10,
    (_) => alphabet[rnd.nextInt(alphabet.length)],
  ).join();
  return '${prefix}_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}$tail';
}
