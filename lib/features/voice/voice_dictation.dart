/// VoiceDictation — toolbar mic button that streams transcription into the editor.
library;

import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../core/services/voice_service.dart';
import '../../ui/colors.dart';

class VoiceDictationButton extends StatefulWidget {
  const VoiceDictationButton({super.key, required this.editorState});

  final afe.EditorState editorState;

  @override
  State<VoiceDictationButton> createState() => _VoiceDictationButtonState();
}

class _VoiceDictationButtonState extends State<VoiceDictationButton> {
  StreamSubscription<TranscriptionEvent>? _sub;
  bool _active = false;
  String _interim = '';
  int? _startOffset;
  afe.Path? _startPath;

  VoiceService get _service => GetIt.I<VoiceService>();

  Future<void> _start() async {
    final selection = widget.editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Place the cursor in a paragraph first'),
      ));
      return;
    }
    final ok = await _service.initialize();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Speech engine unavailable. On Linux: sudo pacman -S speech-dispatcher'),
      ));
      return;
    }
    setState(() {
      _active = true;
      _interim = '';
      _startOffset = selection.end.offset;
      _startPath = selection.end.path;
    });
    _sub = _service
        .startTranscription()
        .listen(_onEvent, onError: (e) => _stop(error: '$e'), onDone: _stop);
  }

  void _onEvent(TranscriptionEvent e) {
    if (!mounted) return;
    final path = _startPath;
    final startOffset = _startOffset;
    if (path == null || startOffset == null) return;

    final node = widget.editorState.getNodeAtPath(path);
    final delta = node?.delta;
    if (node == null || delta == null) return;

    final tx = widget.editorState.transaction;
    final currentLen = _interim.length;
    if (currentLen > 0) {
      tx.deleteText(node, startOffset, currentLen);
    }
    if (e.text.isNotEmpty) {
      tx.insertText(node, startOffset, e.text);
    }
    tx.afterSelection = afe.Selection.collapsed(
      afe.Position(path: path, offset: startOffset + e.text.length),
    );
    widget.editorState.apply(tx);

    setState(() => _interim = e.text);

    if (e.isFinal) {
      // Bake in the final text — next interim starts after it.
      _startOffset = startOffset + e.text.length;
      _interim = '';
    }
  }

  Future<void> _stop({String? error}) async {
    await _sub?.cancel();
    _sub = null;
    await _service.stopTranscription();
    if (!mounted) return;
    setState(() {
      _active = false;
      _interim = '';
      _startOffset = null;
      _startPath = null;
    });
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _service.stopTranscription();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _active ? 'Stop transcription' : 'Voice dictation',
      onPressed: _active ? () => _stop() : _start,
      icon: Icon(
        _active ? Icons.fiber_manual_record : Icons.mic_none,
        size: 18,
        color: _active ? MarioColors.primaryPressed : null,
      ),
    );
  }
}
