/// pageContentProvider — loads a page's Drive JSON into an AppFlowy Document.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';

import '../../core/services/drive_service.dart';

/// Loaded by Drive file ID so a page rename doesn't bust the cache.
final pageContentProvider =
    FutureProvider.family<afe.Document, String>((ref, driveFileId) async {
  final drive = GetIt.I<DriveService>();
  final raw = await drive.readPageFile(driveFileId);
  // Page JSON wraps the AppFlowy document shape with optional metadata fields.
  final doc = raw.containsKey('document')
      ? raw
      : <String, dynamic>{'document': raw};
  return afe.Document.fromJson(Map<String, dynamic>.from(doc));
});
