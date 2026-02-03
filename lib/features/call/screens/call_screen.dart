import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../../../core/providers/providers.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String callId;

  const CallScreen({super.key, required this.callId});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> with SingleTickerProviderStateMixin {
  bool _isMicOff = false;
  bool _isSpeakerOn = true;
  double _localVolume = 0;
  String _connectionStatus = "Connecting (v2)...";
  final Set<int> _remoteUids = {};
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      lowerBound: 1.0,
      upperBound: 1.2,
    );
    _initAgora();
  }

  Future<void> _initAgora() async {
    try {
      debugPrint("🚀 Initializing Agora call flow...");
      setState(() => _connectionStatus = "Step 1: Preparing...");
      
      final user = ref.read(currentUserProvider).value;
      final callService = ref.read(agoraCallServiceProvider);
      
      // Register listeners immediately
      callService.setConnectionListener((status) {
        if (mounted) {
          setState(() => _connectionStatus = status);
          if (status.startsWith("Joined")) {
            callService.stopTones();
          }
        }
      });

      callService.setUserListeners(
        onJoined: (uid) => setState(() => _remoteUids.add(uid)),
        onOffline: (uid) => setState(() => _remoteUids.remove(uid)),
      );

      // Start Agora cleanup and init in Parallel with tone check
      setState(() => _connectionStatus = "Step 2: Connecting...");
      
      // 1. Check tone (Don't await it to block join)
      ref.read(firestoreServiceProvider).getCall(widget.callId).then((callData) {
        if (callData != null && callData['status'] == 'ringing' && callData['callerId'] == user?.uid) {
           callService.playOutgoingTone();
        }
      }).catchError((e) => debugPrint("⚠️ Tone check failed: $e"));

      // 2. Perform Agora Flow
      await callService.release();
      await callService.init();

      // Ensure UID is a positive integer within 32-bit range for Agora
      final uid = (user?.uid.hashCode ?? DateTime.now().millisecondsSinceEpoch).abs() % 10000000;
      debugPrint("👤 Local UID for Agora: $uid");

      callService.setVolumeListener((speakers) {
        if (mounted) {
          final localVolume = speakers.firstWhere(
            (s) => s.uid == 0 || s.uid == uid,
            orElse: () => AudioVolumeInfo(uid: -1, volume: 0, vad: 0, voiceDuration: 0),
          ).volume;
          
          setState(() => _localVolume = localVolume.toDouble());
          if (_localVolume > 10) {
            _pulseController.forward().then((_) => _pulseController.reverse());
          }
        }
      });

      // Join the channel
      await callService.joinChannel(widget.callId, uid); 
      debugPrint("✅ Joined channel successfully");
    } catch (e) {
      debugPrint("❌ Critical failure in _initAgora: $e");
      if (mounted) setState(() => _connectionStatus = "Flow Failed: $e");
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    final callService = ref.read(agoraCallServiceProvider);
    callService.stopTones();
    callService.leaveChannel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen to call stream for side effects (Navigation, Tone control)
    ref.listen(currentCallStreamProvider(widget.callId), (previous, next) {
      final callData = next.value;
      final user = ref.read(currentUserProvider).value;
      if (callData == null) return;
      
      // 1. Handle Navigation (Call Ended/Rejected)
      if (callData['status'] == 'ended' || callData['status'] == 'rejected') {
        if (context.mounted && GoRouterState.of(context).uri.toString().startsWith('/call')) {
          context.pop();
        }
      }

      // 2. Handle Tone Stopping (Call Accepted)
      if (callData['status'] == 'accepted') {
        // If we are calling, stop the outgoing tone
        if (callData['callerId'] == user?.uid) {
           ref.read(agoraCallServiceProvider).stopTones();
        }
      }
    });

    return StreamBuilder<Map<String, dynamic>?>(
      stream: ref.watch(firestoreServiceProvider).streamCall(widget.callId),
      builder: (context, snapshot) {
        final callData = snapshot.data;
        
        // Side effects handled by ref.listen above

        // Side effects handled by ref.listen above

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
                    "Ongoing Audio Call",
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 10),
                  // Connection status pulse/label
                  Text(
                    _remoteUids.isNotEmpty ? "Connected & Live" : "Waiting for other person...",
                    style: TextStyle(color: Colors.indigo.shade100, fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                  Text(
                    _connectionStatus,
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "ID: ${widget.callId}",
                    style: TextStyle(color: Colors.white30, fontSize: 8),
                  ),
                  if (!_connectionStatus.startsWith("Joined"))
                    TextButton.icon(
                      onPressed: _initAgora,
                      icon: const Icon(Icons.refresh, color: Colors.white70, size: 14),
                      label: const Text("Retry Connection", style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ),
                  const SizedBox(height: 20),
                  // User Info
                  if (otherUserId != null)
                    FutureBuilder<Map<String, dynamic>?>(
                      future: ref.read(firestoreServiceProvider).getUser(otherUserId),
                      builder: (context, userSnapshot) {
                        final otherUser = userSnapshot.data;
                        final displayName = otherUser?['displayName'] ?? "User";
                        final photoURL = otherUser?['photoURL'];

                        return Column(
                          children: [
                            ScaleTransition(
                              scale: _pulseController,
                              child: CircleAvatar(
                                radius: 60,
                                backgroundImage: photoURL != null ? NetworkImage(photoURL) : const NetworkImage('https://i.pravatar.cc/150'),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              displayName,
                              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                          ],
                        );
                      },
                    ),
                  const Spacer(),
                  // Controls
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ControlButton(
                          icon: _isMicOff ? Icons.mic_off : Icons.mic,
                          isActive: !_isMicOff,
                          onTap: () {
                            setState(() => _isMicOff = !_isMicOff);
                          },
                        ),
                        _ControlButton(
                          icon: Icons.call_end,
                          color: Colors.red,
                          onTap: () async {
                            await ref.read(firestoreServiceProvider).endCall(widget.callId);
                          },
                        ),
                        _ControlButton(
                          icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                          isActive: _isSpeakerOn,
                          onTap: () {
                            setState(() => _isSpeakerOn = !_isSpeakerOn);
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
              color: isActive ? Colors.white : (color == Colors.red ? Colors.red : Colors.white.withOpacity(0.2)),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: isActive ? const Color(0xFF4338CA) : Colors.white, size: 28),
          ),
        ),
      ],
    );
  }
}
