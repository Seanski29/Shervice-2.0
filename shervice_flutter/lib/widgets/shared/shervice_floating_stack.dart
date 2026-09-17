import 'package:flutter/material.dart';
import 'ai_chatbot_support.dart';

class SherviceFloatingStack extends StatelessWidget {
  final Widget child;
  final String userRole;
  final String userName;
  final String localIp;

  const SherviceFloatingStack({
    super.key,
    required this.child,
    required this.userRole,
    required this.userName,
    required this.localIp,
  });

  @override
  Widget build(BuildContext context) {
    // This Stack puts your screen content (child) at the bottom, 
    // and the chatbot overlay on top.
    return Stack(
      children: [
        child,
        AiChatbotSupport(
          userRole: userRole,
          userName: userName,
          localIp: localIp,
        ),
      ],
    );
  }
}
