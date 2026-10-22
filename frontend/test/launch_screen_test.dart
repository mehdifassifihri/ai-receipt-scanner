import 'package:ai_receipt_scanner/main.dart';
import 'package:ai_receipt_scanner/widgets/snapexpense_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Poppins');
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      loader.addFont(rootBundle.load('assets/fonts/Poppins-$weight.ttf'));
    }
    await loader.load();
  });

  testWidgets('Monochrome mark reveals color and enters Dashboard once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SnapExpenseApp());
    expect(find.byType(SnapExpenseMark), findsNWidgets(2));
    final clip = tester.widget<ClipPath>(find.byType(ClipPath));
    expect(clip.clipper!.getClip(const Size(104, 104)).getBounds().width, 0);
    expect(find.text('Welcome back'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1000));
    final midway = tester.widget<ClipPath>(find.byType(ClipPath));
    final width = midway.clipper!
        .getClip(const Size(104, 104))
        .getBounds()
        .width;
    expect(width, greaterThan(0));
    expect(width, lessThan(150));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byType(SnapExpenseMark), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(SnapExpenseMark), findsNothing);
    await tester.ensureVisible(find.byTooltip('Open Analytics'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open Analytics'));
    await tester.pumpAndSettle();
    expect(find.text('Analytics'), findsOneWidget);
    expect(find.text('No spending data yet'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SnapExpenseMark), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reduced motion uses a brief reveal', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(const SnapExpenseApp());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byType(SnapExpenseMark), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
