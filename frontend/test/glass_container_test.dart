import 'package:ai_receipt_scanner/screens/ask_snap_screen.dart';
import 'package:ai_receipt_scanner/state/expense_store.dart';
import 'package:ai_receipt_scanner/data/backend_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_receipt_scanner/theme/glass_theme.dart';
import 'package:ai_receipt_scanner/widgets/glass_accessibility.dart';
import 'package:ai_receipt_scanner/widgets/glass_container.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> mount(
  WidgetTester tester, {
  bool highContrast = false,
  bool disableAnimations = false,
  Brightness brightness = Brightness.light,
  Widget? child,
}) {
  final content =
      child ??
      const GlassGroup(
        child: GlassContainer(
          child: SizedBox(width: 200, height: 60, child: Text('Glass')),
        ),
      );
  return tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        extensions: [
          brightness == Brightness.dark ? GlassTheme.dark : GlassTheme.light,
        ],
      ),
      home: MediaQuery(
        data: MediaQueryData(
          highContrast: highContrast,
          disableAnimations: disableAnimations,
        ),
        child: GlassAccessibility(
          child: Scaffold(body: Center(child: content)),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'Adjacent glass surfaces share a stable backdrop key and never blur children',
    (tester) async {
      const content = GlassGroup(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassContainer(child: SizedBox(width: 60, height: 60)),
            SizedBox(width: 8),
            GlassContainer(child: SizedBox(width: 60, height: 60)),
          ],
        ),
      );
      await mount(tester, child: content);
      final filters = tester
          .widgetList<BackdropFilter>(find.byType(BackdropFilter))
          .toList();
      expect(filters.length, 2);
      final renderFilters = find
          .byType(BackdropFilter)
          .evaluate()
          .map((element) => element.renderObject! as RenderBackdropFilter)
          .toList();
      expect(renderFilters.first.backdropKey, isNotNull);
      expect(
        renderFilters.first.backdropKey,
        same(renderFilters.last.backdropKey),
      );
      final key = tester
          .widget<BackdropGroup>(find.byType(BackdropGroup))
          .backdropKey;
      await mount(tester, child: content);
      expect(
        tester.widget<BackdropGroup>(find.byType(BackdropGroup)).backdropKey,
        same(key),
      );
      expect(find.byType(ImageFiltered), findsNothing);
    },
  );
  testWidgets('High contrast and reduced motion remove backdrop sampling', (
    tester,
  ) async {
    await mount(tester, highContrast: true);
    expect(find.byType(BackdropFilter), findsNothing);
    await mount(tester, disableAnimations: true);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
      Duration.zero,
    );
    await mount(tester, brightness: Brightness.dark);
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(
      GlassTheme.of(tester.element(find.byType(GlassContainer))).solidColor,
      GlassTheme.dark.solidColor,
    );
  });
  testWidgets(
    'Press scales, produces a light haptic, and cancellation resets it',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await mount(
        tester,
        child: const GlassContainer(
          interactive: true,
          child: SizedBox(width: 100, height: 60),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(GlassContainer)),
      );
      await tester.pump();
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        1.05,
      );
      expect(
        calls
            .where(
              (c) =>
                  c.method == 'HapticFeedback.vibrate' &&
                  c.arguments == 'HapticFeedbackType.lightImpact',
            )
            .length,
        1,
      );
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    },
  );
  testWidgets(
    'iOS Reduce Transparency updates live and fails closed if channel is missing',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('snapexpense/accessibility');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => true,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await mount(tester);
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      final data = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('reduceTransparencyChanged', false),
      );
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        data,
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      await mount(tester);
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets(
    'Floating composer remains usable with large text and keyboard on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final store = ExpenseStore(
        api: BackendApi(
          baseUrl: 'https://test.example',
          accessToken: () async => 'test',
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
      );
      await tester.pumpWidget(
        ExpenseScope(
          store: store,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.4)),
              child: child!,
            ),
            home: const AskSnapScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.ancestor(
          of: find.byType(BackdropFilter),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull, reason: 'before keyboard');
      await tester.tap(find.byType(TextField));
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Send question').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
  test(
    'Text scrims preserve AA contrast over worst-case black and white backdrops',
    () {
      for (final theme in [GlassTheme.light, GlassTheme.dark]) {
        for (final background in [Colors.white, Colors.black]) {
          final scrim = Color.alphaBlend(theme.textScrim, background);
          final a = scrim.computeLuminance(),
              b = theme.foreground.computeLuminance();
          final ratio = ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05);
          expect(ratio, greaterThanOrEqualTo(4.5));
        }
      }
    },
  );
}
