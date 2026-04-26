import Flutter
import Photos
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
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GallerySaverPlugin")
    let channel = FlutterMethodChannel(
      name: "camera_assistant/gallery_saver",
      binaryMessenger: registrar.messenger()
    )
    let saver = GallerySaver()
    channel.setMethodCallHandler { call, result in
      if call.method == "saveImage" {
        saver.saveImage(arguments: call.arguments, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

final class GallerySaver: NSObject {
  private var pendingResult: FlutterResult?

  func saveImage(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let data = args["bytes"] as? FlutterStandardTypedData,
      !data.data.isEmpty
    else {
      result(FlutterError(code: "invalid_bytes", message: "Image bytes are empty.", details: nil))
      return
    }

    let fileName = (args["fileName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
      ?? "cloud_shadow_capture.jpg"
    let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

    do {
      try data.data.write(to: tempUrl, options: .atomic)
    } catch {
      result(FlutterError(code: "write_failed", message: error.localizedDescription, details: nil))
      return
    }

    requestPhotoAddAuthorization { authorized in
      guard authorized else {
        DispatchQueue.main.async {
          result(FlutterError(code: "permission_denied", message: "No permission to add photos.", details: nil))
        }
        return
      }

      self.writePhoto(tempUrl: tempUrl, result: result)
    }
  }

  private func requestPhotoAddAuthorization(_ completion: @escaping (Bool) -> Void) {
    if #available(iOS 14, *) {
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        completion(status == .authorized || status == .limited)
      }
    } else {
      PHPhotoLibrary.requestAuthorization { status in
        completion(status == .authorized)
      }
    }
  }

  private func writePhoto(tempUrl: URL, result: @escaping FlutterResult) {
    PHPhotoLibrary.shared().performChanges({
      PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: tempUrl)
    }, completionHandler: { success, error in
      DispatchQueue.main.async {
        try? FileManager.default.removeItem(at: tempUrl)
        if success {
          result(tempUrl.lastPathComponent)
        } else {
          result(FlutterError(code: "save_failed", message: error?.localizedDescription ?? "Save image failed.", details: nil))
        }
      }
    })
  }
}
