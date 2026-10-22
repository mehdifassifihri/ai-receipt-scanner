import 'package:ai_receipt_scanner/app.dart';
import 'package:ai_receipt_scanner/screens/ask_snap_screen.dart';
import 'package:ai_receipt_scanner/widgets/glass_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'iOS native transparency preference is readable and Ask Snap mounts',
    (tester) async {
      const channel = MethodChannel('snapexpense/accessibility');
      final reduceTransparency = await channel.invokeMethod<bool>(
        'isReduceTransparencyEnabled',
      );
      expect(reduceTransparency, isA<bool>());
      await tester.pumpWidget(
        const SnapExpenseApp(destination: AskSnapScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GlassContainer), findsWidgets);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
