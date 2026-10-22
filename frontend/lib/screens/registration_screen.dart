import 'package:flutter/material.dart';
import 'account_screen.dart';

class RegistrationScreen extends StatelessWidget {
  const RegistrationScreen({super.key});
  @override
  Widget build(BuildContext context) => const AccountScreen(register: true);
}
