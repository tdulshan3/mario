/// VoiceService — speech_to_text + record. Implemented in Sprint 7.
abstract class VoiceService {
  Future<bool> initialize();
  Stream<String> startTranscription({String? localeId});
  Future<void> stopTranscription();
  Future<String> startRecording();
  Future<String?> stopRecording();
}
