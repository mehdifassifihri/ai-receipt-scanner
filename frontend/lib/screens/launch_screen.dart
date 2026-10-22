import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/snapexpense_mark.dart';
import 'home_shell.dart';

/// A single startup sequence. It stays out of the Navigator history and does not
/// replay when returning home or resuming the app.
class LaunchScreen extends StatefulWidget {
  const LaunchScreen({super.key, this.destination});
  final Widget? destination;

  @override
  State<LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<LaunchScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  bool _started = false;
  bool _finished = false;
  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _controller.duration = Duration(milliseconds: _reducedMotion ? 450 : 2400);
    _controller.forward().whenCompleteOrCancel(() {
      if (mounted) setState(() => _finished = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return widget.destination ?? const HomeShell();
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final reveal = const Interval(
          .18,
          .63,
          curve: Curves.easeInOutCubic,
        ).transform(t);
        final exit = const Interval(
          .79,
          1,
          curve: Curves.easeInOutCubic,
        ).transform(t);
        final lift = _reducedMotion ? 0.0 : math.sin(reveal * math.pi) * .035;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (t >= .79)
              ExcludeSemantics(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: exit,
                    child: Transform.translate(
                      offset: Offset(0, _reducedMotion ? 0 : 10 * (1 - exit)),
                      child: widget.destination ?? const HomeShell(),
                    ),
                  ),
                ),
              ),
            IgnorePointer(
              child: Opacity(
                opacity: 1 - exit,
                child: AnnotatedRegion<SystemUiOverlayStyle>(
                  value: const SystemUiOverlayStyle(
                    statusBarColor: Colors.transparent,
                    statusBarIconBrightness: Brightness.dark,
                    statusBarBrightness: Brightness.light,
                    systemNavigationBarColor: Colors.white,
                    systemNavigationBarIconBrightness: Brightness.dark,
                  ),
                  child: ColoredBox(
                    color: Colors.white,
                    child: Center(
                      child: Semantics(
                        label: 'SnapExpense AI is starting',
                        image: true,
                        child: Transform.scale(
                          scale: 1 + lift,
                          child: SizedBox.square(
                            dimension: 104,
                            child: Stack(
                              children: [
                                const SnapExpenseMark(colored: false),
                                ClipPath(
                                  clipper: _ColorRevealClipper(reveal),
                                  child: const SnapExpenseMark(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Color grows from the receipt's center, with no abrupt asset swap.
class _ColorRevealClipper extends CustomClipper<Path> {
  const _ColorRevealClipper(this.progress);
  final double progress;
  @override
  Path getClip(Size size) => Path()
    ..addOval(
      Rect.fromCircle(
        center: size.center(Offset.zero),
        radius: size.longestSide * .72 * progress,
      ),
    );
  @override
  bool shouldReclip(covariant _ColorRevealClipper oldClipper) =>
      oldClipper.progress != progress;
}
