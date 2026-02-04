import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/providers.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String callId;

  const CallScreen({super.key, required this.callId});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen>
    with SingleTickerProviderStateMixin {
  bool _isMicOff = false;
  bool _isSpeakerOn = true;
  String _connectionStatus = "Connecting to Server...";
  late AnimationController _pulseController;

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

    // Listen to connection state
    callService.isConnected.listen((connected) {
      if (mounted) {
        setState(() {
          _connectionStatus =
              connected ? "Connected • Dubbing Active" : "Disconnected";
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
    ref.read(callServiceProvider).endCall();
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
          context.pop();
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
                    "AI Dubbing Call",
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
                  const SizedBox(height: 4),
                  Text(
                    "ID: ${widget.callId}", // Debug ID
                    style: TextStyle(color: Colors.white30, fontSize: 8),
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
                            // TODO: Implement toggle in Service
                            setState(() => _isMicOff = !_isMicOff);
                            // ref.read(callServiceProvider).toggleMic();
                          },
                        ),
                        _ControlButton(
                          icon: Icons.call_end,
                          color: Colors.red,
                          onTap: () async {
                            await ref
                                .read(firestoreServiceProvider)
                                .endCall(widget.callId);
                          },
                        ),
                        _ControlButton(
                          icon:
                              _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                          isActive: _isSpeakerOn,
                          onTap: () {
                            setState(() => _isSpeakerOn = !_isSpeakerOn);
                            // TODO: Implement speaker toggle if sound_stream supports it easily
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

  const _ControlButton({
    required this.icon,
    this.isActive = false,
    this.color = Colors.white,
    required this.onTap,
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
      ],
    );
  }
}
