import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PWViewerDeviceFixture") {
      let channel = FlutterMethodChannel(name: "dev.pocketworld.viewer.fixture", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        if call.method == "documents" {
          result(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.path)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
