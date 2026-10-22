# Ask Snap glass controls

## Renderer decision

The project uses Flutter 3.44.2. The current `liquid_glass_renderer` 1.0 prerelease
requires Flutter 3.47+ with Impeller and Flutter GPU. Its API uses a shared
`LiquidGlassLayer`, individual `LiquidGlass` shapes, blend groups and a `FakeGlass`
fallback. The older 0.2 prerelease has a different API and documented experimental
Impeller-only and animated-geometry limitations.

An SDK/GPU migration is outside this UI change. This implementation therefore uses
the requested hand-built alternative on all platforms: tightly clipped grouped
BackdropFilters, translucent tint, specular strokes, layered rim highlights and
soft shadows. **The rim suggests lensing; it does not refract background pixels.**
No shader, GPU feature flags, pubspec changes or package dependencies were added.

Package sources checked:
- https://pub.dev/packages/liquid_glass_renderer
- https://pub.dev/packages/liquid_glass_renderer/versions/0.2.0-dev.4

## Initial findings and architecture choice

- High: the current package release cannot run on this installed Flutter SDK
  without an SDK/GPU migration; older prereleases carry renderer limitations.
- Medium: camera controls were embedded in the scanner’s scrolling content;
  fixed overlay groups are needed to meet the no-blur-in-scrolling-lists rule.
- Medium: iOS Reduce Transparency was not exposed to Flutter. A small, observed
  platform bridge is required; high contrast and motion already have Flutter APIs.

Kept the existing folder layout, state controllers, Supabase session handling and
navigation. Extracted only the optical component, accessibility scope and scanner
control presentation. No business rules, AI requests or expense data contracts
changed.

## Components and scope

- `frontend/lib/widgets/glass_container.dart`: reusable `GlassContainer(blur,
  tint, borderRadius, interactive, child)` plus optional `onTap`. Interactive
  decoration observes pointer events without replacing child buttons’ semantics.
- `GlassGroup`: RepaintBoundary + stable BackdropGroup key. Adjacent, disjoint
  surfaces use grouped filters; the engine can share their blur pass. Overlapping
  child surfaces use `blur: 0` to avoid sampling twice or sharing an invalid key.
- `frontend/lib/theme/glass_theme.dart`: tunable light/dark ThemeExtension.
  `snapExpenseTheme(brightness: ...)` chooses the corresponding preset. The app’s
  established light appearance is retained; camera controls use dark glass and
  the Ask Snap composer uses the same dark finish via `GlassTheme.darkPanel`. This change does not claim a complete dark-mode redesign of every screen.
- `frontend/lib/widgets/glass_accessibility.dart` and `ios/Runner/AppDelegate.swift`:
  iOS Reduce Transparency method channel, native change notifications and refresh
  on resume. Unknown/missing iOS channel fails closed to an opaque surface.
- Ask Snap remains the expense conversation. Its clear/back controls and fixed
  composer use glass. Suggestions sit within the composer’s single blurred shell;
  individual scrolling chips use zero additional blur. Long answers remain opaque.
- Receipt Scanner owns the camera/captured image. Its fixed top and bottom overlay
  groups apply glass to flash, capture, gallery, close and review actions. The image
  itself is neither blurred nor tinted. Capture, upload, retake and review logic
  remains unchanged. Controls are separated in `scanner_glass_controls.dart`.

There are no BackdropFilters inside scrolling lists. Camera error text may scroll
within the preview, but it contains no glass filters. Captured-image review actions
are the glass overlay/result surface; no new bottom sheet or new AI behavior was
introduced.

## Tunable values

| Setting | Default | Location |
| --- | --- | --- |
| Blur sigma | 24 logical pixels | `GlassTheme.blur` or per-container `blur` |
| White tint | `0x1FFFFFFF`, approximately 12% | `GlassTheme.tint` |
| Specular border opacity | 0.72 at top-left, fades diagonally | `GlassTheme.borderOpacity` |
| Border width | 1 logical pixel | `_SpecularBorder` |
| Press scale | 1.05 | `GlassTheme.pressScale` |
| Press/shape duration | 250 ms | `GlassTheme.duration` |
| Drop shadow | black 12%, blur 16, offset (0, 5) | `GlassContainer` |
| Composer radius | 30 resting / 24 focused | Ask Snap composer |
| Input radius | 20 resting / 16 focused | outer radius minus shell padding |
| Text scrim | near-white in light; near-black in dark | `GlassTheme.textScrim` |
| Opaque accessibility surface | light/dark solid preset | `GlassTheme.solidColor` |

Presses use a slight easeOutBack overshoot and light haptic feedback. This is an
implicit 250 ms spring-like animation, not a physical SpringSimulation. The
composer uses AnimatedSize, AnimatedContainer and an animated clipping radius;
suggestions collapse while the keyboard is open to preserve room on small phones.

High contrast, Disable Animations/Reduce Motion, or iOS Reduce Transparency removes
blur and translucent surface gradients and uses solid color. Reduced motion uses
zero-duration material/shape transitions. Long text stays on opaque cards. Camera
control labels/icons and composer text use scrims; unit tests verify at least
4.5:1 contrast for the configured foreground/scrim pairs over black and white.

## Validation and performance limits

Baseline before this change: analysis clean, 49 Flutter tests passed.
Executed successfully:

- `dart format --output=none --set-exit-if-changed lib test integration_test/glass_native_test.dart tool/glass_profile_main.dart tool/render_glass_receipt_preview_test.dart tool/render_ask_snap_preview_test.dart`: 63 files checked, zero changes required.
- `flutter build apk --debug --dart-define-from-file=config/local.json`: passed.
  Existing `camera_android_camerax` future Kotlin compatibility warning is nonfatal.
- `flutter run -d 383EA713-08E5-4ABA-A078-A8AA64AA5E15 --dart-define-from-file=config/local.json`: final configured app rebuilt and launched; Supabase initialized. Debugger detached, leaving the app running.
- `flutter analyze`: no issues.
- `flutter test --concurrency=1`: **55 tests passed** (49 baseline + six glass tests).
  Covers shared native backdrop keys, opaque accessibility modes, press/haptic
  feedback, live iOS preference changes, contrast, large text/keyboard layout and
  all existing chat, receipt, auth and data flows.
- `flutter test integration_test/glass_native_test.dart integration_test/scanner_test.dart -d 383EA713-08E5-4ABA-A078-A8AA64AA5E15 --concurrency=1`:
  **two iOS simulator tests passed**, including compilation of the new Swift
  channel and its real bool response. Flutter ignores concurrency for integration
  tests; the files ran in sequence. Camera fallback/reopen/navigation passed.
- `flutter test tool/render_glass_receipt_preview_test.dart tool/render_ask_snap_preview_test.dart --concurrency=1`:
  **two preview tests passed**. Captured-image and chat previews inspected with
  real blurred shadows enabled; the receipt fixture is synthetic and local.

No physical-device performance result is implied by these tests.

Only an iPhone 15 Pro Max **simulator** (iOS 17.4), macOS and Chrome were available.
No physical iPhone was connected. **60fps and real-camera blur performance are
unverified**; simulator correctness/rendering is not a substitute for profiling.

On a connected physical iPhone:

```sh
cd frontend
flutter run --profile -t tool/glass_profile_main.dart -d <physical-iphone-id>
```

The `PROFILE FIXTURE` entry point uses synthetic local HTTP responses, enables
Ask Snap input, and makes no network, Supabase or paid AI calls. It uses the actual
camera on hardware; server-backed receipt operations are deliberately disabled.
For profiling the real signed-in app instead, omit `-t` and pass your HTTPS backend
configuration (profile/release rejects development HTTP URLs). Open Receipt Scanner and
Ask Snap; test camera motion, flash, repeated capture/retake, long chat scrolling,
chip swipes, keyboard opening/closing, rotation and large text. Record the DevTools
Performance timeline and memory/power behavior; aim for UI/raster frames under
16.7 ms for a 60Hz budget. Check Reduce Transparency live in iOS Accessibility and
Reduce Motion/high contrast. Do not accept this effect for release solely on the
basis of the simulator build. On slower devices, use solid glass or lower sigma.
