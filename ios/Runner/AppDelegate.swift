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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FashionStorePayments") {
      let channel = FlutterMethodChannel(name: "fashionstore/payments", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "openUrl" else { result(FlutterMethodNotImplemented); return }
        guard let value = call.arguments as? String, let url = URL(string: value), url.scheme == "https", url.host != nil else {
          result(FlutterError(code: "INVALID_URL", message: "Se requiere HTTPS", details: nil)); return
        }
        UIApplication.shared.open(url, options: [:]) { success in
          result(success ? nil : FlutterError(code: "OPEN_FAILED", message: "No se pudo abrir el navegador", details: nil))
        }
      }
    }
  }
}
