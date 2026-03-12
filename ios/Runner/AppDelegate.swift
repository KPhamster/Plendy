import Flutter
import UIKit
import GoogleMaps
import Foundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsApiKey") as? String, !apiKey.isEmpty, !apiKey.contains("$(") {
      GMSServices.provideAPIKey(apiKey)
    } else {
      NSLog("[Plendy] Google Maps API key is missing or not resolved. Ensure MAPS_API_KEY is set and Info.plist contains key 'GoogleMapsApiKey'.")
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()

    let channel = FlutterMethodChannel(name: "plendy.share/channel", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let appGroupId = Bundle.main.object(forInfoDictionaryKey: "AppGroupId") as? String
      let defaultGroupId = "group.\(Bundle.main.bundleIdentifier ?? "")"
      let suiteId = (appGroupId?.isEmpty == false) ? appGroupId! : defaultGroupId
      let userDefaults = UserDefaults(suiteName: suiteId)

      switch call.method {
      case "getInitialSharedMedia":
        let jsonData = userDefaults?.data(forKey: "ShareKey")
        let message = userDefaults?.string(forKey: "ShareMessageKey")
        let jsonString = jsonData.flatMap { String(data: $0, encoding: .utf8) }
        result(["json": jsonString as Any, "message": message as Any])

      case "resetSharedMedia":
        userDefaults?.removeObject(forKey: "ShareKey")
        userDefaults?.removeObject(forKey: "ShareMessageKey")
        userDefaults?.synchronize()
        result(true)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let screenshotChannel = FlutterMethodChannel(name: "com.plendy.app/screenshot", binaryMessenger: messenger)
    screenshotChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "captureScreen":
        AppDelegate.captureScreen(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Screenshot Capture
  private static func captureScreen(result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      guard let window = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .flatMap({ $0.windows })
        .first(where: { $0.isKeyWindow }) else {
        result(FlutterError(code: "CAPTURE_ERROR", message: "Window not available", details: nil))
        return
      }

      let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
      let image = renderer.image { context in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
      }

      if let pngData = image.pngData() {
        result(FlutterStandardTypedData(bytes: pngData))
      } else {
        result(FlutterError(code: "CAPTURE_ERROR", message: "Failed to convert image to PNG", details: nil))
      }
    }
  }
}

// MARK: - Scene Delegate (UIScene lifecycle)
class SceneDelegate: FlutterSceneDelegate {

  override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
       let url = userActivity.webpageURL {
      NSLog("[Plendy] Universal Link received: \(url.absoluteString)")

      if url.host == "plendy.app" || url.host == "www.plendy.app" {
        NSLog("[Plendy] Valid Universal Link domain")

        let path = url.path
        if path.hasPrefix("/shared/") || path.hasPrefix("/shared-category/") {
          NSLog("[Plendy] Shared content Universal Link detected - will handle manually")

          if let controller = window?.rootViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(name: "deep_link_channel", binaryMessenger: controller.binaryMessenger)
            NSLog("[Plendy] Posting URL to Flutter via channel: \(url.absoluteString)")
            channel.invokeMethod("onDeepLink", arguments: url.absoluteString)
          }
          return
        }
      } else {
        NSLog("[Plendy] Universal Link domain mismatch: \(url.host ?? "nil")")
      }
    }

    super.scene(scene, continue: userActivity)
  }
}
