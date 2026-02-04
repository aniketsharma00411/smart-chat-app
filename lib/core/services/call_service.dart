import 'dart:async';

abstract class CallService {
  Future<void> init();

  Future<void> startCall(String callId);

  Future<void> joinCall(String callId);

  Future<void> endCall();

  void dispose();

  // Streams for UI
  Stream<bool> get isConnected;
  Stream<bool> get isMicOn;
}
