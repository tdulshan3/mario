/// word_shortcuts — MS Word-compatible command shortcuts for the editor.
///
/// Adds: Ctrl+L/E/R/J align, Ctrl+Alt+1/2/3 headings, Ctrl+Shift+L/7 lists,
/// Ctrl+]/[ font-size step, Ctrl+= subscript, Ctrl+Shift+= superscript, and
/// Ctrl+V image-paste from system clipboard.
library;

import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pasteboard/pasteboard.dart';

import 'blocks/mario_image_block.dart';
import 'paste_html_bridge.dart';

/// All Word-style commands. Prepend to the editor's commandShortcutEvents so
/// they win over AppFlowy's built-ins where keys collide (e.g. Ctrl+E was
/// inline-code in AppFlowy; Word uses it for align-center).
// AppFlowy's key parser only recognises the long-form labels in
// `keyToCodeMapping` (e.g. 'digit 1', 'bracket right', 'equal'). Short
// punctuation/digit forms ('1', '[', '=') aren't in the map, and the mapping
// uses non-null assertion — any Ctrl+<key> press would crash if any keybinding
// in the list contains such an unmapped label. So spell them out.
List<afe.CommandShortcutEvent> wordCommandShortcuts() => [
      _alignCommand('left'),
      _alignCenterCommand,
      _alignCommand('right', key: 'mario.align.right', command: 'ctrl+r'),
      _alignCommand('left', key: 'mario.align.justify', command: 'ctrl+j'),
      _headingCommand(1, 'ctrl+alt+digit 1'),
      _headingCommand(2, 'ctrl+alt+digit 2'),
      _headingCommand(3, 'ctrl+alt+digit 3'),
      _normalParagraphCommand,
      _listCommand('bulleted_list', 'mario.list.bullet', 'ctrl+shift+l'),
      _listCommand('numbered_list', 'mario.list.numbered', 'ctrl+shift+digit 7'),
      _listCommand('todo_list', 'mario.list.todo', 'ctrl+shift+digit 9'),
      _fontSizeStepCommand(1, 'mario.font.larger', 'ctrl+bracket right'),
      _fontSizeStepCommand(-1, 'mario.font.smaller', 'ctrl+bracket left'),
      _toggleAttrCommand(
          afe.AppFlowyRichTextKeys.code, 'mario.code', 'ctrl+shift+c'),
      // Word: Ctrl+= subscript, Ctrl+Shift+= superscript. Implemented as
      // unicode replacement of the selected text (AppFlowy's rich text doesn't
      // ship a sub/super attribute, but unicode characters survive any export).
      _unicodeMapCommand(_subscriptMap, 'mario.subscript', 'ctrl+equal'),
      _unicodeMapCommand(
          _superscriptMap, 'mario.superscript', 'ctrl+shift+equal'),
      _smartCopyCommand,
      _smartPasteCommand,
    ];

afe.CommandShortcutEvent _alignCommand(String align,
    {String? key, String? command}) {
  return afe.CommandShortcutEvent(
    key: key ?? 'mario.align.$align',
    command: command ?? 'ctrl+${align == 'left' ? 'l' : align[0]}',
    getDescription: () => 'Align $align',
    handler: (editorState) {
      final selection = editorState.selection;
      if (selection == null) return KeyEventResult.ignored;
      editorState.updateNode(selection, (node) {
        return node.copyWith(attributes: {
          ...node.attributes,
          afe.blockComponentAlign: align,
        });
      });
      return KeyEventResult.handled;
    },
  );
}

final afe.CommandShortcutEvent _alignCenterCommand = afe.CommandShortcutEvent(
  key: 'mario.align.center',
  command: 'ctrl+e',
  getDescription: () => 'Align center',
  handler: (editorState) {
    final selection = editorState.selection;
    if (selection == null) return KeyEventResult.ignored;
    editorState.updateNode(selection, (node) {
      return node.copyWith(attributes: {
        ...node.attributes,
        afe.blockComponentAlign: 'center',
      });
    });
    return KeyEventResult.handled;
  },
);

afe.CommandShortcutEvent _headingCommand(int level, String command) {
  return afe.CommandShortcutEvent(
    key: 'mario.heading.$level',
    command: command,
    getDescription: () => 'Heading $level',
    handler: (editorState) {
      final selection = editorState.selection;
      if (selection == null) return KeyEventResult.ignored;
      editorState.formatNode(selection, (node) {
        return node.copyWith(
          type: afe.HeadingBlockKeys.type,
          attributes: {
            afe.HeadingBlockKeys.level: level,
            afe.HeadingBlockKeys.delta: (node.delta ?? afe.Delta()).toJson(),
          },
        );
      });
      return KeyEventResult.handled;
    },
  );
}

final afe.CommandShortcutEvent _normalParagraphCommand =
    afe.CommandShortcutEvent(
  key: 'mario.heading.normal',
  command: 'ctrl+alt+digit 0',
  getDescription: () => 'Normal text',
  handler: (editorState) {
    final selection = editorState.selection;
    if (selection == null) return KeyEventResult.ignored;
    editorState.formatNode(selection, (node) {
      return node.copyWith(
        type: afe.ParagraphBlockKeys.type,
        attributes: {
          afe.ParagraphBlockKeys.delta: (node.delta ?? afe.Delta()).toJson(),
        },
      );
    });
    return KeyEventResult.handled;
  },
);

afe.CommandShortcutEvent _listCommand(String type, String key, String command) {
  return afe.CommandShortcutEvent(
    key: key,
    command: command,
    getDescription: () => 'Toggle $type',
    handler: (editorState) {
      final selection = editorState.selection;
      if (selection == null) return KeyEventResult.ignored;
      editorState.formatNode(selection, (node) {
        final next = node.type == type ? afe.ParagraphBlockKeys.type : type;
        return node.copyWith(
          type: next,
          attributes: {
            ...node.attributes,
            'delta': (node.delta ?? afe.Delta()).toJson(),
          },
        );
      });
      return KeyEventResult.handled;
    },
  );
}

afe.CommandShortcutEvent _toggleAttrCommand(
    String attr, String key, String command) {
  return afe.CommandShortcutEvent(
    key: key,
    command: command,
    getDescription: () => 'Toggle $attr',
    handler: (editorState) {
      editorState.toggleAttribute(attr);
      return KeyEventResult.handled;
    },
  );
}

afe.CommandShortcutEvent _fontSizeStepCommand(
    int step, String key, String command) {
  return afe.CommandShortcutEvent(
    key: key,
    command: command,
    getDescription: () => step > 0 ? 'Increase font size' : 'Decrease font size',
    handler: (editorState) {
      final selection = editorState.selection;
      if (selection == null || selection.isCollapsed) return KeyEventResult.ignored;
      // Read current size from first node's attributes; default to 14.
      final nodes = editorState.getNodesInSelection(selection);
      double current = 14;
      for (final n in nodes) {
        final delta = n.delta;
        if (delta == null) continue;
        for (final op in delta.whereType<afe.TextInsert>()) {
          final size = op.attributes?[afe.AppFlowyRichTextKeys.fontSize];
          if (size is num) {
            current = size.toDouble();
            break;
          }
        }
      }
      const sizes = [
        8.0, 9.0, 10.0, 11.0, 12.0, 14.0, 16.0, 18.0, 20.0,
        22.0, 24.0, 28.0, 32.0, 36.0, 48.0, 60.0, 72.0,
      ];
      var idx = sizes.indexWhere((s) => s >= current);
      if (idx < 0) idx = sizes.length - 1;
      final next = sizes[(idx + step).clamp(0, sizes.length - 1)];
      editorState.formatDelta(selection, {
        afe.AppFlowyRichTextKeys.fontSize: next,
      });
      return KeyEventResult.handled;
    },
  );
}

const Map<String, String> _superscriptMap = {
  '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
  '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
  '+': '⁺', '-': '⁻', '=': '⁼', '(': '⁽', ')': '⁾',
  'a': 'ᵃ', 'b': 'ᵇ', 'c': 'ᶜ', 'd': 'ᵈ', 'e': 'ᵉ',
  'f': 'ᶠ', 'g': 'ᵍ', 'h': 'ʰ', 'i': 'ⁱ', 'j': 'ʲ',
  'k': 'ᵏ', 'l': 'ˡ', 'm': 'ᵐ', 'n': 'ⁿ', 'o': 'ᵒ',
  'p': 'ᵖ', 'r': 'ʳ', 's': 'ˢ', 't': 'ᵗ', 'u': 'ᵘ',
  'v': 'ᵛ', 'w': 'ʷ', 'x': 'ˣ', 'y': 'ʸ', 'z': 'ᶻ',
};

const Map<String, String> _subscriptMap = {
  '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄',
  '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
  '+': '₊', '-': '₋', '=': '₌', '(': '₍', ')': '₎',
  'a': 'ₐ', 'e': 'ₑ', 'h': 'ₕ', 'i': 'ᵢ', 'j': 'ⱼ',
  'k': 'ₖ', 'l': 'ₗ', 'm': 'ₘ', 'n': 'ₙ', 'o': 'ₒ',
  'p': 'ₚ', 'r': 'ᵣ', 's': 'ₛ', 't': 'ₜ', 'u': 'ᵤ',
  'v': 'ᵥ', 'x': 'ₓ',
};

/// Replace every char in the selected range with its mapped variant. Acts
/// like Word's Ctrl+= / Ctrl+Shift+= but uses unicode (sub/super) so the
/// styling survives copy/paste and export.
afe.CommandShortcutEvent _unicodeMapCommand(
    Map<String, String> map, String key, String command) {
  return afe.CommandShortcutEvent(
    key: key,
    command: command,
    getDescription: () => 'Map to ${key.endsWith('subscript') ? 'subscript' : 'superscript'}',
    handler: (editorState) {
      final selection = editorState.selection;
      if (selection == null || selection.isCollapsed) return KeyEventResult.ignored;
      final normalized = selection.normalized;
      if (normalized.start.path.equals(normalized.end.path)) {
        final node = editorState.getNodeAtPath(normalized.start.path);
        final delta = node?.delta;
        if (node == null || delta == null) return KeyEventResult.ignored;
        final plain = delta.toPlainText();
        final start = normalized.start.offset;
        final end = normalized.end.offset;
        final original = plain.substring(start, end);
        final replaced = original.split('').map((c) => map[c] ?? c).join();
        if (replaced == original) return KeyEventResult.ignored;
        final tx = editorState.transaction
          ..deleteText(node, start, end - start)
          ..insertText(node, start, replaced);
        editorState.apply(tx);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
  );
}

/// Patterns that strongly suggest a string is markdown source:
/// ATX headings, list bullets, ordered lists, fences, blockquotes, hr,
/// inline bold/italic/code/link. Multiline so anchors match per-line.
final RegExp _markdownPattern = RegExp(
  r'(^#{1,6}\s|^\s*[-*+]\s|^\s*\d+\.\s|^\s*>\s|^\s*```|^---+\s*$|\*\*[^*\n]+\*\*|__[^_\n]+__|`[^`\n]+`|\[[^\]\n]+\]\([^)\n]+\))',
  multiLine: true,
);

bool _looksLikeMarkdown(String text) => _markdownPattern.hasMatch(text);

/// Strong HTML signal — DOCTYPE, `<html>`, or any common block tag at the
/// start of (a leading-whitespace-stripped) line. Ordered before markdown
/// detection because patterns like `*, *::before { ... }` in CSS would
/// otherwise look like a markdown bullet.
final RegExp _htmlPattern = RegExp(
  r'(<!doctype\s|<html[\s>]|<head[\s>]|<body[\s>]|<style[\s>]|<script[\s>]|<div[\s>]|<section[\s>]|<header[\s>]|<article[\s>]|<table[\s>]|<svg[\s>])',
  caseSensitive: false,
);

bool _looksLikeHtml(String text) {
  final t = text.trimLeft();
  if (t.startsWith('<!') || t.startsWith('<html') || t.startsWith('<!DOCTYPE')) {
    return true;
  }
  return _htmlPattern.hasMatch(t);
}

/// True when the text is a complete HTML document — DOCTYPE or `<html>` root
/// tag — as opposed to a fragment like `<p>foo</p>`. Full documents go to
/// the preview override (so the entire styled page renders verbatim);
/// fragments fall through to AppFlowy's structural HTML parser.
bool _isFullHtmlDocument(String text) {
  final t = text.trimLeft().toLowerCase();
  return t.startsWith('<!doctype') ||
      t.startsWith('<html') ||
      (t.contains('<html') && t.contains('<body'));
}

/// Ctrl+V — combined image + markdown + default paste. Always returns
/// handled so AppFlowy's default paste doesn't fire in parallel; we replay
/// it ourselves in the fallback branch when the clipboard isn't markdown or
/// image content. Pasting from a `.md` file gives plain markdown text +
/// (often) HTML; AppFlowy's default prefers HTML, which strips the markdown
/// structure. We bias to markdown when the text looks like markdown source.
final afe.CommandShortcutEvent _smartPasteCommand = afe.CommandShortcutEvent(
  key: 'mario.paste.smart',
  command: 'ctrl+v',
  getDescription: () => 'Smart paste (image / markdown / rich)',
  handler: (editorState) {
    () async {
      try {
        // 0. In-app rich copy (e.g. a table) that is still the current
        // clipboard content → replay the exact nodes so the structure
        // survives. AppFlowy's clipboard only carries plain text, which would
        // otherwise flatten a copied table into lines.
        final inAppNodes = _InAppClipboard.nodes;
        if (inAppNodes != null) {
          final clip = await Pasteboard.text;
          if (clip != null && clip == _InAppClipboard.text) {
            if (editorState.isDisposed) return;
            await _pasteInAppNodes(editorState, inAppNodes);
            return;
          }
        }
        if (!kIsWeb) {
          // 1. Raw image bytes (screenshot, "Copy image" from a browser).
          final bytes = await Pasteboard.image;
          if (bytes != null && bytes.isNotEmpty) {
            if (editorState.isDisposed) return;
            await _insertClipboardImage(editorState, bytes);
            return;
          }
          // 2. File copy from a file manager — the clipboard carries paths,
          // not bytes. Insert each image file as a Mario image block; if any
          // images consumed, skip the markdown/text path so we don't paste
          // the path string as text.
          final files = await Pasteboard.files();
          final imagePaths = files.where(_isImagePath).toList();
          if (imagePaths.isNotEmpty) {
            if (editorState.isDisposed) return;
            await _insertImagePaths(editorState, imagePaths);
            return;
          }
        }
        final text = await Pasteboard.text;
        if (text != null && text.isNotEmpty) {
          // 3. A bare image-file path on the clipboard (some apps paste paths
          // as text). Recognise it and insert the image instead of the path.
          if (!kIsWeb) {
            final trimmed = text.trim();
            final candidate = _pathFromTextClipboard(trimmed);
            if (candidate != null && _isImagePath(candidate)) {
              if (editorState.isDisposed) return;
              await _insertImagePaths(editorState, [candidate]);
              return;
            }
          }
          // Detect HTML first — CSS like `*, *::before` falsely matches the
          // markdown bullet regex, so HTML source pasted from a code editor
          // would otherwise be parsed as markdown and turn into garbage.
          if (_looksLikeHtml(text)) {
            if (editorState.isDisposed) return;
            // Full styled documents:
            //   - Set the override so the preview pane renders it verbatim
            //     (sticky/grid/JS/animations survive — htmlToDocument would
            //     flatten it to text+headings).
            //   - ALSO mirror the raw source as paragraphs in the editor so
            //     hiding the preview shows the tags-as-text, and the content
            //     persists in the doc (in addition to the override).
            if (_isFullHtmlDocument(text)) {
              rawHtmlOverride.value = text;
              await _insertHtmlSource(editorState, text);
              return;
            }
            await _insertHtml(editorState, text);
            return;
          }
          if (_looksLikeMarkdown(text)) {
            if (editorState.isDisposed) return;
            await _insertMarkdown(editorState, text);
            return;
          }
        }
      } catch (_) {
        // fall through to default paste
      }
      if (editorState.isDisposed) return;
      // Replay AppFlowy's default rich-clipboard paste (HTML or plain text).
      afe.handlePaste(editorState);
    }();
    return KeyEventResult.handled;
  },
);

/// In-app rich-copy buffer. AppFlowy 3.3.0's clipboard only carries plain text
/// (its copy command computes HTML but [AppFlowyClipboard.setData] drops it),
/// so a copied table pastes back as flat lines. We stash the copied nodes as
/// JSON and replay them on paste when the system clipboard still holds the same
/// text we copied — preserving tables (and other rich blocks) within the app.
class _InAppClipboard {
  _InAppClipboard._();
  static String? text;
  static List<Map<String, Object>>? nodes;

  static void set(String t, List<afe.Node> ns) {
    text = t;
    nodes = ns.map((n) => n.toJson()).toList(growable: false);
  }
}

/// Ctrl+C — when the caret/selection is inside a table, copy the whole table
/// as a reusable block (and mirror its text to the system clipboard). For
/// everything else we return [KeyEventResult.ignored] so AppFlowy's default
/// copy keeps handling plain text and partial selections correctly.
final afe.CommandShortcutEvent _smartCopyCommand = afe.CommandShortcutEvent(
  key: 'mario.copy.block',
  command: 'ctrl+c',
  macOSCommand: 'cmd+c',
  getDescription: () => 'Copy a table or image as a reusable block',
  handler: (editorState) {
    final selection = editorState.selection?.normalized;
    if (selection == null) return KeyEventResult.ignored;
    final block = _copyableBlock(editorState, selection);
    if (block == null) return KeyEventResult.ignored;
    // For everything else we return ignored so AppFlowy's default copy keeps
    // handling plain text and partial selections correctly.
    final text = block.type == 'table'
        ? _tablePlainText(block)
        : (block.attributes['url'] as String?) ?? '[image]';
    _InAppClipboard.set(text, [block]);
    // Write via the SAME plugin the paste path reads (Pasteboard), so the
    // round-trip is byte-identical and the in-app match guard fires. Flutter's
    // Clipboard.setData and Pasteboard.text don't reliably agree on Linux,
    // which made the guard never match and the copy silently fall back to
    // AppFlowy's plain-text paste.
    Pasteboard.writeText(text);
    return KeyEventResult.handled;
  },
);

/// Walk up from the selection start to find an enclosing copyable rich block —
/// a table or an image — whose structure AppFlowy's plain-text-only clipboard
/// would otherwise lose on copy/paste.
afe.Node? _copyableBlock(afe.EditorState editorState, afe.Selection selection) {
  afe.Node? n = editorState.getNodeAtPath(selection.start.path);
  while (n != null) {
    if (n.type == 'table' || n.type == 'image') return n;
    n = n.parent;
  }
  return null;
}

/// Tab/newline rendering of a table's cells for the system clipboard (so an
/// external paste gets readable text, and so we can detect our own copy later).
String _tablePlainText(afe.Node table) {
  final cols = (table.attributes['colsLen'] as int?) ?? 0;
  final rows = (table.attributes['rowsLen'] as int?) ?? 0;
  if (cols <= 0 || rows <= 0) {
    return table.children.map((c) => c.delta?.toPlainText() ?? '').join('\n');
  }
  final grid = List.generate(rows, (_) => List<String>.filled(cols, ''));
  for (final cell in table.children) {
    final r = cell.attributes['rowPosition'] as int?;
    final c = cell.attributes['colPosition'] as int?;
    if (r == null || c == null || r < 0 || c < 0 || r >= rows || c >= cols) {
      continue;
    }
    grid[r][c] =
        cell.children.map((n) => n.delta?.toPlainText() ?? '').join(' ').trim();
  }
  return grid.map((row) => row.join('\t')).join('\n');
}

/// Insert previously-copied in-app nodes (rebuilt from JSON so they're fresh
/// clones) below the caret — replacing an empty current paragraph if present.
Future<void> _pasteInAppNodes(
    afe.EditorState editorState, List<Map<String, Object>> nodesJson) async {
  if (nodesJson.isEmpty) return;
  final children = nodesJson.map(afe.Node.fromJson).toList();
  final selection = editorState.selection;
  var path = selection?.end.path.next ??
      editorState.document.root.children.last.path.next;
  if (selection != null) {
    final node = editorState.document.nodeAtPath(selection.end.path);
    final delta = node?.delta;
    if (delta != null && delta.toPlainText().isEmpty) {
      path = selection.end.path;
    }
  }
  final tx = editorState.transaction..insertNodes(path, children);
  await editorState.apply(tx);
}

const _imageExtensions = <String>{
  '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.svg', '.heic', '.heif',
};

bool _isImagePath(String path) {
  final lower = path.toLowerCase();
  return _imageExtensions.any(lower.endsWith);
}

/// Accept either a plain path or a `file://` URI; reject anything else.
String? _pathFromTextClipboard(String text) {
  if (text.isEmpty) return null;
  if (text.contains('\n')) return null;
  if (text.startsWith('file://')) {
    final uri = Uri.tryParse(text);
    return uri?.toFilePath();
  }
  if (text.startsWith('/') || text.startsWith('~/')) {
    return text.startsWith('~/')
        ? '${Platform.environment['HOME']}${text.substring(1)}'
        : text;
  }
  return null;
}

/// Lazily-created persistent image directory under the app documents dir.
/// Files written here survive reboots and OS /tmp sweeps, so an image url
/// stored in a Drive doc keeps working between sessions.
Future<Directory> _persistentImageDir() async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/mario_images');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// Copy a user-supplied image file into the persistent image dir under a
/// unique filename, returning the new absolute path. Originals can be moved
/// or deleted by the user without breaking the embedded reference.
///
/// Exposed for drag-drop in editor_screen.dart; clipboard/file pastes call
/// it through [_insertImagePaths].
Future<String> persistImageFile(String sourcePath) async {
  final dir = await _persistentImageDir();
  final ext = () {
    final dot = sourcePath.lastIndexOf('.');
    return dot >= 0 ? sourcePath.substring(dot) : '.png';
  }();
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final dest = File('${dir.path}/mario_image_$stamp$ext');
  await File(sourcePath).copy(dest.path);
  return dest.path;
}

Future<void> _insertImagePaths(
    afe.EditorState editorState, List<String> paths) async {
  if (editorState.isDisposed) return;
  // Copy each source into the persistent dir so the doc reference survives
  // moves/deletes/reboots of the original file.
  final stored = <String>[];
  for (final p in paths) {
    try {
      stored.add(await persistImageFile(p));
    } catch (_) {
      // Copy failed (permissions, missing) — fall back to the raw path so
      // the user still sees something in this session.
      stored.add(p);
    }
  }
  if (editorState.isDisposed) return;
  final selection = editorState.selection;
  final basePath = selection?.end.path ??
      editorState.document.root.children.last.path;
  final tx = editorState.transaction
    ..insertNodes(
      basePath.next,
      [
        for (final p in stored)
          afe.Node(
            type: MarioImageKeys.type,
            attributes: {MarioImageKeys.url: p},
          ),
      ],
    );
  await editorState.apply(tx);
}

Future<void> _insertClipboardImage(
    afe.EditorState editorState, Uint8List bytes) async {
  final dir = await _persistentImageDir();
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final file = File('${dir.path}/mario_paste_$stamp.png');
  await file.writeAsBytes(bytes);
  if (editorState.isDisposed) return;
  final selection = editorState.selection;
  final path = selection?.end.path ??
      editorState.document.root.children.last.path;
  final tx = editorState.transaction
    ..insertNode(
      path.next,
      afe.Node(
        type: MarioImageKeys.type,
        attributes: {MarioImageKeys.url: file.path},
      ),
    );
  await editorState.apply(tx);
}

Future<void> _insertHtml(
    afe.EditorState editorState, String html) async {
  // AppFlowy's HTML parser handles a subset (paragraph/heading/list/quote/
  // image/table). Whatever can't be modelled is dropped — the original raw
  // HTML still exists on the system clipboard if the user wants to keep it.
  final doc = afe.htmlToDocument(html);
  final children = doc.root.children.toList();
  if (children.isEmpty) return;
  final selection = editorState.selection;
  var path = selection?.end.path.next ??
      editorState.document.root.children.last.path.next;
  if (selection != null) {
    final node = editorState.document.nodeAtPath(selection.end.path);
    final delta = node?.delta;
    if (delta != null && delta.toPlainText().isEmpty) {
      path = selection.end.path;
    }
  }
  final tx = editorState.transaction..insertNodes(path, children);
  var afterPath = path;
  for (var i = 0; i < children.length - 1; i++) {
    afterPath = afterPath.next;
  }
  final offset = children.last.delta?.length ?? 0;
  tx.afterSelection = afe.Selection.collapsed(
    afe.Position(path: afterPath, offset: offset),
  );
  await editorState.apply(tx);
}

/// Insert raw HTML source as plain paragraphs (one per source line) below
/// the caret. Used for full-document pastes so the user sees the HTML *with
/// tags* in the editor (when preview is off) — the rendered version lives in
/// the preview pane via [rawHtmlOverride].
///
/// Empty lines collapse to a single space so AppFlowy doesn't insert its
/// placeholder text on what should be a visible blank line.
Future<void> _insertHtmlSource(
    afe.EditorState editorState, String html) async {
  if (editorState.isDisposed) return;
  final lines = html.split('\n');
  if (lines.isEmpty) return;
  final selection = editorState.selection;
  var path = selection?.end.path.next ??
      editorState.document.root.children.last.path.next;
  if (selection != null) {
    final node = editorState.document.nodeAtPath(selection.end.path);
    final delta = node?.delta;
    if (delta != null && delta.toPlainText().isEmpty) {
      path = selection.end.path;
    }
  }
  final nodes = [
    for (final line in lines) afe.paragraphNode(text: line.isEmpty ? ' ' : line),
  ];
  final tx = editorState.transaction..insertNodes(path, nodes);
  var afterPath = path;
  for (var i = 0; i < nodes.length - 1; i++) {
    afterPath = afterPath.next;
  }
  final offset = nodes.last.delta?.length ?? 0;
  tx.afterSelection = afe.Selection.collapsed(
    afe.Position(path: afterPath, offset: offset),
  );
  await editorState.apply(tx);
}

Future<void> _insertMarkdown(
    afe.EditorState editorState, String markdown) async {
  final doc = afe.markdownToDocument(markdown);
  final children = doc.root.children;
  if (children.isEmpty) return;
  final selection = editorState.selection;
  // Mirror AppFlowy's _pasteMarkdown logic: replace empty current paragraph
  // in-place; otherwise insert after it.
  var path = selection?.end.path.next ??
      editorState.document.root.children.last.path.next;
  if (selection != null) {
    final node = editorState.document.nodeAtPath(selection.end.path);
    final delta = node?.delta;
    if (delta != null && delta.toPlainText().isEmpty) {
      path = selection.end.path;
    }
  }
  final tx = editorState.transaction..insertNodes(path, children);
  // Caret at end of last inserted node.
  var afterPath = path;
  for (var i = 0; i < children.length - 1; i++) {
    afterPath = afterPath.next;
  }
  final offset = children.last.delta?.length ?? 0;
  tx.afterSelection = afe.Selection.collapsed(
    afe.Position(path: afterPath, offset: offset),
  );
  await editorState.apply(tx);
}
