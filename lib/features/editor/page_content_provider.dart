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

import '../../core/services/drive_service.dart';

final pageContentProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, driveFileId) async {
  final drive = GetIt.I<DriveService>();
  final raw = await drive.readPageFile(driveFileId);
  return raw.containsKey('document') ? raw : <String, dynamic>{'document': raw};
});
