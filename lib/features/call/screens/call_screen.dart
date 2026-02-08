import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html show window;

import '../../../core/providers/providers.dart';
import '../widgets/call_settings_sheet.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String callId;

  const CallScreen({super.key, required this.callId});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen>
    with SingleTickerProviderStateMixin {
  bool _isMicOff = false;
  bool _isDubbingEnabled = false;
  String _targetLanguage = 'en'; // Default to English, will be updated from user preferences
  String _connectionStatus = "Connecting to Server...";
  late AnimationController _pulseController;
  bool _hasEndedCall = false; // Track if we've already ended the call

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      lowerBound: 1.0,
      upperBound: 1.1,
    )..repeat(reverse: true);

    _initCall();
  }

  Future<void> _initCall() async {
    final callService = ref.read(callServiceProvider);

    await callService.init();

    // Load user's preferred language from settings
    final user = ref.read(currentUserProvider).value;
    if (user != null) {
      final firestoreService = ref.read(firestoreServiceProvider);
      final userDoc = await firestoreService.getUser(user.uid);
      if (userDoc != null && userDoc.containsKey('preferredLanguage')) {
        final preferredLanguage = userDoc['preferredLanguage'] as String;
        // Set the default target language to user's preference
        _targetLanguage = preferredLanguage;
        callService.setTargetLanguage(preferredLanguage);
      }
    }

    // Listen to connection state
    callService.isConnected.listen((connected) {
      if (mounted) {
        setState(() {
          _connectionStatus = connected
              ? (_isDubbingEnabled
                  ? "Connected • Translation Active"
                  : "Connected")
              : "Disconnected";
        });
      }
    });

    // Listen to mic state
    callService.isMicOn.listen((isMicOn) {
      if (mounted) {
        setState(() {
          _isMicOff = !isMicOn;
        });
      }
    });

    // Listen to dubbing state
    callService.isDubbingEnabled.listen((enabled) {
      if (mounted) {
        setState(() {
          _isDubbingEnabled = enabled;
          // Update connection status when dubbing state changes
          final callServiceState = ref.read(callServiceProvider);
          callServiceState.isConnected.listen((connected) {
            if (mounted && connected) {
              setState(() {
                _connectionStatus = _isDubbingEnabled
                    ? "Connected • Translation Active"
                    : "Connected";
              });
            }
          });
        });
      }
    });

    // Listen to target language
    callService.targetLanguage.listen((language) {
      if (mounted) {
        setState(() {
          _targetLanguage = language;
        });
      }
    });

    try {
      await callService.joinCall(widget.callId);
    } catch (e) {
      if (mounted) setState(() => _connectionStatus = "Connection Failed");
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    // Don't call endCall here - it's async and should be called explicitly
    // when the disconnect button is pressed. The cleanup will happen there.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen to call stream for side effects (Navigation)
    ref.listen(currentCallStreamProvider(widget.callId), (previous, next) {
      final callData = next.value;
      if (callData == null) return;

      // Handle Navigation (Call Ended/Rejected)
      if (callData['status'] == 'ended' || callData['status'] == 'rejected') {
        if (context.mounted &&
            GoRouterState.of(context).uri.toString().startsWith('/call')) {
          // On web, do a full page reload to release microphone
          // On other platforms, just pop
          if (kIsWeb) {
            debugPrint("🔄 Call ended - reloading page to release microphone...");
            html.window.location.href = '/chats';
          } else {
            context.pop();
          }
        }
      }
    });

    return StreamBuilder<Map<String, dynamic>?>(
      stream: ref.watch(firestoreServiceProvider).streamCall(widget.callId),
      builder: (context, snapshot) {
        final callData = snapshot.data;
        final user = ref.watch(currentUserProvider).value;
        final callMap = callData ?? {};
        final otherUserId = callMap['callerId'] == user?.uid
            ? callMap['receiverId']
            : callMap['callerId'];

        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF4338CA), Color(0xFF1E1B4B)],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 60),
                  const Text(
                    "Audio Call",
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 10),
                  // Connection status pulse/label
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _connectionStatus.contains("Connected")
                              ? Colors.greenAccent
                              : Colors
                                  .amber, // Green for connected, Amber for connecting
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _connectionStatus,
                        style: TextStyle(
                            color: Colors.indigo.shade100, fontSize: 12),
                      ),
                    ],
                  ),
                  // Language Badge (when dubbing is enabled)
                  if (_isDubbingEnabled) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.translate,
                            size: 14,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _getLanguageName(_targetLanguage),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    "ID: ${widget.callId}", // Debug ID
                    style: const TextStyle(color: Colors.white30, fontSize: 8),
                  ),
                  const SizedBox(height: 40),

                  // User Info
                  if (otherUserId != null)
                    FutureBuilder<Map<String, dynamic>?>(
                      future: ref
                          .read(firestoreServiceProvider)
                          .getUser(otherUserId),
                      builder: (context, userSnapshot) {
                        final otherUser = userSnapshot.data;
                        final displayName = otherUser?['displayName'] ?? "User";
                        final photoURL = otherUser?['photoURL'];

                        return Column(
                          children: [
                            ScaleTransition(
                              scale: _pulseController,
                              child: Container(
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.blueAccent
                                              .withOpacity(0.3),
                                          blurRadius: 20,
                                          spreadRadius: 5)
                                    ]),
                                child: CircleAvatar(
                                  radius: 60,
                                  backgroundImage: photoURL != null
                                      ? NetworkImage(photoURL)
                                      : const NetworkImage(
                                          'https://i.pravatar.cc/150'),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              displayName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        );
                      },
                    ),
                  const Spacer(),

                  // Waveform / AI Visualizer PlaceHolder
                  Container(
                    height: 60,
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    child: CustomPaint(
                      painter: AudioWaveformPainter(), // Simple dummy painter
                    ),
                  ),

                  const Spacer(),

                  // Controls
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(30)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ControlButton(
                          icon: _isMicOff ? Icons.mic_off : Icons.mic,
                          isActive: !_isMicOff,
                          onTap: () {
                            ref.read(callServiceProvider).toggleMic();
                          },
                        ),
                        _ControlButton(
                          icon: Icons.auto_awesome,
                          isActive: _isDubbingEnabled,
                          onTap: _showCallSettings,
                          label: 'AI Translation',
                        ),
                        _ControlButton(
                          icon: Icons.call_end,
                          color: Colors.red,
                          onTap: () async {
                            if (_hasEndedCall) return; // Prevent double-tap
                            _hasEndedCall = true;
                            
                            try {
                              // End the call service first (cleanup audio/websocket)
                              debugPrint("🔴 Ending call...");
                              await ref.read(callServiceProvider).endCall();
                              debugPrint("✅ Call service ended");
                              
                              // Update Firestore status
                              await ref
                                  .read(firestoreServiceProvider)
                                  .endCall(widget.callId);
                              debugPrint("✅ Firestore updated");
                              
                              // Force page reload on web to release microphone
                              // (workaround for flutter_sound web bug)
                              if (kIsWeb) {
                                debugPrint("🔄 Forcing page reload to release microphone...");
                                html.window.location.href = '/chats';
                              }
                            } catch (e) {
                              debugPrint("❌ Error ending call: $e");
                              _hasEndedCall = false; // Reset on error
                              // Try to navigate back manually if there's an error
                              if (mounted && context.mounted) {
                                try {
                                  if (kIsWeb) {
                                    html.window.location.href = '/chats';
                                  } else {
                                    context.pop();
                                  }
                                } catch (popError) {
                                  debugPrint("⚠️ Could not navigate: $popError");
                                }
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showCallSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CallSettingsSheet(
        isDubbingEnabled: _isDubbingEnabled,
        targetLanguage: _targetLanguage,
        onApply: (enabled, language) async {
          final callService = ref.read(callServiceProvider);
          
          // Update settings
          callService.setDubbingEnabled(enabled);
          callService.setTargetLanguage(language);
          
          // Apply (reconnect with new settings)
          await callService.applyDubbingSettings();
          
          // Show snackbar
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  enabled
                      ? 'Translation enabled: ${_getLanguageName(language)}'
                      : 'Translation disabled',
                ),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
      ),
    );
  }

  String _getLanguageName(String code) {
    const languages = {
      'en': 'English',
      'es': 'Spanish',
      'fr': 'French',
      'de': 'German',
      'hi': 'Hindi',
      'zh': 'Chinese',
      'ja': 'Japanese',
      'ko': 'Korean',
      'ru': 'Russian',
      'pt': 'Portuguese',
    };
    return languages[code] ?? code.toUpperCase();
  }
}

class AudioWaveformPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(0, size.height / 2);
    // Draw a fake waveform
    for (double i = 0; i < size.width; i += 10) {
      path.relativeLineTo(5, (i % 20 == 0) ? -10 : 10);
      path.relativeLineTo(5, (i % 20 == 0) ? 10 : -10);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final Color color;
  final VoidCallback onTap;
  final String? label;

  const _ControlButton({
    required this.icon,
    this.isActive = false,
    this.color = Colors.white,
    required this.onTap,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(35),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.white
                  : (color == Colors.red
                      ? Colors.red
                      : Colors.white.withOpacity(0.2)),
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                color: isActive ? const Color(0xFF4338CA) : Colors.white,
                size: 28),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 8),
          Text(
            label!,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}
