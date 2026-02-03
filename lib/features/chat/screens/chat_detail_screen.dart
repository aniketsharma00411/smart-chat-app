import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_chat_app/core/providers/providers.dart';
import 'package:smart_chat_app/features/chat/models/message.dart';

class ChatDetailScreen extends ConsumerStatefulWidget {
  final String chatId;

  const ChatDetailScreen({super.key, required this.chatId});

  @override
  ConsumerState<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends ConsumerState<ChatDetailScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _targetLanguage = 'es'; // Default to Spanish for demo

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();

    final user = ref.read(currentUserProvider).value;
    if (user == null) return;

    final apiService = ref.read(apiServiceProvider);
    final firestoreService = ref.read(firestoreServiceProvider);

    // 1. Analyze Tone (Basic approach: analyze current text + mock history for now)
    // To do it properly, we'd fetch previous messages. 
    // For MVP/Demo as per request 'Gateway API' usage:
    final toneResult = await apiService.analyzeTone(text, ["History placeholder"]); 
    
    // 2. Translate
    final translationResult = await apiService.translateMessage(text, _targetLanguage);

    final message = Message(
      id: '', // Firestore generates this if using .add(), but we construct it here just for model
      text: text,
      senderId: user.uid,
      timestamp: DateTime.now(),
      tone: toneResult,
      translation: translationResult,
      originalLanguage: 'en', // Assuming English input for now
    );

    await firestoreService.sendMessage(widget.chatId, message);
    
    // Scroll to bottom
    if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = ref.watch(firestoreServiceProvider);
    final user = ref.watch(currentUserProvider).value;
    final messagesStream = firestoreService.getMessages(widget.chatId);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Slate 50
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF4338CA), Color(0xFF6366F1)], // Indigo gradients
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        title: Row(
          children: [
            const CircleAvatar(backgroundImage: NetworkImage('https://i.pravatar.cc/150'), radius: 16),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Chat ${widget.chatId}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                const Text("Online", style: TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: () => context.push('/call'),
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
              child: const Icon(Icons.call, color: Colors.white, size: 20),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _targetLanguage,
                dropdownColor: const Color(0xFF1E293B),
                icon: const Icon(Icons.translate, color: Colors.white, size: 18),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                items: const [
                  DropdownMenuItem(value: 'es', child: Text("🇪🇸 Spanish")),
                  DropdownMenuItem(value: 'fr', child: Text("🇫🇷 French")),
                  DropdownMenuItem(value: 'de', child: Text("🇩🇪 German")),
                  DropdownMenuItem(value: 'hi', child: Text("🇮🇳 Hindi")),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _targetLanguage = val);
                },
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: messagesStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final messages = snapshot.data!;
                if (messages.isEmpty) return Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.mark_chat_unread_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text("No messages yet", style: TextStyle(color: Colors.grey)),
                  ],
                ));

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final currentUserId = user?.uid ?? 'demo_user';
                    final isMe = msg.senderId == currentUserId;
                    
                    // For demo: verify if we "revealed" the tone/translation
                    // In a real app, this would be computed or stored in the message model
                    
                    final translationText = msg.translation?['translation'];
                    final toneReason = msg.tone?['tone'];

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85), // Increased width for menu
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end, // Align menu to bottom of bubble
                          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                          children: [
                            if (isMe) _buildMessageMenu(context, msg), // Menu on Left for Me (optional, usually right for everyone, but let's stick to standard)
                            
                            Flexible(
                              child: Column(
                                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      gradient: isMe 
                                        ? const LinearGradient(colors: [Color(0xFF4338CA), Color(0xFF6366F1)])
                                        : null,
                                      color: isMe ? null : Colors.white,
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(20),
                                        topRight: const Radius.circular(20),
                                        bottomLeft: isMe ? const Radius.circular(20) : const Radius.circular(4),
                                        bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(20),
                                      ),
                                      boxShadow: [
                                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          msg.text, 
                                          style: TextStyle(
                                            fontSize: 16, 
                                            color: isMe ? Colors.white : const Color(0xFF1E293B),
                                            height: 1.4,
                                          )
                                        ),
                                        // Only show translation if it exists (simulating it was "requested" or auto-done)
                                        if (translationText != null && translationText != msg.text) ...[
                                           const SizedBox(height: 8),
                                           Container(
                                             padding: const EdgeInsets.all(8),
                                             decoration: BoxDecoration(
                                               color: isMe ? Colors.black.withOpacity(0.1) : const Color(0xFFF1F5F9),
                                               borderRadius: BorderRadius.circular(8),
                                             ),
                                             child: Row(
                                               mainAxisSize: MainAxisSize.min,
                                               children: [
                                                 Icon(Icons.translate, size: 14, color: isMe ? Colors.white70 : const Color(0xFF64748B)),
                                                 const SizedBox(width: 6),
                                                 Flexible(
                                                   child: Text(
                                                     translationText, 
                                                     style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: isMe ? Colors.white.withOpacity(0.9) : const Color(0xFF475569))
                                                   ),
                                                 ),
                                               ],
                                             ),
                                           ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  // Tone Tag - Shown outside/below bubble
                                  if (toneReason != null) ...[
                                     const SizedBox(height: 6),
                                     Container(
                                       margin: const EdgeInsets.only(left: 4),
                                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                       decoration: BoxDecoration(
                                         color: const Color(0xFFFEF3C7), // Amber 100
                                         borderRadius: BorderRadius.circular(12),
                                         border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
                                       ),
                                       child: Row(
                                         mainAxisSize: MainAxisSize.min,
                                         children: [
                                           const Icon(Icons.psychology, size: 12, color: Color(0xFFD97706)),
                                           const SizedBox(width: 4),
                                           Text(toneReason, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFB45309))),
                                         ],
                                       ),
                                     ),
                                  ],
                                ],
                              ),
                            ),
                            
                            if (!isMe) _buildMessageMenu(context, msg), // Menu on Right for Others
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          
          // Input Area
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white, 
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(onPressed: () {}, icon: const Icon(Icons.add_circle_outline, color: Color(0xFF64748B))),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: "Type a message...",
                          hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: CircleAvatar(
                      backgroundColor: const Color(0xFF4338CA),
                      radius: 24,
                      child: const Icon(Icons.send, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageMenu(BuildContext context, Message msg) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20, color: Color(0xFF94A3B8)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      onSelected: (value) async {
        if (value == 'tone') {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Analyzing Tone... (Demo: Tone Revealed)")));
        } else if (value == 'translate') {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Translating...")));
        } else if (value == 'copy') {
           await Clipboard.setData(ClipboardData(text: msg.text));
           if (context.mounted) {
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Text copied to clipboard")));
           }
        } else if (value == 'rewrite') {
           GoRouter.of(context).push('/ai-chat', extra: "Rewrite this message to be more professional: \"${msg.text}\"");
        } else if (value == 'explain') {
           GoRouter.of(context).push('/ai-chat', extra: "Explain the tone and context of this message: \"${msg.text}\"");
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'rewrite',
          child: Row(
            children: const [
              Icon(Icons.edit, size: 20, color: Color(0xFF4338CA)),
              SizedBox(width: 12),
              Text('Rewrite Message'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'explain',
          child: Row(
            children: const [
              Icon(Icons.lightbulb_outline, size: 20, color: Color(0xFFF59E0B)),
              SizedBox(width: 12),
              Text('Explain Context'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'tone',
          child: Row(
            children: const [
              Icon(Icons.psychology_outlined, size: 20, color: Color(0xFF4338CA)),
              SizedBox(width: 12),
              Text('Analyze Tone'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'translate',
          child: Row(
            children: const [
              Icon(Icons.translate_outlined, size: 20, color: Color(0xFF06B6D4)),
              SizedBox(width: 12),
              Text('Translate'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'copy',
          child: Row(
            children: const [
              Icon(Icons.copy_outlined, size: 20),
              SizedBox(width: 12),
              Text('Copy Text'),
            ],
          ),
        ),
      ],
    );
  }
}
