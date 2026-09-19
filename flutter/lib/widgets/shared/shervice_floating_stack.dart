import 'package:flutter/material.dart';

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
    return child;
  }
}
