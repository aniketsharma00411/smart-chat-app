import 'package:vayu/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vayu/core/providers/providers.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  String _selectedLanguage = 'en';
  bool _isLoadingLanguage = false;

  final Map<String, String> _languages = {
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

  @override
  void initState() {
    super.initState();
    _loadCurrentLanguage();
  }

  Future<void> _loadCurrentLanguage() async {
    final user = ref.read(currentUserProvider).value;
    if (user != null) {
      final firestoreService = ref.read(firestoreServiceProvider);
      final userDoc = await firestoreService.getUser(user.uid);
      if (userDoc != null && userDoc.containsKey('preferredLanguage')) {
        if (mounted) {
          setState(() {
            _selectedLanguage = userDoc['preferredLanguage'];
          });
        }
      }
    }
  }

  Future<void> _saveLanguage(String? newValue) async {
    if (newValue == null) return;

    setState(() {
      _selectedLanguage = newValue;
      _isLoadingLanguage = true;
    });

    try {
      final user = ref.read(currentUserProvider).value;
      if (user != null) {
        final firestoreService = ref.read(firestoreServiceProvider);
        await firestoreService.updateUserLanguage(user.uid, newValue);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving language: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLanguage = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showAddContactDialog() {
    final TextEditingController emailController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text("Add New Contact"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  "Enter the email address of the user you want to add."),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: "Email Address",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 16.0),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      final email = emailController.text.trim();
                      if (email.isEmpty || !email.contains('@')) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text("Invalid email address")));
                        return;
                      }

                      setState(() => isLoading = true);

                      try {
                        final firestoreService =
                            ref.read(firestoreServiceProvider);
                        final currentUser = ref.read(currentUserProvider).value;

                        if (currentUser == null) {
                          setState(() => isLoading = false);
                          return;
                        }

                        if (email == currentUser.email) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text("You cannot add yourself")));
                          setState(() => isLoading = false);
                          return;
                        }

                        final targetUser =
                            await firestoreService.searchUserByEmail(email);

                        if (targetUser != null) {
                          final chatId = await firestoreService.createChat(
                              currentUser.uid, targetUser['uid']);

                          if (context.mounted) {
                            Navigator.pop(context); // Close dialog
                            context.push('/chats/detail/$chatId');
                          }
                        } else {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        "User not found with this email")));
                            setState(() => isLoading = false);
                          }
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Error: $e")));
                          setState(() => isLoading = false);
                        }
                      }
                    },
              child: const Text("Add Contact"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final user = userAsync.value;
    final authService = ref.read(authServiceProvider);
    final firestoreService = ref.read(firestoreServiceProvider);

    // Zego Calling removed for Agora migration

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  hintText: "Search contacts...",
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.white70),
                ),
                style: const TextStyle(color: Colors.white),
                onChanged: (value) =>
                    setState(() => _searchQuery = value.toLowerCase()),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/branding/app_icon.png',
                    height: 48, // Increased size
                    width: 48,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.error, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.3)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedLanguage,
                          isExpanded: false,
                          isDense: true,
                          dropdownColor: AppTheme.primaryBrand,
                          icon: _isLoadingLanguage
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.keyboard_arrow_down,
                                  color: Colors.white, size: 20),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500),
                          items: _languages.entries.map((entry) {
                            return DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(
                                entry.value.split(' ')[0],
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: _isLoadingLanguage ? null : _saveLanguage,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
        elevation: 0,
        backgroundColor: AppTheme.primaryBrand,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search,
                  color: Colors.white),
              tooltip: _isSearching ? "Close Search" : "Search Contacts",
              onPressed: () {
                setState(() {
                  if (_isSearching) {
                    _isSearching = false;
                    _searchQuery = "";
                    _searchController.clear();
                  } else {
                    _isSearching = true;
                  }
                });
              }),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: "Settings",
            onPressed: () {
              context.push('/settings');
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [AppTheme.primaryBrand, AppTheme.primaryAccent]),
              ),
              accountName: Text(user?.displayName ?? "Demo User",
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              accountEmail: Text(user?.email ?? "demo@smartchat.com"),
              currentAccountPicture: Container(
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2)),
                child: CircleAvatar(
                  backgroundColor: Colors.white,
                  backgroundImage: user?.photoURL != null
                      ? NetworkImage(user!.photoURL!)
                      : null,
                  child: user?.photoURL == null
                      ? const Text("D",
                          style: TextStyle(color: Color(0xFF4338CA)))
                      : null,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_add_outlined),
              title: const Text("Add Contact"),
              onTap: () {
                Navigator.pop(context); // Close drawer
                _showAddContactDialog();
              },
            ),
            const Spacer(),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Color(0xFFEF4444)),
              title: const Text("Sign Out",
                  style: TextStyle(
                      color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
              onTap: () async {
                await authService.signOut();
                if (context.mounted) context.go('/login');
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: firestoreService.getChats(user.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }

                final allChats = snapshot.data ?? [];

                if (allChats.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Opacity(
                            opacity: 0.5,
                            child: Icon(Icons.chat_bubble_outline, size: 64)),
                        const SizedBox(height: 16),
                        const Text("No active chats.",
                            style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _showAddContactDialog,
                          icon: const Icon(Icons.person_add),
                          label: const Text("Start New Chat"),
                        )
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: allChats.length,
                  itemBuilder: (context, index) {
                    final chat = allChats[index];
                    final participants =
                        List<String>.from(chat['participants'] ?? []);
                    final otherUserId = participants
                        .firstWhere((id) => id != user.uid, orElse: () => '');

                    if (otherUserId.isEmpty) return const SizedBox.shrink();

                    return FutureBuilder<Map<String, dynamic>?>(
                        future: firestoreService.getUser(otherUserId),
                        builder: (context, userSnapshot) {
                          if (!userSnapshot.hasData) {
                            return const ListTile(
                              leading: CircleAvatar(child: Icon(Icons.person)),
                              title: Text("Loading..."),
                            );
                          }

                          final otherUser = userSnapshot.data!;
                          final displayName =
                              otherUser['displayName'] ?? 'Unknown User';

                          if (_searchQuery.isNotEmpty &&
                              !displayName
                                  .toLowerCase()
                                  .contains(_searchQuery) &&
                              !(otherUser['email'] ?? '')
                                  .toLowerCase()
                                  .contains(_searchQuery)) {
                            return const SizedBox.shrink();
                          }

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage: otherUser['photoURL'] != null
                                  ? NetworkImage(otherUser['photoURL'])
                                  : null,
                              child: otherUser['photoURL'] == null
                                  ? Text(displayName[0].toUpperCase())
                                  : null,
                            ),
                            title: Text(displayName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              chat['lastMessage']?.toString().isNotEmpty == true
                                  ? chat['lastMessage']
                                  : 'Start a conversation',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              context.push('/chats/detail/${chat['id']}');
                            },
                          );
                        });
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddContactDialog,
        child: const Icon(Icons.person_add),
      ),
    );
  }
}
