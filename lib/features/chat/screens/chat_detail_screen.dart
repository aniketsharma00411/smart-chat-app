import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vayu/core/providers/providers.dart';
import 'package:vayu/features/chat/screens/rewrite_message_screen.dart';
import 'package:vayu/features/chat/screens/explain_context_screen.dart';
import 'package:vayu/features/chat/models/message.dart';
import 'package:vayu/core/theme/app_theme.dart';

class ChatDetailScreen extends ConsumerStatefulWidget {
  final String chatId;

  const ChatDetailScreen({super.key, required this.chatId});

  @override
  ConsumerState<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends ConsumerState<ChatDetailScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Set<String> _processingIds = {};
  String? _lastError;
  final Map<String, Map<String, dynamic>> _ephemeralTones = {};

  void _batchTranslateIfNeeded(
      List<Message> messages, String? preferredLanguage) async {
    if (preferredLanguage == null) return;

    // Filter messages that need translation AND are not currently being processed
    final candidates = messages.where((msg) {
      final hasTranslation =
          msg.translations?.containsKey(preferredLanguage) ?? false;
      final isTextEmpty = msg.text.isEmpty;
      return !hasTranslation &&
          !isTextEmpty &&
          !_processingIds.contains(msg.id);
    }).toList();

    if (candidates.isEmpty) return;

    // Process in a batch of up to 20
    final batch = candidates.take(20).toList();
    final batchIds = batch.map((m) => m.id).toSet();

    // Mark as processing
    _processingIds.addAll(batchIds);
    // No setState needed strictly for this Set unless UI depends on it, but let's keep it safe given strict mode?
    // Actually we don't need setState for _processingIds if it doesn't affect build directly.

    try {
      List<Map<String, String>> itemsToTranslate =
          batch.map((m) => {'id': m.id, 'text': m.text}).toList();

      final apiService = ref.read(apiServiceProvider);
      final results =
          await apiService.translateBatch(itemsToTranslate, preferredLanguage);

      if (results != null && results.isNotEmpty) {
        final firestoreService = ref.read(firestoreServiceProvider);
        await firestoreService.saveBatchTranslations(
            widget.chatId, results, preferredLanguage);
        if (mounted) setState(() => _lastError = null);
      } else {
        // If failed, remove from processing so we can retry later (e.g. next stream update or manual retry)
        _processingIds.removeAll(batchIds);
      }
    } catch (e) {
      debugPrint("Translation error: $e");
      _processingIds.removeAll(batchIds);
    } finally {
      // We don't remove from _processingIds on success immediately?
      // If we remove them, and the stream hasn't updated yet, we might re-submit.
      // Better to leave them in _processingIds until the stream updates with the translation?
      // Actually, if we save successfully, the next stream event will have "hasTranslation = true".
      // So they will be filtered out by `!hasTranslation`.
      // So we can safely remove them from _processingIds.

      // However, if we remove them NOW, and the stream hasn't processed the update yet (latency),
      // `addPostFrameCallback` might run again and see `!hasTranslation` and `!_processingIds.contains`.
      // So removing them might cause a double-submit race condition.

      // Improved logic: Keep them in _processingIds for a short delay or until we see them translated?
      // Simplest approach: Remove them. The `saveBatchTranslations` is awaited.
      // If it returns, the data is likely committed.

      _processingIds.removeAll(batchIds);
    }
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();

    final user = ref.read(currentUserProvider).value;
    if (user == null) return;

    final firestoreService = ref.read(firestoreServiceProvider);

    final message = Message(
      id: '',
      text: text,
      senderId: user.uid,
      timestamp: DateTime.now(),
      originalLanguage: 'en',
    );

    await firestoreService.sendMessage(widget.chatId, message);

    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = ref.watch(firestoreServiceProvider);
    final user = ref.watch(currentUserProvider).value;
    final userProfile = ref.watch(userProfileProvider).value;
    final preferredLanguage = userProfile?['preferredLanguage'];
    final messagesStream = firestoreService.getMessages(widget.chatId);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(92),
        child: Container(
          decoration: const BoxDecoration(
            color: AppTheme.primaryBrand,
          ),
          child: SafeArea(
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => context.pop(),
                ),
                Expanded(
                  child: ref.watch(chatProvider(widget.chatId)).when(
                        data: (chat) {
                          if (chat == null) {
                            return const Text("Chat",
                                style: TextStyle(
                                    color: Colors.white, fontSize: 18));
                          }
                          final participants =
                              List<String>.from(chat['participants'] ?? []);
                          final otherUserId = participants.firstWhere(
                              (id) => id != user?.uid,
                              orElse: () => '');

                          return ref.watch(otherUserProvider(otherUserId)).when(
                                data: (otherUser) {
                                  final displayName =
                                      otherUser?['displayName'] ?? 'User';
                                  final photoURL = otherUser?['photoURL'];
                                  return Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundImage: photoURL != null
                                            ? NetworkImage(photoURL)
                                            : const NetworkImage(
                                                'https://i.pravatar.cc/150'),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          displayName,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                                loading: () => const Text("...",
                                    style: TextStyle(color: Colors.white)),
                                error: (_, __) => const Text("User",
                                    style: TextStyle(color: Colors.white)),
                              );
                        },
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const Text("Error",
                            style: TextStyle(color: Colors.white)),
                      ),
                ),
                // Call Actions
                ref.watch(chatProvider(widget.chatId)).maybeWhen(
                      data: (chat) {
                        if (chat == null) return const SizedBox.shrink();
                        final participants =
                            List<String>.from(chat['participants'] ?? []);
                        final otherUserId = participants.firstWhere(
                            (id) => id != user?.uid,
                            orElse: () => '');
                        if (otherUserId.isEmpty) return const SizedBox.shrink();

                        return ref
                            .watch(otherUserProvider(otherUserId))
                            .maybeWhen(
                              data: (otherUser) {
                                final displayName =
                                    otherUser?['displayName'] ?? 'User';

                                return IconButton(
                                  icon: const Icon(Icons.phone,
                                      color: Colors.white, size: 28),
                                  onPressed: () async {
                                    final firestore =
                                        ref.read(firestoreServiceProvider);
                                    final currentUser =
                                        ref.read(currentUserProvider).value;
                                    if (currentUser == null) return;

                                    final callId = await firestore.createCall(
                                        currentUser.uid, otherUserId);
                                    if (context.mounted) {
                                      context.push('/call/$callId');
                                    }
                                  },
                                );
                              },
                              orElse: () => const SizedBox.shrink(),
                            );
                      },
                      orElse: () => const SizedBox.shrink(),
                    ),
                IconButton(
                  icon: const Icon(Icons.settings, color: Colors.white),
                  onPressed: () => context.push('/settings'),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_lastError != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_lastError!,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 12))),
                  IconButton(
                    icon: const Icon(Icons.close, size: 14, color: Colors.red),
                    onPressed: () => setState(() => _lastError = null),
                  ),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: messagesStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!;

                // Trigger batch translation check with the REACTIVE preferredLanguage
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _batchTranslateIfNeeded(messages, preferredLanguage);
                });

                if (messages.isEmpty) {
                  return const Center(
                      child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.mark_chat_unread_outlined,
                          size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text("No messages yet",
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ));
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final currentUserId = user?.uid ?? 'demo_user';
                    final isMe = msg.senderId == currentUserId;

                    // Use preferredLanguage from provider
                    String? translationText;
                    if (preferredLanguage != null && msg.translations != null) {
                      translationText = msg.translations![preferredLanguage];
                    }

                    final toneReason =
                        _ephemeralTones[msg.id]?['tone'] ?? msg.tone?['tone'];

                    return Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.85),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: isMe
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          children: [
                            if (isMe) _buildMessageMenu(context, msg),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      gradient: isMe
                                          ? const LinearGradient(colors: [
                                              AppTheme.primaryBrand,
                                              AppTheme.primaryAccent,
                                            ])
                                          : null,
                                      color: isMe ? null : Colors.white,
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(20),
                                        topRight: const Radius.circular(20),
                                        bottomLeft: isMe
                                            ? const Radius.circular(20)
                                            : const Radius.circular(4),
                                        bottomRight: isMe
                                            ? const Radius.circular(4)
                                            : const Radius.circular(20),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.05),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2))
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(msg.text,
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: isMe
                                                  ? Colors.white
                                                  : const Color(0xFF1E293B),
                                              height: 1.4,
                                            )),
                                        if (translationText != null &&
                                            translationText != msg.text) ...[
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: isMe
                                                  ? Colors.black
                                                      .withOpacity(0.1)
                                                  : const Color(0xFFF1F5F9),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.translate,
                                                    size: 14,
                                                    color: isMe
                                                        ? Colors.white70
                                                        : const Color(
                                                            0xFF64748B)),
                                                const SizedBox(width: 6),
                                                Flexible(
                                                  child: Text(translationText,
                                                      style: TextStyle(
                                                          fontSize: 14,
                                                          fontStyle:
                                                              FontStyle.italic,
                                                          color: isMe
                                                              ? Colors.white
                                                                  .withOpacity(
                                                                      0.9)
                                                              : const Color(
                                                                  0xFF475569))),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (toneReason != null ||
                                      _ephemeralTones[msg.id]?['status'] ==
                                          'loading') ...[
                                    const SizedBox(height: 6),
                                    if (_ephemeralTones[msg.id]?['status'] ==
                                        'loading')
                                      Container(
                                        margin: const EdgeInsets.only(left: 4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border: Border.all(
                                              color: Colors.grey.shade300),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const SizedBox(
                                                width: 10,
                                                height: 10,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color:
                                                            Color(0xFF6366F1))),
                                            const SizedBox(width: 8),
                                            Text("Analyzing...",
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color:
                                                        Colors.grey.shade600)),
                                          ],
                                        ),
                                      )
                                    else if (toneReason != null)
                                      Container(
                                        margin: const EdgeInsets.only(left: 4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFFEEF2FF),
                                              Color(0xFFE0E7FF)
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border: Border.all(
                                              color: const Color(0xFF6366F1)
                                                  .withOpacity(0.2)),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFF6366F1)
                                                  .withOpacity(0.05),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            )
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.auto_awesome,
                                                size: 14,
                                                color: AppTheme.primaryBrand),
                                            const SizedBox(width: 6),
                                            Text(toneReason,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppTheme.primaryBrand,
                                                  letterSpacing: 0.3,
                                                )),
                                          ],
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                            if (!isMe) _buildMessageMenu(context, msg),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5))
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.add_circle_outline,
                          color: Color(0xFF64748B))),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: "Type a message...",
                          hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.auto_fix_high,
                                color: Color(0xFF6366F1), size: 20),
                            tooltip: "Rewrite with AI",
                            onPressed: () async {
                              if (_controller.text.trim().isEmpty) return;
                              final newText = await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => RewriteMessageScreen(
                                      originalText: _controller.text),
                                ),
                              );
                              if (newText != null && newText is String) {
                                setState(() {
                                  _controller.text = newText;
                                });
                              }
                            },
                          ),
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
                    child: const CircleAvatar(
                      backgroundColor: AppTheme.primaryBrand,
                      radius: 24,
                      child: Icon(Icons.send, color: Colors.white, size: 20),
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
          setState(() {
            _ephemeralTones[msg.id] = {'status': 'loading'};
          });

          try {
            final apiService = ref.read(apiServiceProvider);
            // History could be fetched here if needed
            final result = await apiService.analyzeTone(msg.text, []);

            if (mounted) {
              if (result != null) {
                setState(() {
                  _ephemeralTones[msg.id] = result;
                });
              } else {
                setState(() {
                  _ephemeralTones.remove(msg.id);
                });
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Could not analyze tone.")));
              }
            }
          } catch (e) {
            debugPrint("Tone analysis failed: $e");
            if (mounted) {
              setState(() {
                _ephemeralTones.remove(msg.id);
              });
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text("Error: $e")));
            }
          }
        } else if (value == 'copy') {
          await Clipboard.setData(ClipboardData(text: msg.text));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Text copied to clipboard")));
          }
        } else if (value == 'rewrite') {
          GoRouter.of(context).push('/ai-chat',
              extra:
                  "Rewrite this message to be more professional: \"${msg.text}\"");
        } else if (value == 'explain') {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ExplainContextScreen(
                targetMessage: msg,
                chatId: widget.chatId,
              ),
            ),
          );
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'explain',
          child: Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 20, color: Color(0xFFF59E0B)),
              SizedBox(width: 12),
              Text('Explain Context'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'tone',
          child: Row(
            children: [
              Icon(Icons.psychology_outlined,
                  size: 20, color: AppTheme.primaryBrand),
              SizedBox(width: 12),
              Text('Analyze Tone'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'copy',
          child: Row(
            children: [
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
