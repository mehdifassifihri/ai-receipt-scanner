import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Native secure storage persists and deletes a synthetic value', (
    tester,
  ) async {
    const storage = FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    );
    final key =
        'snapexpense.audit-probe.${DateTime.now().microsecondsSinceEpoch}';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('Secure storage verification')),
      ),
    );
    try {
      await storage.write(key: key, value: 'synthetic-test-value');
      expect(await storage.read(key: key), 'synthetic-test-value');
      await storage.delete(key: key);
      expect(await storage.read(key: key), isNull);
    } finally {
      await storage.delete(key: key);
    }
  });
}
