/// MarioImageBlock — drop-in image block with an inline OCR shadow panel and
/// Drive-backed cloud sync for the picture itself.
///
/// Replaces the stock AppFlowy image builder. Trades the resizable image's
/// drag-handles + alignment menu for a lighter wrapper that runs OCR through
/// [OcrService] and shows the detected lines as click-to-insert chips.
///
/// The block carries two references to the same picture and they are not
/// interchangeable:
///
///  * [MarioImageKeys.url] is where the file sits on *this* machine. It is
///    written once, by whichever device inserted the image, and is meaningless
///    everywhere else — which is exactly why images used to vanish on a second
///    device even though the note itself synced fine.
///  * [MarioImageKeys.driveId] is the picture's id in the Drive appDataFolder.
///    It means the same thing everywhere, so it is the reference that actually
///    travels. [AssetSyncService] turns it back into a local file.
///
/// `url` is never rewritten to suit another device: device B resolves the id
/// into its own cache and leaves the originating device's path untouched, so
/// two machines editing the same note don't fight over the attribute.
library;

import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/services/asset_sync_service.dart';
import '../../../core/services/ocr_service.dart';
import '../../../ui/colors.dart';
import '_safe_transaction.dart';
import 'block_context_menu.dart';

class MarioImageKeys {
  const MarioImageKeys._();
  static const String type = 'image';
  static const String url = 'url';

  /// Google Drive appDataFolder id of the image bytes — the device-independent
  /// half of the reference. Absent on notes written before image sync existed;
  /// those get one minted the first time the block renders on a signed-in
  /// device (see `_syncAsset`).
  static const String driveId = 'drive_id';

  static const String width = 'width';
  static const String ocrLines = 'ocr_lines';
  static const String ocrDismissed = 'ocr_dismissed';
}

class MarioImageBlockBuilder extends afe.BlockComponentBuilder {
  MarioImageBlockBuilder({super.configuration});

  @override
  afe.BlockComponentWidget build(afe.BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return MarioImageBlockWidget(
      key: node.key,
      node: node,
      showActions: showActions(node),
      configuration: configuration,
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
    );
  }

  @override
  bool validate(afe.Node node) =>
      node.attributes[MarioImageKeys.url] is String ||
      node.attributes[MarioImageKeys.driveId] is String;
}

class MarioImageBlockWidget extends afe.BlockComponentStatefulWidget {
  const MarioImageBlockWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.configuration = const afe.BlockComponentConfiguration(),
  });

  @override
  State<MarioImageBlockWidget> createState() => _MarioImageBlockWidgetState();
}

class _MarioImageBlockWidgetState extends State<MarioImageBlockWidget>
    with afe.SelectableMixin, afe.BlockComponentConfigurable {
  bool _ocrRunning = false;

  /// True while this device is pulling the bytes down from Drive for the first
  /// time — the state a note opened on a brand-new machine starts in.
  bool _downloading = false;

  /// Memoised result of [_resolveSync], with the attribute pair it was
  /// computed from. Resolution touches the filesystem (`existsSync`), and
  /// `build` runs on every editor notification, so recomputing per frame would
  /// put a syscall in the typing path.
  String? _resolvedKey;
  String? _resolvedPath;

  /// The attribute pair [_ensureLocalCopy] has already acted on, so a rebuild
  /// doesn't re-fire a download that is already done or in flight.
  String? _syncedKey;

  final GlobalKey _imageKey = GlobalKey();
  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  AssetSyncService get _assets => GetIt.I<AssetSyncService>();

  @override
  afe.BlockComponentConfiguration get configuration => widget.configuration;

  @override
  afe.Node get node => widget.node;

  String get _src =>
      (widget.node.attributes[MarioImageKeys.url] as String?) ?? '';

  String? get _driveId {
    final v = widget.node.attributes[MarioImageKeys.driveId];
    return (v is String && v.isNotEmpty) ? v : null;
  }

  /// Identity of the picture this block currently points at. Both halves
  /// matter: the id can arrive on a block that already had a url (an upload
  /// finishing), and the url can be all there is (a note from before sync).
  String get _assetKey => '${_driveId ?? ''}|$_src';

  List<String> get _ocrLines {
    final raw = widget.node.attributes[MarioImageKeys.ocrLines];
    if (raw is List) return raw.whereType<String>().toList(growable: false);
    return const [];
  }

  bool get _dismissed =>
      (widget.node.attributes[MarioImageKeys.ocrDismissed] as bool?) ?? false;

  bool get _ocrAlreadyKnown =>
      widget.node.attributes.containsKey(MarioImageKeys.ocrLines);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureLocalCopy();
      _maybeRunOcr();
    });
  }

  @override
  void didUpdateWidget(covariant MarioImageBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The node is mutable and AppFlowy reuses this State across attribute
    // changes, so a fresh id (or a replaced url) shows up here rather than in
    // a new State. Both calls no-op when nothing moved.
    _ensureLocalCopy();
    _maybeRunOcr();
  }

  // ---------- Asset resolution ----------

  /// The file this block can actually draw right now, or null if there isn't
  /// one yet. Never touches the network.
  ///
  /// The Drive id is consulted first because it is the reference that is true
  /// everywhere; `url` is the fallback for the device that inserted the image
  /// (and for notes predating sync). Checking the id first also means that
  /// after a device re-downloads a picture whose original local copy was
  /// deleted, the cached copy wins.
  String? get _localPath {
    final key = _assetKey;
    if (key != _resolvedKey) {
      _resolvedKey = key;
      _resolvedPath = _resolveSync();
    }
    return _resolvedPath;
  }

  String? _resolveSync() {
    final id = _driveId;
    if (id != null) {
      final hit = _assets.cachedPath(id);
      if (hit != null) return hit;
    }
    final src = _src;
    if (src.isNotEmpty && _isLocalFile(src)) return src;
    return null;
  }

  /// Make sure this device has the bytes, downloading them if the note points
  /// at an asset this machine has never seen.
  ///
  /// Only the download half lives here. Uploads belong to [AssetSweeper],
  /// which walks the whole document: blocks below the fold are never built by
  /// the editor's lazy list, so a block-driven upload would quietly skip
  /// exactly the images the user didn't scroll past.
  ///
  /// A failed download clears [_syncedKey] so the Retry button can try again;
  /// nothing retries on a timer, because an offline user shouldn't have a
  /// background loop hammering Drive.
  Future<void> _ensureLocalCopy() async {
    if (kIsWeb) return;
    final key = _assetKey;
    if (_syncedKey == key) return;
    _syncedKey = key;

    final id = _driveId;
    if (id == null) return; // nothing to fetch; the sweeper will mint an id
    if (_assets.cachedPath(id) != null) return; // already on this disk

    final src = _src;
    if (src.isNotEmpty && _isLocalFile(src)) {
      // We have the bytes but the index lost the mapping (corrupt index, or an
      // upload that finished after the app was killed mid-stamp). Re-point the
      // index instead of re-downloading them.
      await _assets.adoptLocal(id, src);
      if (!mounted) return;
      setState(() => _resolvedKey = null);
      return;
    }

    if (!mounted) return;
    setState(() => _downloading = true);
    // The extension comes from the originating device's url, which synced with
    // the note — supplying it saves a metadata round-trip per image.
    final path =
        await _assets.ensureLocal(id, extensionHint: src.isEmpty ? null : src);
    if (!mounted) return;
    setState(() {
      _downloading = false;
      _resolvedKey = null; // force a re-resolve; the cache may now hit
    });
    if (path == null) {
      _syncedKey = null; // offline or deleted — the Retry button can re-ask
    } else {
      _maybeRunOcr();
    }
  }

  Future<void> _retryAsset() async {
    _syncedKey = null;
    _resolvedKey = null;
    await _ensureLocalCopy();
  }

  /// Whether this picture is still local-only. Derived, not tracked: an image
  /// with local bytes and no Drive id has not reached the cloud, whether the
  /// sweeper hasn't got to it yet or can't (offline, signed out).
  ///
  /// Reads through [_localPath] rather than re-testing the file, so the check
  /// costs nothing on the build path — this is evaluated on every frame the
  /// block paints.
  bool get _awaitingUpload => !kIsWeb && _driveId == null && _localPath != null;

  Future<void> _maybeRunOcr() async {
    if (!mounted) return;
    if (_ocrAlreadyKnown || _ocrRunning) return;
    final ocr = GetIt.I<OcrService>();
    if (!ocr.isAvailable) return;
    // OCR reads a file off the disk, so it needs the resolved copy — on a
    // second device `url` points at a path that was never here.
    final path = _localPath;
    if (path == null) return;

    setState(() => _ocrRunning = true);
    List<String> lines = const [];
    try {
      lines = await ocr.extractText(path);
    } catch (_) {}
    if (!mounted) return;

    final editorState = context.read<afe.EditorState>();
    await safeApply(editorState, (tx) {
      tx.updateNode(widget.node, {
        MarioImageKeys.ocrLines: lines,
        MarioImageKeys.ocrDismissed: false,
      });
    }, background: true);
    if (!mounted) return;
    setState(() => _ocrRunning = false);
  }

  Future<void> _dismiss() async {
    final editorState = context.read<afe.EditorState>();
    await safeApply(editorState, (tx) {
      tx.updateNode(widget.node, {MarioImageKeys.ocrDismissed: true});
    });
  }

  /// Insert all OCR'd lines as paragraphs immediately after the image, then
  /// dismiss the panel. Single action — no per-line clicking.
  Future<void> _insertAll() async {
    final editorState = context.read<afe.EditorState>();
    final lines = _ocrLines.where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return;
    // insertNodes inserts the whole list at one path in a single op, so we
    // don't have to walk path.next ourselves — the loop version dropped all
    // but the first because each insertNode above the previous shifted the
    // expected target path.
    await safeApply(editorState, (tx) {
      tx.insertNodes(
        widget.node.path.next,
        [for (final line in lines) _paragraphFrom(line)],
      );
      tx.updateNode(widget.node, {MarioImageKeys.ocrDismissed: true});
    });
  }

  bool _isLocalFile(String src) {
    if (kIsWeb) return false;
    final uri = Uri.tryParse(src);
    if (uri == null) return false;
    if (uri.scheme.isEmpty || uri.scheme == 'file') return File(src).existsSync();
    return false;
  }

  /// A path-shaped string (no scheme, starts with `/` or `~/`, or `file://`)
  /// is meant for the local FS — never fetch via HTTP, even if the file is
  /// missing. NetworkImage on a bare path throws "No host specified in URI",
  /// which clogs the console and breaks image-block layout.
  bool _isLocalPathShape(String src) {
    if (src.startsWith('file://')) return true;
    if (src.startsWith('/') || src.startsWith('~/')) return true;
    final uri = Uri.tryParse(src);
    return uri != null && uri.scheme.isEmpty;
  }

  Widget _buildImage() {
    final local = _localPath;
    if (local != null) return Image.file(File(local), fit: BoxFit.contain);

    if (_downloading) return _statusBox(null, 'Downloading image…');

    final src = _src;
    // A real remote URL (a pasted https image) still renders straight from the
    // network — those never needed syncing in the first place.
    if (src.isNotEmpty && !_isLocalPathShape(src)) {
      return Image.network(src, fit: BoxFit.contain);
    }
    if (src.isEmpty && _driveId == null) return const SizedBox.shrink();

    // Known to Drive but not here yet, and the fetch didn't succeed: almost
    // always offline. Worth distinguishing from a genuinely lost file, because
    // one of them comes back on its own and the other doesn't.
    if (_driveId != null) {
      return _statusBox(
        Icons.cloud_off_outlined,
        "Image isn't downloaded yet",
        onRetry: _retryAsset,
      );
    }
    return _statusBox(Icons.broken_image_outlined, 'Image missing: $src');
  }

  /// Shared frame for the non-image states. A null [icon] means "in progress"
  /// and draws a spinner in its place.
  Widget _statusBox(IconData? icon, String message, {VoidCallback? onRetry}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? MarioColors.onSurfaceMutedDark : MarioColors.onSurfaceMuted;
    final border = isDark ? MarioColors.borderDark : MarioColors.border;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          if (icon == null)
            SizedBox(
              width: 20,
              height: 20,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: CircularProgressIndicator(strokeWidth: 1.5, color: muted),
              ),
            )
          else
            Icon(icon, size: 20, color: muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(fontSize: 12, color: muted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: MarioColors.primaryPressed,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('Retry',
                  style: GoogleFonts.inter(
                      fontSize: 11, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  /// Small corner badge while the picture is still local-only, so it's obvious
  /// the image isn't safe on another device *yet*. Deliberately unobtrusive —
  /// the upload is background work and blocking on it would be worse.
  ///
  /// No spinner: when the user is offline this state persists, and a spinner
  /// that never resolves reads as a hang rather than as "waiting for a
  /// connection".
  Widget _uploadBadge() {
    return Positioned(
      right: 8,
      top: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_upload_outlined,
                size: 11, color: Colors.white),
            const SizedBox(width: 6),
            Text('Not synced yet',
                style: GoogleFonts.inter(fontSize: 10, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? MarioColors.onSurfaceMutedDark : MarioColors.onSurfaceMuted;
    final border = isDark ? MarioColors.borderDark : MarioColors.border;

    final editorState = context.read<afe.EditorState>();

    Widget content = Padding(
      key: _imageKey,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: _buildImage(),
              ),
              if (_awaitingUpload) _uploadBadge(),
            ],
          ),
          if (_ocrRunning)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Reading text from image…',
                    style: GoogleFonts.inter(fontSize: 11, color: muted),
                  ),
                ],
              ),
            )
          else if (!_dismissed && _ocrLines.isNotEmpty)
            Focus(
              autofocus: false,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.tab) {
                  _insertAll();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: MarioColors.primary
                      .withValues(alpha: isDark ? 0.08 : 0.18),
                  border: Border(
                      left: BorderSide(color: MarioColors.primary, width: 3)),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(6),
                    bottomRight: Radius.circular(6),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Detected text (${_ocrLines.length} lines)',
                              style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: muted),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Dismiss',
                            icon: const Icon(Icons.close, size: 14),
                            onPressed: _dismiss,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                maxHeight: 24, maxWidth: 24),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                      child: Text(
                        _ocrLines.join('\n'),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          height: 1.4,
                          color: muted.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                    Container(
                        height: 1,
                        color: border.withValues(alpha: 0.4),
                        margin: const EdgeInsets.symmetric(horizontal: 12)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: _insertAll,
                            icon: const Icon(Icons.keyboard_tab, size: 14),
                            label: Text(
                              'Tab — Insert all',
                              style: GoogleFonts.inter(
                                  fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: MarioColors.primaryPressed,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    // Make the block selectable — the editor's Backspace/Delete handlers
    // remove a node when its block selection is active.
    content = afe.BlockSelectionContainer(
      node: widget.node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [afe.BlockSelectionType.block],
      child: content,
    );

    // Right-click anywhere on the image to get a Word/OneDrive-style
    // context menu (Move up / Move down / Duplicate / Delete).
    return BlockContextMenu(node: widget.node, child: content);
  }

  // SelectableMixin — minimal implementation that mirrors AppFlowy's stock
  // image block. Each method points the editor at our wrapped image bounds so
  // block-level selection, cursor placement, and "delete this node" all work.

  @override
  afe.Position start() => afe.Position(path: widget.node.path, offset: 0);

  @override
  afe.Position end() => afe.Position(path: widget.node.path, offset: 1);

  @override
  afe.Position getPositionInOffset(Offset start) => end();

  @override
  bool get shouldCursorBlink => false;

  @override
  afe.CursorStyle get cursorStyle => afe.CursorStyle.cover;

  @override
  Rect getBlockRect({bool shiftWithBaseOffset = false}) {
    final box = _imageKey.currentContext?.findRenderObject();
    if (box is RenderBox) return Offset.zero & box.size;
    return Rect.zero;
  }

  @override
  Rect? getCursorRectInPosition(
    afe.Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    final box = _renderBox;
    if (box == null) return null;
    return Rect.fromLTWH(-box.size.width / 2, 0, box.size.width, box.size.height);
  }

  @override
  List<Rect> getRectsInSelection(
    afe.Selection selection, {
    bool shiftWithBaseOffset = false,
  }) {
    final box = _renderBox;
    if (box == null) return const [];
    final imageBox = _imageKey.currentContext?.findRenderObject();
    if (imageBox is RenderBox) {
      return [imageBox.localToGlobal(Offset.zero, ancestor: box) & imageBox.size];
    }
    return [Offset.zero & box.size];
  }

  @override
  afe.Selection getSelectionInRange(Offset start, Offset end) =>
      afe.Selection.single(
        path: widget.node.path,
        startOffset: 0,
        endOffset: 1,
      );

  @override
  Offset localToGlobal(
    Offset offset, {
    bool shiftWithBaseOffset = false,
  }) =>
      _renderBox!.localToGlobal(offset);
}

afe.Node _paragraphFrom(String text) => afe.paragraphNode(text: text);
