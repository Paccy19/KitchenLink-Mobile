import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var documentController: UIDocumentInteractionController?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Opens a downloaded file (e.g. a vendor's PDF document) in a preview.
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KitchenLinkFiles") else { return }
    let channel = FlutterMethodChannel(name: "kitchenlink/files", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "open",
            let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      let controller = UIDocumentInteractionController(url: URL(fileURLWithPath: path))
      controller.delegate = self
      self?.documentController = controller
      if controller.presentPreview(animated: true) {
        result(true)
      } else {
        result(FlutterError(code: "NO_APP", message: "This file can't be previewed on this phone.", details: nil))
      }
    }
  }
}

extension AppDelegate: UIDocumentInteractionControllerDelegate {
  func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
    let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
    var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController ?? UIViewController()
    while let presented = top.presentedViewController { top = presented }
    return top
  }
}
