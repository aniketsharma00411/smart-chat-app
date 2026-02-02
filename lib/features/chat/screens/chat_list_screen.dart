import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_chat_app/core/providers/providers.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  Map<String, dynamic>? _userProfile;

  @override
  void initState() {
    super.initState();
    // ref.read in initState might be too early for StreamProvider value
  }

  Future<void> _loadUserProfile(String uid) async {
    if (!mounted) return;
    final firestoreService = ref.read(firestoreServiceProvider);
    
    try {
      var profile = await firestoreService.getUser(uid);
      
      // If profile is missing or lacks shareId, try to ensure it exists
      if (profile == null || !profile.containsKey('shareId')) {
        if (!mounted) return;
        final authService = ref.read(authServiceProvider);
        final currentUser = ref.read(currentUserProvider).value;
        
        if (currentUser != null && currentUser.uid == uid) {
           await authService.ensureUserDocument(currentUser);
           // Reload profile after fix
           if (mounted) {
             profile = await firestoreService.getUser(uid);
           }
        }
      }

      if (mounted) setState(() => _userProfile = profile);
    } catch (e) {
      debugPrint("Error loading profile: $e");
    }
  }

  void _showSearchDialog() {
    final TextEditingController searchController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Start New Chat"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Enter the 6-digit Share ID of the user you want to chat with."),
            const SizedBox(height: 16),
            TextField(
              controller: searchController,
              decoration: const InputDecoration(
                labelText: "Share ID",
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              final shareId = searchController.text.trim().toUpperCase();
              if (shareId.length != 6) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid ID format")));
                return;
              }
              
              Navigator.pop(context); // Close dialog
              
              try {
                final firestoreService = ref.read(firestoreServiceProvider);
                final targetUser = await firestoreService.searchUserByShareId(shareId);
                
                if (targetUser != null) {
                   final currentUser = ref.read(currentUserProvider).value;
                   if (currentUser != null) {
                     final chatId = await firestoreService.createChat(currentUser.uid, targetUser['uid']);
                     if (context.mounted) context.push('/chats/detail/$chatId');
                   }
                } else {
                   if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("User not found")));
                }
              } catch (e) {
                 if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
              }
            },
            child: const Text("Chat"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final user = userAsync.value;
    final authService = ref.read(authServiceProvider);

    // Listen for user changes to load profile data
    ref.listen(currentUserProvider, (previous, next) {
      final newUser = next.value;
      if (newUser != null && _userProfile == null) {
        _loadUserProfile(newUser.uid);
      }
    });
    
    // Also check immediately in build if we missed the transition
    if (user != null && _userProfile == null) {
       // Defer to next frame to avoid setState during build
       Future.microtask(() => _loadUserProfile(user.uid));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        actions: [
           IconButton(
             icon: const Icon(Icons.search), 
             tooltip: "Search User by ID",
             onPressed: _showSearchDialog
           ),
           IconButton(icon: const Icon(Icons.create_outlined), onPressed: _showSearchDialog), 
           const SizedBox(width: 8),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF4338CA), Color(0xFF6366F1)]),
              ),
              accountName: Text(user?.displayName ?? "Demo User", style: const TextStyle(fontWeight: FontWeight.bold)),
              accountEmail: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user?.email ?? "demo@smartchat.com"),
                  if (_userProfile != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          "ID: ${_userProfile!['shareId']}",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
              currentAccountPicture: Container(
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                child: CircleAvatar(
                  backgroundColor: Colors.white, 
                  backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                  child: user?.photoURL == null ? const Text("D", style: TextStyle(color: Color(0xFF4338CA))) : null,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text("Settings"),
              onTap: () {},
            ),
            const Spacer(),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Color(0xFFEF4444)),
              title: const Text("Sign Out", style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
              onTap: () async {
                await authService.signOut();
                if (context.mounted) context.go('/login');
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      body: Center(
        child: Column( // Temp placeholder until we stream chats
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
             Opacity(opacity: 0.5, child: Icon(Icons.chat_bubble_outline, size: 64)),
             const SizedBox(height: 16),
             Text("Search for a user ID to start chatting!", style: TextStyle(color: Colors.grey[600])),
             const SizedBox(height: 8),
             if (_userProfile != null)
               SelectableText("Your ID: ${_userProfile!['shareId']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        elevation: 2,
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Teams'),
          NavigationDestination(icon: Icon(Icons.calendar_today_outlined), selectedIcon: Icon(Icons.calendar_today), label: 'Calendar'),
        ],
      ),
    );
  }
}
