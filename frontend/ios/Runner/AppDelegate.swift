import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var accessibilityChannel: FlutterMethodChannel?
  private var transparencyObserver: NSObjectProtocol?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SnapGlassAccessibility") {
      let channel = FlutterMethodChannel(name: "snapexpense/accessibility", binaryMessenger: registrar.messenger())
      accessibilityChannel = channel
      channel.setMethodCallHandler { call, result in
        if call.method == "isReduceTransparencyEnabled" {
          result(UIAccessibility.isReduceTransparencyEnabled)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      if let observer = transparencyObserver { NotificationCenter.default.removeObserver(observer) }
      transparencyObserver = NotificationCenter.default.addObserver(
        forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
        object: nil, queue: .main
      ) { [weak self] _ in
        self?.accessibilityChannel?.invokeMethod("reduceTransparencyChanged", arguments: UIAccessibility.isReduceTransparencyEnabled)
      }
    }
  }
  deinit {
    if let observer = transparencyObserver { NotificationCenter.default.removeObserver(observer) }
  }
}
