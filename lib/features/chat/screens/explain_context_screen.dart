import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayu/core/providers/providers.dart';
import 'package:vayu/features/chat/models/message.dart';

class ExplainContextScreen extends ConsumerStatefulWidget {
  final Message targetMessage;
  final String chatId;

  const ExplainContextScreen(
      {super.key, required this.targetMessage, required this.chatId});

  @override
  ConsumerState<ExplainContextScreen> createState() =>
      _ExplainContextScreenState();
}

class _ExplainContextScreenState extends ConsumerState<ExplainContextScreen> {
  // Store the conversation history: Each item is { 'type': 'user'|'ai', 'text': '...' }
  final List<Map<String, String>> _conversation = [];
  // Keep original history separate to re-send to stateless API if needed
  List<String> _historyContext = [];

  final TextEditingController _instructionController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = false;
  bool _isInitializing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeExplanation();
  }

  Future<void> _initializeExplanation() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final firestoreService = ref.read(firestoreServiceProvider);

      // Fetch messages from Firestore to get context
      // We use the stream first value to get current state
      final stream = firestoreService.getMessages(widget.chatId);
      final messages = await stream.first;

      // Sort by timestamp
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Find target message index
      final targetIndex =
          messages.indexWhere((m) => m.id == widget.targetMessage.id);

      // Get up to 20 previous messages + the target message
      final endIndex = targetIndex == -1 ? messages.length : targetIndex + 1;
      final startIndex = (endIndex - 20) < 0 ? 0 : (endIndex - 20);

      final contextMessages = messages.sublist(startIndex, endIndex);

      // Format context for AI
      _historyContext = contextMessages.map((m) {
        final isMe = m.senderId == widget.targetMessage.senderId;
        // We don't have user names here easily without fetching profiles,
        // so we'll use "User" and "Other" or just sender IDs if needed.
        // Better: "Sender" (of the target message) and "Other".
        final label = isMe ? "Sender" : "Other";
        return "$label: ${m.text}";
      }).toList();

      if (_historyContext.isEmpty) {
        // Fallback if message not found or something
        _historyContext = ["Sender: ${widget.targetMessage.text}"];
      }

      // Initial Call to API
      await _askAI(isInitial: true);
    } catch (e) {
      debugPrint("Error initializing context: $e");
      if (mounted) {
        setState(() {
          _error = "Could not load context: $e";
          _isLoading = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  Future<void> _askAI({String? query, bool isInitial = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    if (query != null) {
      _conversation.add({'type': 'user', 'text': query});
      _scrollToBottom();
    }

    try {
      final apiService = ref.read(apiServiceProvider);

      // If we have no context, we can't do much, but we try anyway.
      final result = await apiService.explainContext(
          widget.targetMessage.text, _historyContext, query);

      if (mounted) {
        setState(() {
          if (result != null) {
            _conversation.add({'type': 'ai', 'text': result});
          } else {
            _conversation.add({
              'type': 'ai',
              'text': "Sorry, I couldn't generate an explanation."
            });
          }
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _conversation.add({'type': 'ai', 'text': "Error: $e"});
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _handleSend() {
    final text = _instructionController.text.trim();
    if (text.isEmpty) return;

    _instructionController.clear();
    _askAI(query: text);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Explain Context",
            style: TextStyle(
                color: Color(0xFF1E293B), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Color(0xFF64748B)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Original Message Preview
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: const Color(0xFFEFF6FF),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("MESSAGE IN CONTEXT",
                    style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0)),
                const SizedBox(height: 4),
                Text(widget.targetMessage.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFF334155), fontStyle: FontStyle.italic)),
              ],
            ),
          ),

          Expanded(
            child: _isInitializing
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text(_error!,
                            style: const TextStyle(color: Colors.red)))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _conversation.length + (_isLoading ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _conversation.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          }

                          final item = _conversation[index];
                          final isUser = item['type'] == 'user';

                          return Align(
                            alignment: isUser
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: isUser
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width *
                                              0.85),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isUser
                                        ? const Color(0xFFE2E8F0)
                                        : Colors.white,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(12),
                                      topRight: const Radius.circular(12),
                                      bottomLeft: isUser
                                          ? const Radius.circular(12)
                                          : const Radius.circular(2),
                                      bottomRight: isUser
                                          ? const Radius.circular(2)
                                          : const Radius.circular(12),
                                    ),
                                    boxShadow: isUser
                                        ? []
                                        : [
                                            BoxShadow(
                                                color: Colors.black
                                                    .withOpacity(0.05),
                                                blurRadius: 2,
                                                offset: const Offset(0, 1))
                                          ],
                                    border: isUser
                                        ? null
                                        : Border.all(
                                            color: Colors.grey.shade200),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (isUser)
                                        const Text("You asked:",
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Color(0xFF64748B),
                                                fontWeight: FontWeight.bold)),
                                      if (!isUser)
                                        Row(
                                          children: const [
                                            Icon(Icons.lightbulb_outline,
                                                size: 12,
                                                color: Color(0xFFF59E0B)),
                                            SizedBox(width: 4),
                                            Text("AI Explanation",
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color: Color(0xFFF59E0B),
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ],
                                        ),
                                      const SizedBox(height: 4),
                                      Text(item['text']!,
                                          style: const TextStyle(
                                              color: Color(0xFF1E293B),
                                              height: 1.4)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),

          // Input Area
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _instructionController,
                      decoration: InputDecoration(
                        hintText: "Ask a follow-up question...",
                        hintStyle: const TextStyle(
                            color: Color(0xFF94A3B8), fontSize: 14),
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _handleSend(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF59E0B), // Amber for "Explain"
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                      onPressed: _handleSend,
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
}
