/// AudioBlock — record/playback embed with auto-transcription below the player.
library;

import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../../../core/services/voice_service.dart';
import '../../../ui/colors.dart';
import '_safe_transaction.dart';
import 'block_context_menu.dart';

class AudioBlockKeys {
  const AudioBlockKeys._();
  static const String type = 'audio_clip';
  static const String path = 'path';
  static const String transcript = 'transcript';
  static const String durationMs = 'durationMs';
}

afe.Node audioNode({
  String path = '',
  String transcript = '',
  int durationMs = 0,
}) =>
    afe.Node(
      type: AudioBlockKeys.type,
      attributes: {
        AudioBlockKeys.path: path,
        AudioBlockKeys.transcript: transcript,
        AudioBlockKeys.durationMs: durationMs,
      },
    );

class AudioBlockComponentBuilder extends afe.BlockComponentBuilder {
  AudioBlockComponentBuilder({super.configuration});

  @override
  afe.BlockComponentWidget build(afe.BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return AudioBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
    );
  }

  @override
  bool validate(afe.Node node) =>
      node.attributes.containsKey(AudioBlockKeys.path);
}

class AudioBlockComponentWidget extends afe.BlockComponentStatefulWidget {
  const AudioBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.configuration = const afe.BlockComponentConfiguration(),
  });

  @override
  State<AudioBlockComponentWidget> createState() =>
      _AudioBlockComponentWidgetState();
}

class _AudioBlockComponentWidgetState extends State<AudioBlockComponentWidget> {
  AudioPlayer? _player;
  StreamSubscription<TranscriptionEvent>? _transcriptionSub;
  bool _recording = false;
  String _transcriptBuffer = '';

  String get _path =>
      (widget.node.attributes[AudioBlockKeys.path] as String?) ?? '';
  String get _transcript =>
      (widget.node.attributes[AudioBlockKeys.transcript] as String?) ?? '';

  VoiceService get _service => GetIt.I<VoiceService>();

  @override
  void dispose() {
    _player?.dispose();
    _transcriptionSub?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final ok = await _service.initialize();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Speech engine unavailable. Recording without transcript.'),
      ));
    }
    final path = await _service.startRecording();
    if (!mounted) return;
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Microphone permission denied'),
      ));
      return;
    }
    setState(() {
      _recording = true;
      _transcriptBuffer = '';
    });
    if (ok) {
      _transcriptionSub = _service.startTranscription().listen(
        (e) {
          if (!mounted) return;
          setState(() => _transcriptBuffer = e.text);
        },
        onError: (_) {},
      );
    }
  }

  Future<void> _stop() async {
    await _transcriptionSub?.cancel();
    _transcriptionSub = null;
    await _service.stopTranscription();
    final path = await _service.stopRecording();
    if (!mounted) return;
    setState(() => _recording = false);
    if (path == null) return;

    final editorState = context.read<afe.EditorState>();
    await safeApply(editorState, (tx) {
      tx.updateNode(widget.node, {
        AudioBlockKeys.path: path,
        AudioBlockKeys.transcript: _transcriptBuffer,
        AudioBlockKeys.durationMs: 0,
      });
    });
  }

  Future<void> _ensurePlayer() async {
    if (_player != null || _path.isEmpty) return;
    final p = AudioPlayer();
    try {
      await p.setFilePath(_path);
    } catch (_) {}
    if (!mounted) {
      p.dispose();
      return;
    }
    setState(() => _player = p);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? MarioColors.borderDark : MarioColors.border;
    final muted =
        isDark ? MarioColors.onSurfaceMutedDark : MarioColors.onSurfaceMuted;
    final bg = isDark
        ? MarioColors.surfaceVariantDark
        : MarioColors.surfaceVariant;

    Widget content;
    if (_path.isEmpty) {
      // New block: prompt user to record.
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: _recording
                      ? Theme.of(context).colorScheme.error
                      : MarioColors.primary,
                  foregroundColor: const Color(0xFF1A1A1A),
                ),
                onPressed: _recording ? _stop : _start,
                icon: Icon(
                  _recording ? Icons.stop : Icons.mic,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _recording
                      ? (_transcriptBuffer.isEmpty
                          ? 'Recording…'
                          : _transcriptBuffer)
                      : 'Tap to record a voice note',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: _recording && _transcriptBuffer.isEmpty
                        ? muted
                        : null,
                    fontStyle: _recording ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      _ensurePlayer();
      final player = _player;
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Row(
              children: [
                IconButton(
                  onPressed: player == null
                      ? null
                      : () {
                          if (player.playing) {
                            player.pause();
                          } else {
                            player.play();
                          }
                          setState(() {});
                        },
                  icon: Icon(
                    player?.playing == true ? Icons.pause : Icons.play_arrow,
                  ),
                ),
                Expanded(
                  child: StreamBuilder<Duration>(
                    stream: player?.positionStream ?? const Stream.empty(),
                    builder: (context, snap) {
                      final pos = snap.data ?? Duration.zero;
                      final dur = player?.duration ?? Duration.zero;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(
                            value: dur.inMilliseconds == 0
                                ? null
                                : pos.inMilliseconds /
                                    dur.inMilliseconds,
                            color: MarioColors.primary,
                            backgroundColor: border,
                            minHeight: 4,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_format(pos)} / ${_format(dur)}',
                            style:
                                GoogleFonts.inter(fontSize: 11, color: muted),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
              if (_transcript.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _transcript,
                  style: GoogleFonts.inter(fontSize: 12, color: muted),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return BlockContextMenu(node: widget.node, child: content);
  }

  String _format(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

afe.SelectionMenuItem audioSelectionMenuItem = afe.SelectionMenuItem.node(
  getName: () => 'Voice clip',
  iconData: Icons.mic_none,
  keywords: const ['voice', 'audio', 'record', 'mic'],
  nodeBuilder: (editorState, _) => audioNode(),
  replace: (editorState, node) =>
      node.delta?.toPlainText().isEmpty ?? false,
);
