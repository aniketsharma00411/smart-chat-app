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
  String? _rewrittenText;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _rewrite();
  }

  Future<void> _rewrite() async {
    try {
      final apiService = ref.read(apiServiceProvider);
      final result = await apiService.rewriteMessage(widget.originalText);
      if (mounted) {
        setState(() {
          _rewrittenText = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Refine Message",
            style: TextStyle(
                color: Color(0xFF1E293B), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Color(0xFF64748B)),
          onPressed: () => Navigator.of(context).pop(), // Return null
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("ORIGINAL",
                style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(widget.originalText,
                  style: const TextStyle(
                      fontSize: 16, color: Color(0xFF475569), height: 1.5)),
            ),
            const SizedBox(height: 32),
            const Text("REWRITTEN",
                style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2)),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEEF2FF), Color(0xFFE0E7FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: const Color(0xFF818CF8).withOpacity(0.3)),
                ),
                child: _isLoading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: Color(0xFF4338CA)))
                    : _error != null
                        ? Center(
                            child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Colors.red, size: 32),
                              const SizedBox(height: 8),
                              Text("Failed to rewrite",
                                  style: TextStyle(color: Colors.red.shade700)),
                              TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _isLoading = true;
                                      _error = null;
                                    });
                                    _rewrite();
                                  },
                                  child: const Text("Retry"))
                            ],
                          ))
                        : SingleChildScrollView(
                            child: Text(_rewrittenText ?? "",
                                style: const TextStyle(
                                    fontSize: 18,
                                    color: Color(0xFF1E293B),
                                    fontWeight: FontWeight.w500,
                                    height: 1.6)),
                          ),
              ),
            ),
            const SizedBox(height: 32),
            if (!_isLoading && _rewrittenText != null)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(), // Cancel
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("Keep Original",
                          style: TextStyle(color: Color(0xFF64748B))),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context)
                          .pop(_rewrittenText), // Return new text
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4338CA),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text("Use This",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
