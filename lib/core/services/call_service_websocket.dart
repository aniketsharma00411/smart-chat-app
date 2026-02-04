import 'dart:async';
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

      await _playerModule!.startPlayerFromStream(
        codec: Codec.pcm16,
        numChannels: 1,
        sampleRate: 44100,
        bufferSize: 8192,
        interleaved: true,
      );

      // Listen for incoming audio
      _channel!.stream.listen(
        (data) {
          if (data is List<int>) {
            // Backend sends Int16 at 16kHz
            // Upsample to 44.1kHz
            Uint8List audioData = Uint8List.fromList(data);
            Uint8List upsampled = _resampleInt16Upsample(audioData);
            _playerModule!.feedFromStream(upsampled);
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
        await _recorderModule!.startRecorder(
          toStream: recordingStream.sink,
          codec: Codec.pcm16,
          numChannels: 1,
          sampleRate: 44100,
        );

        // Log actual sample rate
        try {
          int? actualRate = await _recorderModule!.getSampleRate();
          debugPrint("ℹ️ Actual Sample Rate: $actualRate Hz");
        } catch (e) {
          debugPrint("⚠️ Could not get sample rate: $e");
        }

        debugPrint("✅ Recorder Started");

        _recorderSubscription = recordingStream.stream.listen((data) {
          debugPrint("🎤 Mic Data: ${data.length} bytes");
          if (data.isNotEmpty) {
            // debugPrint("DATA FLOWING");
          }

          if (!_isMicMuted && _channel != null) {
            // Downsample 44.1k -> 16k
            try {
              // Log first chunk processing to verify
              // debugPrint("Resampling ${data.length} bytes...");
              final resampled = _resampleInt16Downsample(data);
              _channel!.sink.add(resampled);
            } catch (e) {
              debugPrint("Error processing audio: $e");
            }
          }
        });
      } catch (e) {
        debugPrint("❌ Failed to start Recorder: $e");
        throw e; // Re-throw to trigger cleanup
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

  void toggleMic() {
    _isMicMuted = !_isMicMuted;
    _isMicOnController.add(!_isMicMuted);
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
  // Web Audio is typically 44.1kHz. Backend is 16kHz.
  // We expect PCM16 (Int16) bytes from Flutter Sound.

  // Input: Int16 44.1kHz -> Int16 16kHz (Downsample)
  Uint8List _resampleInt16Downsample(Uint8List inputBytes) {
    // View as Int16
    final intInput = inputBytes.buffer.asInt16List();
    // Target: Keep 1 out of 3 samples (approx 48k -> 16k, or 44.1k -> 14.7k close enough for demo)
    // Ideally we need polyphase, but decimating by 3 is fast.
    final int targetLength = intInput.length ~/ 3;
    final ByteData outputData = ByteData(targetLength * 2);

    for (int i = 0; i < targetLength; i++) {
      int sample = intInput[i * 3];
      outputData.setInt16(i * 2, sample, Endian.little);
    }
    return outputData.buffer.asUint8List();
  }

  // Output: Int16 16kHz -> Int16 44.1kHz (Upsample)
  Uint8List _resampleInt16Upsample(Uint8List inputBytes) {
    final intInput = inputBytes.buffer.asInt16List();
    final int sampleCount = intInput.length;
    final ByteData outputData =
        ByteData(sampleCount * 3 * 2); // 3x samples, 2 bytes each

    for (int i = 0; i < sampleCount; i++) {
      int sample = intInput[i];
      // Zero-Order Hold (repeat sample)
      outputData.setInt16((i * 3) * 2, sample, Endian.little);
      outputData.setInt16((i * 3 + 1) * 2, sample, Endian.little);
      outputData.setInt16((i * 3 + 2) * 2, sample, Endian.little);
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
