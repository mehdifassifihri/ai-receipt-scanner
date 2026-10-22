import 'package:flutter/material.dart';
import '../theme/glass_theme.dart';
import 'glass_container.dart';

/// Contrôles uniquement : aucune dépendance au plugin caméra ou au store.
/// Chaque bande partage un filtre ; l’image reste peinte séparément dessous.
class ScannerGlassControls extends StatelessWidget {
  const ScannerGlassControls({
    super.key,
    required this.reviewing,
    required this.busy,
    required this.cameraReady,
    required this.flashSupported,
    required this.flash,
    required this.onFlash,
    required this.onGallery,
    required this.onCapture,
    required this.onClose,
    required this.onContinue,
    required this.onRetake,
  });
  final bool reviewing, busy, cameraReady, flashSupported, flash;
  final VoidCallback onFlash,
      onGallery,
      onCapture,
      onClose,
      onContinue,
      onRetake;
  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(extensions: [GlassTheme.dark]),
    child: Stack(
      children: [
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: GlassGroup(
            child: Row(
              children: [
                GlassContainer(
                  borderRadius: 20,
                  child: _scrim(
                    radius: 20,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            color: Color(0xFFDDEEBA),
                            size: 14,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'RECEIPT',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                if (!reviewing && flashSupported)
                  GlassContainer(
                    borderRadius: 24,
                    interactive: !busy,
                    child: _scrim(
                      child: IconButton(
                        tooltip: flash ? 'Turn flash off' : 'Turn flash on',
                        onPressed: busy ? null : onFlash,
                        color: Colors.white,
                        icon: Icon(
                          flash
                              ? Icons.flash_on_rounded
                              : Icons.flash_off_rounded,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 14,
          left: 14,
          right: 14,
          child: GlassGroup(
            child: GlassContainer(
              borderRadius: 30,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: reviewing ? _reviewActions() : _captureActions(),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _reviewActions() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      GlassContainer(
        blur: 0,
        borderRadius: 22,
        interactive: !busy,
        child: _scrim(
          radius: 22,
          child: SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: busy ? null : onContinue,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Continue'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(13),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(
            child: _textAction('Retake', Icons.refresh_rounded, onRetake),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _textAction(
              'Choose another',
              Icons.photo_library_outlined,
              onGallery,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _captureActions() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      _iconAction(
        'Choose receipt from gallery',
        Icons.photo_library_outlined,
        busy ? null : onGallery,
      ),
      GlassContainer(
        blur: 0,
        borderRadius: 32,
        interactive: !busy && cameraReady,
        child: SizedBox.square(
          dimension: 64,
          child: FilledButton(
            onPressed: busy || !cameraReady ? null : onCapture,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDDEEBA),
              foregroundColor: const Color(0xFF20251F),
              disabledBackgroundColor: const Color(0xFF424A41),
              disabledForegroundColor: Colors.white70,
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
            ),
            child: Semantics(
              label: 'Capture receipt',
              child: busy
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.camera_alt_outlined, size: 27),
            ),
          ),
        ),
      ),
      _iconAction('Close scanner', Icons.close_rounded, onClose),
    ],
  );

  Widget _iconAction(String label, IconData icon, VoidCallback? action) =>
      GlassContainer(
        blur: 0,
        borderRadius: 24,
        interactive: action != null,
        child: _scrim(
          child: IconButton(
            tooltip: label,
            onPressed: action,
            color: Colors.white,
            icon: Icon(icon),
          ),
        ),
      );
  Widget _textAction(String label, IconData icon, VoidCallback action) =>
      GlassContainer(
        blur: 0,
        borderRadius: 24,
        interactive: !busy,
        child: _scrim(
          child: TextButton.icon(
            onPressed: busy ? null : action,
            icon: Icon(icon, size: 18),
            label: Text(label, style: const TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ),
      );
  // Blanc sur scrim sombre : contraste indépendant des pixels de la caméra.
  Widget _scrim({required Widget child, double radius = 24}) => DecoratedBox(
    decoration: BoxDecoration(
      color: GlassTheme.dark.textScrim,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: child,
  );
}
