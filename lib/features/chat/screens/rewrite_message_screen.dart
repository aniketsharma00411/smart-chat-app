import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_chat_app/core/providers/providers.dart';

class RewriteMessageScreen extends ConsumerStatefulWidget {
  final String originalText;

  const RewriteMessageScreen({super.key, required this.originalText});

  @override
  ConsumerState<RewriteMessageScreen> createState() =>
      _RewriteMessageScreenState();
}

class _RewriteMessageScreenState extends ConsumerState<RewriteMessageScreen> {
  // Store the conversation history: Each item is { 'type': 'user'|'ai', 'text': '...' }
  final List<Map<String, String>> _conversation = [];

  final TextEditingController _instructionController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _currentDraft; // The latest rewritten text
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Initial rewrite on load removed as per user request
  }

  Future<void> _rewrite(
      {String tone = 'professional', String? instruction}) async {
    setState(() {
      _isLoading = true;
    });

    // Add user instruction to conversation if provided manually (not initial load)
    if (instruction != null && _conversation.isNotEmpty) {
      // Check if the last message wasn't already this instruction (prevent dupes if logic changes)
      if (_conversation.last['text'] != instruction) {
        _conversation.add({'type': 'user', 'text': instruction});
      }
    }

    try {
      final apiService = ref.read(apiServiceProvider);
      // We always rewrite the ORIGINAL text based on new instructions to avoid degrading quality
      // essentially "Apply this instruction to the original message"
      // OR should we refine the latest draft?
      // Plan said: "Refine message...". Usually better to refine the original with new context,
      // or else it turns into a game of telephone.
      // Let's stick to refining the ORIGINAL text but allowing the prompt to be additive if we supported context.
      // For now, simple model: Input + Instruction -> Output.

      final result = await apiService.rewriteMessage(widget.originalText,
          tone: tone, instruction: instruction);

      if (mounted) {
        setState(() {
          if (result != null) {
            _currentDraft = result;
            _conversation.add({'type': 'ai', 'text': result});
          } else {
            _conversation
                .add({'type': 'ai', 'text': "Sorry, I couldn't rewrite that."});
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
      }
    }
  }

  void _handleCustomInstruction() {
    final text = _instructionController.text.trim();
    if (text.isEmpty) return;

    _instructionController.clear();
    // For custom instructions, we might want to neutralise the 'tone' param or keep it default
    // We'll pass the instruction explicitly.
    _rewrite(tone: "neutral", instruction: text);
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
        title: const Text("Refine Message",
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
          // Original Message Preview (Collapsible or just static top)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: const Color(0xFFEFF6FF),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("ORIGINAL",
                    style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0)),
                const SizedBox(height: 4),
                Text(widget.originalText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFF334155), fontStyle: FontStyle.italic)),
              ],
            ),
          ),

          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _conversation.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _conversation.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }

                final item = _conversation[index];
                final isUser = item['type'] == 'user';

                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: isUser
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.85),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color:
                              isUser ? const Color(0xFFE2E8F0) : Colors.white,
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
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 2,
                                      offset: const Offset(0, 1))
                                ],
                          border: isUser
                              ? null
                              : Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                                  Icon(Icons.auto_awesome,
                                      size: 12, color: Color(0xFF6366F1)),
                                  SizedBox(width: 4),
                                  Text("Refined Draft",
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF6366F1),
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            const SizedBox(height: 4),
                            Text(item['text']!,
                                style: const TextStyle(
                                    color: Color(0xFF1E293B), height: 1.4)),
                          ],
                        ),
                      ),
                      if (!isUser)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16, left: 4),
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                Navigator.of(context).pop(item['text']),
                            icon: const Icon(Icons.check,
                                size: 16, color: Colors.white),
                            label: const Text("Use This",
                                style: TextStyle(
                                    fontSize: 12, color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4338CA),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20)),
                              visualDensity: VisualDensity.compact,
                              elevation: 0,
                            ),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Quick Actions
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        _buildChip("Professional",
                            () => _rewrite(tone: "professional")),
                        const SizedBox(width: 8),
                        _buildChip("Casual", () => _rewrite(tone: "casual")),
                        const SizedBox(width: 8),
                        _buildChip("Shorter", () => _rewrite(tone: "concise")),
                        const SizedBox(width: 8),
                        _buildChip(
                            "Fix Grammar",
                            () => _rewrite(
                                tone: "grammatically correct",
                                instruction: "Fix grammar only")),
                      ],
                    ),
                  ),

                  // Text Field
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _instructionController,
                          decoration: InputDecoration(
                            hintText: "E.g. 'Make it sound excited'",
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
                          onSubmitted: (_) => _handleCustomInstruction(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFF4338CA),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.send_rounded,
                              color: Colors.white, size: 20),
                          onPressed: _handleCustomInstruction,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Action Buttons (Only Cancel/Keep Original now)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(), // Keep Original / Cancel
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("Keep Original",
                          style: TextStyle(color: Color(0xFF64748B))),
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

  Widget _buildChip(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: Colors.white,
      side: BorderSide(color: Colors.grey.shade300),
      labelStyle: const TextStyle(
          color: Color(0xFF475569), fontSize: 12, fontWeight: FontWeight.w500),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      visualDensity: VisualDensity.compact,
    );
  }
}
