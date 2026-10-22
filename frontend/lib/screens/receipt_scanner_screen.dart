import '../widgets/glass_container.dart';
import '../widgets/scanner_glass_controls.dart';
import '../state/expense_store.dart';
import 'receipt_extraction_screen.dart';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/receipt_selection.dart';
import 'receipt_review_screen.dart';

const _lime = Color(0xFFDDEEBA);

class ReceiptScannerScreen extends StatefulWidget {
  const ReceiptScannerScreen({super.key, this.onReceiptReady});
  final ValueChanged<ReceiptSelection>? onReceiptReady;

  @override
  State<ReceiptScannerScreen> createState() => _ReceiptScannerScreenState();
}

class _ReceiptScannerScreenState extends State<ReceiptScannerScreen>
    with WidgetsBindingObserver {
  final _picker = ImagePicker();
  CameraController? _camera;
  ReceiptSelection? _receipt;
  String? _cameraError;
  bool _loading = true;
  bool _busy = false;
  bool _picking = false;
  bool _active = true;
  bool _flash = false;
  bool _flashSupported = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    // Android may destroy the activity while the system photo picker is open.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final result = await _picker.retrieveLostData();
        if (!mounted) return;
        if (result.files?.isNotEmpty == true) {
          await _select(result.files!.first);
        } else if (result.exception != null) {
          _message(
            'Your previous image could not be restored. Please choose it again.',
          );
        }
      } catch (_) {
        if (mounted) _message('Please choose your receipt again.');
      }
    }
    if (mounted && _receipt == null) await _initializeCamera();
  }

  Future<void> _releaseCamera() async {
    _generation++;
    final controller = _camera;
    _camera = null;
    _flash = false;
    _flashSupported = false;
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {
        /* Already disconnected. */
      }
    }
  }

  Future<void> _initializeCamera() async {
    await _releaseCamera();
    if (!mounted || !_active || _picking || _receipt != null) return;
    final generation = _generation;
    setState(() {
      _loading = true;
      _cameraError = null;
    });
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('Unavailable', 'No camera found');
      }
      if (!mounted || generation != _generation) return;
      final back = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      controller = CameraController(
        back.isNotEmpty ? back.first : cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      var supportsFlash = false;
      if (!kIsWeb) {
        try {
          await controller.setFlashMode(FlashMode.off);
          supportsFlash = true;
        } on CameraException {
          supportsFlash = false;
        }
      }
      if (!mounted || generation != _generation || !_active) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _loading = false;
        _flashSupported = supportsFlash;
      });
    } catch (error) {
      if (controller != null) {
        try {
          await controller.dispose();
        } catch (_) {}
      }
      if (!mounted || generation != _generation) return;
      final code = error is CameraException ? error.code : '';
      final denied =
          code.contains('AccessDenied') || code.contains('Restricted');
      setState(() {
        _loading = false;
        _cameraError = denied
            ? 'Camera access is off. Allow camera access in your device settings, then try again. You can also upload a receipt.'
            : 'Your camera is unavailable right now. Try again or upload a receipt from your gallery.';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (!_active) {
      unawaited(_releaseCamera());
      if (mounted) setState(() => _loading = true);
    } else if (!_picking && _receipt == null) {
      unawaited(_initializeCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_releaseCamera());
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _select(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      // Validate that the file can actually be displayed before accepting it.
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1600);
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      codec.dispose();
      if (!mounted) return;
      await _releaseCamera();
      if (mounted) {
        setState(() {
          _receipt = ReceiptSelection(file: file, bytes: bytes);
          _loading = false;
        });
      }
    } catch (_) {
      _message(
        'This image could not be opened. Please choose a readable JPEG or PNG receipt.',
      );
    }
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (_busy || camera == null || !camera.value.isInitialized) return;
    setState(() => _busy = true);
    try {
      final file = await camera.takePicture();
      if (mounted) await _select(file);
    } catch (_) {
      _message('We couldn’t capture that receipt. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _picking = true;
    });
    await _releaseCamera();
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (mounted && file != null) await _select(file);
    } on PlatformException {
      _message(
        'Your photo library could not be opened. Check photo permissions in device settings and try again.',
      );
    } catch (_) {
      _message('We couldn’t access that image. Please try another receipt.');
    } finally {
      _picking = false;
      if (mounted) {
        setState(() => _busy = false);
        if (_receipt == null && _active) await _initializeCamera();
      }
    }
  }

  Future<void> _toggleFlash() async {
    if (_busy || _camera == null) return;
    final camera = _camera!;
    setState(() => _busy = true);
    try {
      await camera.setFlashMode(_flash ? FlashMode.off : FlashMode.torch);
      if (mounted && camera == _camera) setState(() => _flash = !_flash);
    } catch (_) {
      if (mounted) {
        setState(() {
          _flashSupported = false;
          _flash = false;
        });
      }
      _message('Flash is not available on this camera.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continue() async {
    final receipt = _receipt;
    if (receipt == null || _busy) return;
    widget.onReceiptReady?.call(receipt);
    setState(() => _busy = true);
    final result = await Navigator.of(context).push<ReceiptReviewResult>(
      MaterialPageRoute(
        builder: (_) => ExpenseScope.of(context).api == null
            ? ReceiptReviewScreen(receipt: receipt)
            : ReceiptExtractionScreen(
                receipt: receipt,
                api: ExpenseScope.of(context).api!,
              ),
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case ReceiptReviewResult.saved:
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                ExpenseScope.of(context).connected
                    ? 'Expense saved successfully.'
                    : 'Expense saved for this session. It will reset when the app restarts.',
              ),
            ),
          );
      case ReceiptReviewResult.retake:
        setState(() => _receipt = null);
        await _initializeCamera();
      case ReceiptReviewResult.gallery:
        await _pick();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reviewing = _receipt != null;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        leading: Padding(
          padding: const EdgeInsets.all(5),
          child: GlassGroup(
            child: GlassContainer(
              interactive: true,
              borderRadius: 24,
              child: IconButton(
                tooltip: 'Back to Dashboard',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
          ),
        ),
        title: const Text(
          'Scan Receipt',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 530;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 568),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        compact ? 4 : 12,
                        24,
                        compact ? 8 : 18,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!compact)
                            Text(
                              reviewing
                                  ? 'Looking good?'
                                  : 'Every receipt.\nA little more clarity.',
                              style: const TextStyle(
                                fontSize: 28,
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -1,
                              ),
                            ),
                          if (!compact) const SizedBox(height: 10),
                          Text(
                            reviewing
                                ? 'Make sure the details are clear and the entire receipt is visible.'
                                : 'Capture your receipt and let AI handle the rest.',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF777C73),
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ColoredBox(
                                color: const Color(0xFF242A25),
                                child: AnimatedSwitcher(
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : const Duration(milliseconds: 180),
                                  child: reviewing
                                      ? _receiptPreview()
                                      : _cameraView(),
                                ),
                              ),
                              ScannerGlassControls(
                                reviewing: reviewing,
                                busy: _busy,
                                cameraReady: _cameraError == null && !_loading,
                                flashSupported: _flashSupported,
                                flash: _flash,
                                onFlash: _toggleFlash,
                                onGallery: _pick,
                                onCapture: _capture,
                                onClose: () => Navigator.of(context).pop(),
                                onContinue: _continue,
                                onRetake: () {
                                  setState(() => _receipt = null);
                                  _initializeCamera();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        compact ? 8 : 14,
                        24,
                        12,
                      ),
                      child: Column(
                        children: [
                          if (!compact)
                            _Tip(
                              icon: reviewing
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.wb_sunny_outlined,
                              text: reviewing
                                  ? 'Ready when you are. Review before continuing.'
                                  : 'Good light. Flat receipt. All the details in frame.',
                            ),
                          if (!reviewing) ...[
                            if (!compact) const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _busy ? null : _pick,
                              icon: const Icon(
                                Icons.photo_library_outlined,
                                size: 20,
                              ),
                              label: const Text('Upload from Gallery'),
                            ),
                            const Text(
                              'JPEG & PNG supported',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF777C73),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _receiptPreview() => Padding(
    key: const ValueKey('receipt-preview'),
    padding: const EdgeInsets.all(16),
    child: Semantics(
      label: 'Selected receipt image',
      image: true,
      child: Image.memory(
        _receipt!.bytes,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: 1600,
        errorBuilder: (_, _, _) => const Center(
          child: Text(
            'Image unavailable. Please choose another.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ),
    ),
  );

  Widget _cameraView() {
    final camera = _camera;
    return Stack(
      key: const ValueKey('camera-view'),
      fit: StackFit.expand,
      children: [
        if (camera != null && camera.value.isInitialized)
          Center(
            child: AspectRatio(
              aspectRatio: 1 / camera.value.aspectRatio,
              child: CameraPreview(camera),
            ),
          ),
        if (_cameraError == null && !_loading)
          const CustomPaint(painter: _ScannerGuide()),
        if (_loading)
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: _lime),
                SizedBox(height: 16),
                Text(
                  'Opening camera…',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        if (_cameraError != null)
          Padding(
            padding: const EdgeInsets.only(top: 55, bottom: 105),
            child: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.no_photography_outlined,
                        size: 36,
                        color: _lime,
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Let’s get your receipt',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _cameraError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextButton(
                        onPressed: _busy ? null : _initializeCamera,
                        style: TextButton.styleFrom(foregroundColor: _lime),
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _lime.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      children: [
        Icon(icon, size: 19, color: const Color(0xFF526840)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF526840),
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ScannerGuide extends CustomPainter {
  const _ScannerGuide();
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      size.width * .14,
      size.height * .17,
      size.width * .86,
      size.height * .70,
    );
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(14)));
    canvas.drawPath(
      outside,
      Paint()..color = Colors.black.withValues(alpha: .46),
    );
    final paint = Paint()
      ..color = _lime
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const length = 23.0;
    for (final corner in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      final dx = corner.dx == rect.left ? 1 : -1;
      final dy = corner.dy == rect.top ? 1 : -1;
      canvas.drawPath(
        Path()
          ..moveTo(corner.dx, corner.dy + dy * length)
          ..lineTo(corner.dx, corner.dy + dy * 8)
          ..quadraticBezierTo(
            corner.dx,
            corner.dy,
            corner.dx + dx * 8,
            corner.dy,
          )
          ..lineTo(corner.dx + dx * length, corner.dy),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScannerGuide oldDelegate) => false;
}
