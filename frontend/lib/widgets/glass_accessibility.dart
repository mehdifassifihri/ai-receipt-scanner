import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Flutter expose contraste/mouvement ; iOS expose la transparence via ce canal.
class GlassAccessibility extends StatefulWidget {
  const GlassAccessibility({super.key, required this.child});
  final Widget child;
  static bool reduceTransparencyOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_TransparencyScope>()
          ?.reduceTransparency ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);
  @override
  State<GlassAccessibility> createState() => _GlassAccessibilityState();
}

class _GlassAccessibilityState extends State<GlassAccessibility>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('snapexpense/accessibility');
  bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  int _generation = 0;
  late bool _reduce =
      _ios; // Opaque tant que la préférence native n’est pas connue.
  @override
  void initState() {
    super.initState();
    if (_ios) {
      WidgetsBinding.instance.addObserver(this);
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'reduceTransparencyChanged' &&
            call.arguments is bool &&
            mounted) {
          setState(() {
            _generation++;
            _reduce = call.arguments as bool;
          });
        }
      });
      unawaited(_read());
    }
  }

  Future<void> _read() async {
    final generation = _generation;
    try {
      final reduce = await _channel.invokeMethod<bool>(
        'isReduceTransparencyEnabled',
      );
      if (mounted && generation == _generation) {
        setState(() => _reduce = reduce ?? true);
      }
    } on PlatformException {
      if (mounted && generation == _generation) setState(() => _reduce = true);
    } on MissingPluginException {
      if (mounted && generation == _generation) setState(() => _reduce = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _ios) unawaited(_read());
  }

  @override
  void dispose() {
    if (_ios) {
      WidgetsBinding.instance.removeObserver(this);
      _channel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _TransparencyScope(reduceTransparency: _reduce, child: widget.child);
}

class _TransparencyScope extends InheritedWidget {
  const _TransparencyScope({
    required this.reduceTransparency,
    required super.child,
  });
  final bool reduceTransparency;
  @override
  bool updateShouldNotify(_TransparencyScope oldWidget) =>
      reduceTransparency != oldWidget.reduceTransparency;
}
