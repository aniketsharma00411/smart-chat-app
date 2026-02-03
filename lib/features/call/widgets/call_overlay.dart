import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_chat_app/core/router/app_router.dart';
import '../../../core/providers/providers.dart';

class CallOverlay extends ConsumerWidget {
  final Widget child;

  const CallOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    if (user == null) return child;

    // Listen for incoming calls to trigger tones
    ref.listen(incomingCallsProvider, (previous, next) {
      final calls = next.value ?? [];
      if (calls.isNotEmpty) {
        final activeCall = calls.first;
        if (activeCall['status'] == 'ringing') {
          ref.read(agoraCallServiceProvider).playIncomingTone();
        }
      } else {
        // If calls becomes empty, stop any ringing
        ref.read(agoraCallServiceProvider).stopTones();
      }
    });

    final incomingCallsAsync = ref.watch(incomingCallsProvider);

    return Stack(
      children: [
        child,
        incomingCallsAsync.when(
          data: (calls) {
            if (calls.isEmpty) return const SizedBox.shrink();

            final activeCall = calls.first; 
            final callerId = activeCall['callerId'];
            final callId = activeCall['id'];

            return FutureBuilder<Map<String, dynamic>?>(
              future: ref.read(firestoreServiceProvider).getUser(callerId),
              builder: (context, userSnapshot) {
                final caller = userSnapshot.data;
                final displayName = caller?['displayName'] ?? "Incoming Call";
                final photoURL = caller?['photoURL'];

                return Material(
                  color: Colors.transparent,
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "Incoming Audio Call",
                            style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 16),
                          CircleAvatar(
                            radius: 40,
                            backgroundImage: photoURL != null ? NetworkImage(photoURL) : const NetworkImage('https://i.pravatar.cc/150'),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            displayName,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _CallActionButton(
                                icon: Icons.close,
                                label: "Decline",
                                color: Colors.red,
                                onTap: () {
                                  ref.read(agoraCallServiceProvider).stopTones();
                                  ref.read(firestoreServiceProvider).updateCallStatus(callId, 'rejected');
                                },
                              ),
                              _CallActionButton(
                                icon: Icons.phone,
                                label: "Accept",
                                color: Colors.green,
                                onTap: () async {
                                  debugPrint("📞 Accepting call: $callId");
                                  ref.read(agoraCallServiceProvider).stopTones();
                                  await ref.read(firestoreServiceProvider).updateCallStatus(callId, 'accepted');
                                  debugPrint("✅ Call status updated to accepted. Navigating...");
                                  ref.read(routerProvider).push('/call/$callId');
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (e, st) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 32),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
      ],
    );
  }
}
