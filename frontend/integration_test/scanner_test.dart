import 'package:ai_receipt_scanner/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Native scanner opens, recovers without a camera, and returns home',
    (tester) async {
      await tester.pumpWidget(const SnapExpenseApp());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Scan Receipt'));
      await tester.tap(find.text('Scan Receipt'));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      // The iOS simulator has no camera. Real devices may show a live preview instead.
      expect(
        find.text('Capture your receipt and let AI handle the rest.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Upload from Gallery'));
      expect(find.text('Upload from Gallery'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Back to Dashboard'));
      await tester.pumpAndSettle();
      expect(find.text('\$2,450.75'), findsOneWidget);
      // Reopening checks that navigation disposes resources cleanly.
      await tester.tap(find.text('Scan Receipt'));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(find.text('Scan Receipt'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Back to Dashboard'));
      await tester.pumpAndSettle();
    },
  );
}
