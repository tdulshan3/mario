/// VoiceServiceImpl — concrete VoiceService backed by speech_to_text + record.
library;

import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/services/voice_service.dart';

class VoiceServiceImpl implements VoiceService {
  VoiceServiceImpl();

  final SpeechToText _speech = SpeechToText();
  final AudioRecorder _recorder = AudioRecorder();
  bool _initAttempted = false;
  bool _ready = false;
  StreamController<TranscriptionEvent>? _activeStream;

  @override
  bool get isAvailable => _ready;

  @override
  Future<bool> initialize() async {
    if (_initAttempted) return _ready;
    _initAttempted = true;
    try {
      _ready = await _speech.initialize(
        onError: (_) {},
        onStatus: (_) {},
      );
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  @override
  Stream<TranscriptionEvent> startTranscription({String? localeId}) {
    final controller = StreamController<TranscriptionEvent>.broadcast(
      onCancel: stopTranscription,
    );
    _activeStream = controller;

    () async {
      if (!_ready) {
        final ok = await initialize();
        if (!ok) {
          controller.addError(StateError(
              'Speech engine unavailable. On Linux install speech-dispatcher.'));
          await controller.close();
          return;
        }
      }
      try {
        await _speech.listen(
          localeId: localeId,
          onResult: (r) {
            if (controller.isClosed) return;
            controller.add(TranscriptionEvent(
              text: r.recognizedWords,
              isFinal: r.finalResult,
            ));
          },
        );
      } catch (e) {
        controller.addError(e);
      }
    }();

    return controller.stream;
  }

  @override
  Future<void> stopTranscription() async {
    try {
      await _speech.stop();
    } catch (_) {}
    final stream = _activeStream;
    _activeStream = null;
    if (stream != null && !stream.isClosed) {
      await stream.close();
    }
  }

  String _generateClipPath(Directory dir) =>
      '${dir.path}/mario-voice-${DateTime.now().millisecondsSinceEpoch}.m4a';

  @override
  Future<String?> startRecording() async {
    final granted = await _recorder.hasPermission();
    if (!granted) return null;
    final dir = await getTemporaryDirectory();
    final path = _generateClipPath(dir);
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 96000),
      path: path,
    );
    return path;
  }

  @override
  Future<String?> stopRecording() async {
    try {
      return await _recorder.stop();
    } catch (_) {
      return null;
    }
  }
}
