/// VoiceService — abstract speech-to-text + audio capture interface.
library;

class TranscriptionEvent {
  final String text;
  final bool isFinal;
  const TranscriptionEvent({required this.text, required this.isFinal});
}

abstract class VoiceService {
  /// Whether the platform reports a usable speech engine. On Linux this means
  /// speech_dispatcher is reachable; on web it means the Web Speech API exists.
  bool get isAvailable;

  /// Returns true when the engine successfully initialised. Subsequent calls
  /// are no-ops once initialised.
  Future<bool> initialize();

  /// Begin a streaming transcription session. The returned stream emits both
  /// interim and final partials; close it via [stopTranscription].
  Stream<TranscriptionEvent> startTranscription({String? localeId});

  /// Stop the current transcription session. Safe to call when not active.
  Future<void> stopTranscription();

  /// Begin recording audio to disk. Returns the file path that will receive
  /// the recording, or null when the platform refuses permission.
  Future<String?> startRecording();

  /// Stop the active recording. Returns the final file path or null.
  Future<String?> stopRecording();
}
