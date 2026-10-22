import 'package:flutter/material.dart';
import 'account_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, this.message});
  final String? message;
  @override
  Widget build(BuildContext context) => AccountScreen(initialMessage: message);
}
