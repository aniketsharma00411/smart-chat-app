import 'dart:async';

abstract class CallService {
  Future<void> init();

  Future<void> startCall(String callId);

  Future<void> joinCall(String callId);

  Future<void> endCall();
  
  void toggleMic();

  void dispose();

  // Dubbing controls
  void setDubbingEnabled(bool enabled);
  void setTargetLanguage(String languageCode);
  Future<void> applyDubbingSettings();

  // Streams for UI
  Stream<bool> get isConnected;
  Stream<bool> get isMicOn;
  Stream<bool> get isDubbingEnabled;
  Stream<String> get targetLanguage;
}
