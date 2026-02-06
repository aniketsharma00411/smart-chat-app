import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/api_config.dart';
import 'call_service.dart';

class CallServiceWebSocket implements CallService {
  WebSocketChannel? _channel;

  StreamSubscription? _micSubscription;
  StreamSubscription? _audioSubscription;

  final _isConnectedController = StreamController<bool>.broadcast();
  final _isMicOnController = StreamController<bool>.broadcast();

  bool _isMicMuted = false;

  // Configuration
  late final String _baseUrl = ApiConfig.socketUrl;

  @override
  Stream<bool> get isConnected => _isConnectedController.stream;

  @override
  Stream<bool> get isMicOn => _isMicOnController.stream;

  @override
  Future<void> init() async {
    await _requestPermissions();

    _recorderModule = FlutterSoundRecorder();
    _playerModule = FlutterSoundPlayer();

    await _recorderModule!.openRecorder();
    await _playerModule!.openPlayer();

    debugPrint("✅ Audio Stream Initialized");
  }

  Future<void> _requestPermissions() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      await Permission.microphone.request();
    }
  }

  @override
  Future<void> startCall(String callId) async {
    await joinCall(callId);
  }

  @override
  Future<void> joinCall(String callId) async {
    if (_channel != null) return;

    try {
      final uri = Uri.parse("$_baseUrl/$callId");
      debugPrint("🔌 Connecting to WebSocket: $uri (Base: $_baseUrl)");
      _channel = WebSocketChannel.connect(uri);

      _isConnectedController.add(true);
      _isMicOnController.add(!_isMicMuted);

      // Start Player at 16kHz to match Backend
      // Using recommended buffer size of 1024 for optimal latency
      debugPrint("🔊 Starting Player (16kHz)...");
      await _playerModule!.startPlayerFromStream(
        codec: Codec.pcm16,
        numChannels: 1,
        sampleRate: 16000,
        bufferSize: 4096, // Increased for more stable playback
        interleaved: true,
      );

      // Listen for incoming audio with proper flow control
      int receiveCount = 0;
      _channel!.stream.listen(
        (data) async {
          if (data is List<int>) {
            // Backend sends Int16 at 16kHz
            Uint8List audioData = Uint8List.fromList(data);

            // DEBUG: Calculate Amplitude of RECEIVED Audio
            int maxRxAmp = 0;
            for (int i = 0; i < audioData.length - 1; i += 2) {
              int val = audioData[i] | (audioData[i + 1] << 8);
              if (val > 32767) val -= 65536;
              if (val.abs() > maxRxAmp) maxRxAmp = val.abs();
            }
            if (maxRxAmp > 100) {
              receiveCount++;
              debugPrint("📥 RECV #$receiveCount: ${audioData.length} bytes | Amp: $maxRxAmp");
            }

            // CRITICAL: Use await to prevent buffer accumulation
            // This provides flow control and prevents the 1-minute delay
            try {
              await _playerModule!.feedUint8FromStream(audioData);
            } catch (e) {
              debugPrint("❌ Error feeding audio to player: $e");
            }
          } else {
            // Control Message
            debugPrint("📩 WS Message: $data");
          }
        },
        onError: (e) {
          debugPrint("❌ WebSocket Error: $e");
          _cleanup();
        },
        onDone: () {
          debugPrint("🔌 WebSocket Closed");
          _cleanup();
        },
      );

      debugPrint("🎤 Starting Recorder...");
      try {
        final recordingStream = StreamController<Uint8List>();
        
        // CRITICAL: Try to record at 16kHz, but browser may override this
        // Web browsers typically force 48kHz or 44.1kHz
        const requestedSampleRate = 16000;
        
        await _recorderModule!.startRecorder(
          toStream: recordingStream.sink,
          codec: Codec.pcm16,
          numChannels: 1,
          sampleRate: requestedSampleRate,
          audioSource: AudioSource.defaultSource,
          bufferSize: 4096, // Match player buffer for consistency
        );

        debugPrint("✅ Recorder Started (requested $requestedSampleRate Hz)");
        debugPrint("⚠️ NOTE: On web, browser may override to 48kHz!");

        int chunkCount = 0;
        int sendCount = 0;
        
        // Track timing to calculate actual sample rate
        DateTime? firstChunkTime;
        int totalSamples = 0;
        
        _recorderSubscription = recordingStream.stream.listen((data) {
          if (data.isEmpty) return;

          chunkCount++;
          
          // Calculate actual sample rate from data flow
          if (firstChunkTime == null) {
            firstChunkTime = DateTime.now();
          } else if (chunkCount == 50) {
            // After 50 chunks, calculate actual rate
            final elapsed = DateTime.now().difference(firstChunkTime!).inMilliseconds;
            final actualSampleRate = (totalSamples * 1000) / elapsed;
            debugPrint("📊 ACTUAL Sample Rate: ${actualSampleRate.toStringAsFixed(0)} Hz (expected $requestedSampleRate Hz)");
            if ((actualSampleRate - requestedSampleRate).abs() > 1000) {
              debugPrint("⚠️ WARNING: Browser is providing ${actualSampleRate.toStringAsFixed(0)}Hz but player expects ${requestedSampleRate}Hz!");
              debugPrint("⚠️ This will cause ${(actualSampleRate / requestedSampleRate).toStringAsFixed(1)}x slow motion!");
            }
          }
          totalSamples += data.length ~/ 2; // 2 bytes per Int16 sample

          if (!_isMicMuted && _channel != null) {
            try {
              Uint8List audioData = Uint8List.fromList(data);

              // CRITICAL: Downsample from browser's rate (~31-48kHz) to 16kHz
              // Browser provides high sample rate, but backend/player expect 16kHz
              final downsampled = _downsampleTo16k(audioData);

              // DEBUG: Log amplitude of downsampled data
              int maxAmp = 0;
              for (int i = 0; i < downsampled.length - 1; i += 2) {
                int val = downsampled[i] | (downsampled[i + 1] << 8);
                if (val > 32767) val -= 65536;
                if (val.abs() > maxAmp) maxAmp = val.abs();
              }

              if (maxAmp > 300) {
                sendCount++;
                // Log EVERY send to match receive logging
                debugPrint("📤 SEND #$sendCount: ${downsampled.length} bytes (from ${audioData.length}) | Amp: $maxAmp");
                _channel!.sink.add(downsampled);
              }
            } catch (e) {
              debugPrint("Error processing audio: $e");
            }
          }
        });
      } catch (e) {
        debugPrint("❌ Failed to start Recorder: $e");
        rethrow; // Re-throw to trigger cleanup
      }

      debugPrint("🎤 Audio Loop Started");
    } catch (e) {
      debugPrint("❌ Join Call Failed: $e");
      _cleanup();
    }
  }

  @override
  Future<void> endCall() async {
    _cleanup();
  }

  @override
  void toggleMic() {
    _isMicMuted = !_isMicMuted;
    _isMicOnController.add(!_isMicMuted);
    debugPrint("🎤 Mic ${_isMicMuted ? 'MUTED' : 'UNMUTED'}");
  }

  // DEBUG: Generate 1 second of 440Hz Sine Wave at correct sample rate
  void _playTestTone() async {
    debugPrint("🎵 Generating Test Tone (440Hz)...");
    // FIXED: Use 16kHz to match the player's sample rate
    final int sampleRate = 16000;
    final int durationMs = 1000;
    final int numSamples = (sampleRate * durationMs) ~/ 1000;
    final ByteData buffer = ByteData(numSamples * 2);

    for (int i = 0; i < numSamples; i++) {
      // Sine wave: Amplitude * sin(2 * pi * f * t)
      double t = i / sampleRate;
      double sample = 32767.0 * 0.5 * sin(2 * pi * 440 * t); // 50% volume
      buffer.setInt16(i * 2, sample.toInt(), Endian.little);
    }

    final Uint8List bytes = buffer.buffer.asUint8List();
    debugPrint("🎵 Feeding ${bytes.length} bytes of Tone to Player...");
    try {
      // Use await for proper flow control
      await _playerModule!.feedUint8FromStream(bytes);
    } catch (e) {
      debugPrint("❌ Error playing test tone: $e");
    }
  }

  void _cleanup() {
    _isConnectedController.add(false);
    _channel?.sink.close();
    _channel = null;

    _recorderModule?.closeRecorder();
    _playerModule?.closePlayer();
    _recorderModule = null;
    _playerModule = null;

    _recorderSubscription?.cancel();
    _recorderSubscription = null;

    _micSubscription?.cancel();
    _micSubscription = null;

    _audioSubscription?.cancel();
    _audioSubscription = null;
  }

  // Flutter Sound
  FlutterSoundRecorder? _recorderModule;
  FlutterSoundPlayer? _playerModule;
  StreamSubscription? _recorderSubscription;

  // Data Converters
  // Browser provides high sample rate (31-48kHz), but backend expects 16kHz
  // Downsample by keeping approximately every Nth sample

  Uint8List _downsampleTo16k(Uint8List inputBytes) {
    // View as Int16
    final intInput = inputBytes.buffer.asInt16List();
    
    // Based on detected rate of ~31360 Hz, we need to decimate by ~2
    // For safety, use ratio of 2 (works for 32kHz) or 3 (works for 48kHz)
    const decimationFactor = 2; // Adjust if needed: 2 for 32kHz, 3 for 48kHz
    
    final int targetLength = intInput.length ~/ decimationFactor;
    final ByteData outputData = ByteData(targetLength * 2);

    for (int i = 0; i < targetLength; i++) {
      int sample = intInput[i * decimationFactor];
      outputData.setInt16(i * 2, sample, Endian.little);
    }
    return outputData.buffer.asUint8List();
  }

  @override
  void dispose() {
    _cleanup();
    _isConnectedController.close();
    _isMicOnController.close();
  }
}
