import 'package:flutter/widgets.dart';

/// Données de présentation du compte, sans exposer le SDK ou ses jetons aux vues.
class AccountScope extends InheritedWidget {
  const AccountScope({
    super.key,
    required this.email,
    required this.firstName,
    required this.signOut,
    required super.child,
  });
  final String? email;
  final String? firstName;
  final Future<void> Function() signOut;
  static AccountScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountScope>();
  @override
  bool updateShouldNotify(AccountScope oldWidget) =>
      email != oldWidget.email ||
      firstName != oldWidget.firstName ||
      signOut != oldWidget.signOut;
}
