import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../constant.dart';

class AiChatbotSupport extends StatefulWidget {
  final String userRole;
  final String userName;
  final String localIp;

  const AiChatbotSupport({
    super.key,
    required this.userRole,
    required this.userName,
    required this.localIp,
  });

  @override
  State<AiChatbotSupport> createState() => _AiChatbotSupportState();
}

class _AiChatbotSupportState extends State<AiChatbotSupport> {
  bool _isChatOpen = false;
  bool _isTyping = false;
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String get _backendUrl => '$backendUrl/ai/chat';

  List<String> get _quickSuggestions {
    switch (widget.userRole.toLowerCase()) {
      case 'admin':
      case 'staff':
        return [
          'How do I add a new driver?',
          'How do I delete a user?',
          'Report a system bug',
        ];
      case 'driver':
        return [
          'EMERGENCY: I got into an accident!',
          'The app is freezing.',
          'How do I check my schedule?',
        ];
      case 'oic':
        return [
          'How do I request a new shuttle?',
          'I found a bug on the dashboard.',
          'How do I submit feedback?',
        ];
      default:
        return ['How do I navigate this app?', 'Report a bug'];
    }
  }

  @override
  void initState() {
    super.initState();
    _messages.add({
      'role': 'bot',
      'text':
          'Hello ${widget.userName}! I am Shervice Support. I can help you navigate the app, report bugs, or trigger emergency alerts for dispatch staff. How can I help?',
      'isEmergency': false,
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    _inputController.clear();
    setState(() {
      _messages.add({'role': 'user', 'text': text, 'isEmergency': false});
      _isTyping = true;
    });
    _scrollToBottom();

    try {
      final response = await http
          .post(
            Uri.parse(_backendUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'message': text,
              'role': widget.userRole,
              'name': widget.userName,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final replyText = data['response'] ?? "I received your message.";
        final action = data['action'] ?? "normal";

        _addBotResponse(replyText, isEmergency: action == 'emergency');
      } else {
        _addBotResponse(
          "Server offline. If this is an emergency, please call GT LANTIN dispatch directly via phone.",
        );
      }
    } catch (e) {
      debugPrint("❌ Chatbot Error: $e");
      _addBotResponse(
        "Connection failed. Ensure you are connected to the correct local hotspot.",
      );
    }
  }

  void _addBotResponse(String text, {bool isEmergency = false}) {
    if (!mounted) return;
    setState(() {
      _isTyping = false;
      _messages.add({'role': 'bot', 'text': text, 'isEmergency': isEmergency});
    });
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    // Add extra space for a bottom navigation bar on mobile (typical height ~60-70)
    const bottomNavHeight = 65.0;

    return Stack(
      children: [
        // Floating Action Button
        Positioned(
          bottom: 20 + (isMobile ? bottomNavHeight : 0),
          right: 20,
          child: FloatingActionButton(
            onPressed: () => setState(() => _isChatOpen = !_isChatOpen),
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Icon(
              _isChatOpen ? Icons.close : Icons.support_agent,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ),

        // Chat Dialog Window
        if (_isChatOpen)
          Positioned(
            bottom: 90 + (isMobile ? bottomNavHeight : 0),
            right: 20,
            child: Card(
              elevation: 12,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: isMobile ? MediaQuery.of(context).size.width - 40 : 380,
                height: isMobile
                    ? MediaQuery.of(context).size.height * 0.6
                    : 500,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.support_agent,
                            color: Theme.of(context).colorScheme.onPrimary,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Shervice Support',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Messages List
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isUser = msg['role'] == 'user';
                          final isEmergency = msg['isEmergency'] ?? false;

                          return Align(
                            alignment: isUser
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isEmergency
                                    ? Colors.red.shade100
                                    : (isUser
                                        ? Colors.blue.shade600
                                        : Colors.grey.shade100),
                                border: isEmergency
                                    ? Border.all(
                                        color: Colors.red.shade400,
                                        width: 2,
                                      )
                                    : null,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(14),
                                  topRight: const Radius.circular(14),
                                  bottomLeft: isUser
                                      ? const Radius.circular(14)
                                      : const Radius.circular(0),
                                  bottomRight: isUser
                                      ? const Radius.circular(0)
                                      : const Radius.circular(14),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (isEmergency)
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 4.0),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.warning_amber_rounded,
                                            color: Colors.red,
                                            size: 16,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'EMERGENCY BROADCASTED',
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  Text(
                                    msg['text'],
                                    style: TextStyle(
                                      color: isUser
                                          ? Colors.white
                                          : const Color(0xFF0F172A),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // Typing Indicator
                    if (_isTyping)
                      const Padding(
                        padding: EdgeInsets.only(left: 16, bottom: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Support is typing...',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ),

                    // Suggestions
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: _quickSuggestions.map((suggestion) {
                          final isSos = suggestion.contains('EMERGENCY');
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              label: Text(
                                suggestion,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isSos
                                      ? Colors.red.shade800
                                      : Colors.blue.shade800,
                                ),
                              ),
                              onPressed: () => _sendMessage(suggestion),
                              backgroundColor: isSos
                                  ? Colors.red.shade50
                                  : Colors.blue.shade50,
                              side: BorderSide(
                                color: isSos
                                    ? Colors.red.shade200
                                    : Colors.blue.shade100,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Input Box with AI Disclaimer
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _inputController,
                                  decoration: InputDecoration(
                                    hintText: 'Type a message...',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                    filled: true,
                                    fillColor: Colors.grey.shade100,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                  ),
                                  onSubmitted: _sendMessage,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.send, color: Colors.blue),
                                onPressed: () =>
                                    _sendMessage(_inputController.text),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Shervice Copilot is an AI and can make mistakes. Please verify important logistics.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}