import 'dart:math' as math;
import 'package:flutter/cupertino.dart'
    show CupertinoSliverRefreshControl, RefreshIndicatorMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A native spring-driven pull reveal. The artwork extends underneath the
/// rounded content edge so the two surfaces remain continuous while dragging.
class ArtworkRefreshScrollView extends StatefulWidget {
  const ArtworkRefreshScrollView({
    super.key,
    required this.child,
    required this.onRefresh,
  });
  final Widget child;
  final Future<void> Function() onRefresh;
  @override
  State<ArtworkRefreshScrollView> createState() =>
      _ArtworkRefreshScrollViewState();
}

class _ArtworkRefreshScrollViewState extends State<ArtworkRefreshScrollView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation;

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        precacheImage(
          const AssetImage('assets/images/blurry_background.png'),
          context,
        );
      }
    });
  }

  Future<void> _refresh() async {
    if (!MediaQuery.disableAnimationsOf(context)) _rotation.repeat();
    HapticFeedback.lightImpact();
    try {
      // Keep the gesture feedback legible even when the local refresh is instant.
      await Future.wait([
        widget.onRefresh(),
        Future<void>.delayed(const Duration(milliseconds: 650)),
      ]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn’t refresh right now. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) _rotation.stop();
    }
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomScrollView(
    key: const PageStorageKey('dashboard-scroll'),
    paintOrder: SliverPaintOrder.lastIsTop,
    physics: const BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    ),
    slivers: [
      CupertinoSliverRefreshControl(
        refreshTriggerPullDistance: 100,
        refreshIndicatorExtent: 78,
        onRefresh: _refresh,
        builder: (context, mode, extent, trigger, indicatorExtent) {
          if (extent <= 0) return const SizedBox.shrink();
          final progress = (extent / trigger).clamp(0.0, 1.0);
          final active = mode == RefreshIndicatorMode.refresh;
          final done = mode == RefreshIndicatorMode.done;
          final label = active
              ? 'Refreshing dashboard'
              : done
              ? 'Refresh complete'
              : progress >= 1
              ? 'Release to refresh'
              : 'Pull to refresh';
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: extent + 28,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  child: Image.asset(
                    'assets/images/blurry_background.png',
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: extent,
                child: Center(
                  child: Semantics(
                    label: label,
                    liveRegion: active || done,
                    child: ExcludeSemantics(
                      child: Opacity(
                        opacity: (extent / 45).clamp(0.0, 1.0),
                        child: AnimatedBuilder(
                          animation: _rotation,
                          builder: (context, _) => Transform.rotate(
                            angle: done
                                ? 0
                                : active
                                ? _rotation.value * 2 * math.pi
                                : progress * math.pi,
                            child: Icon(
                              done
                                  ? Icons.check_rounded
                                  : Icons.refresh_rounded,
                              size: 32,
                              color: const Color(0xFF20251F),
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
      ),
      SliverToBoxAdapter(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: widget.child,
        ),
      ),
    ],
  );
}
