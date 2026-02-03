import 'dart:async';
import 'package:flutter/material.dart';
import 'package:smart_chat_app/core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {
  bool _isMuted = false;
  bool _isSpeaker = true;
  bool _isVideoOff = true; // Audio call by default
  Duration _duration = Duration.zero;
  Timer? _timer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _duration = Duration(seconds: timer.tick));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E1B4B), Color(0xFF312E81), Color(0xFF4338CA)], // Deep Indigo
          ),
        ),
        child: Column(
          children: [
             const Spacer(flex: 2),
             // Avatar Pulse Animation
             ScaleTransition(
               scale: Tween<double>(begin: 1.0, end: 1.1).animate(
                 CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut)
               ),
               child: Container(
                 decoration: BoxDecoration(
                   shape: BoxShape.circle,
                   boxShadow: [
                     BoxShadow(
                       color: AppTheme.primaryAccent.withOpacity(0.5),
                       blurRadius: 40,
                       spreadRadius: 10,
                     )
                   ]
                 ),
                 child: const CircleAvatar(
                   radius: 80,
                   backgroundImage: NetworkImage('https://i.pravatar.cc/150?u=demo'),
                   backgroundColor: Colors.white24,
                 ),
               ),
             ),
             const SizedBox(height: 32),
             const Text(
               "Jane Doe",
               style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
             ),
             const SizedBox(height: 8),
             Text(
               _formatDuration(_duration),
               style: const TextStyle(fontSize: 16, color: Colors.white70, letterSpacing: 1.2),
             ),
             const Spacer(flex: 3),
             
             // Glassmorphism Controls
             Container(
               margin: const EdgeInsets.all(24),
               padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
               decoration: BoxDecoration(
                 color: Colors.white.withOpacity(0.1),
                 borderRadius: BorderRadius.circular(32),
                 border: Border.all(color: Colors.white.withOpacity(0.2)),
                 boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10))
                 ]
               ),
               child: Row(
                 mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                 children: [
                   _buildControlButton(
                     icon: _isMuted ? Icons.mic_off : Icons.mic,
                     isActive: _isMuted,
                     onTap: () => setState(() => _isMuted = !_isMuted),
                   ),
                   _buildControlButton(
                     icon: _isVideoOff ? Icons.videocam_off : Icons.videocam,
                     isActive: _isVideoOff,
                     onTap: () => setState(() => _isVideoOff = !_isVideoOff),
                   ),
                   _buildControlButton(
                     icon: _isSpeaker ? Icons.volume_up : Icons.volume_off,
                     isActive: _isSpeaker,
                     onTap: () => setState(() => _isSpeaker = !_isSpeaker),
                   ),
                   Container(
                     height: 56, width: 56,
                     decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                     child: IconButton(
                       onPressed: () => context.pop(),
                       icon: const Icon(Icons.call_end, color: Colors.white),
                     ),
                   ),
                 ],
               ),
             ),
             const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({required IconData icon, required bool isActive, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56, width: 56,
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.white.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: isActive ? AppTheme.textPrimary : Colors.white),
      ),
    );
  }
}
