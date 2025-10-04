import Flutter
import UIKit
import GoogleMaps
import Foundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Get Google Maps API Key from Info.plist
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsApiKey") as? String, !apiKey.isEmpty, !apiKey.contains("$(") {
      GMSServices.provideAPIKey(apiKey)
    } else {
      // Fallback: log a warning to help diagnose missing/incorrect configuration
      NSLog("[Plendy] Google Maps API key is missing or not resolved. Ensure MAPS_API_KEY is set and Info.plist contains key 'GoogleMapsApiKey'.")
    }
    GeneratedPluginRegistrant.register(with: self)

    // Bridge to read shared data from App Group if the plugin doesn't deliver it
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "plendy.share/channel", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, result in
        guard let _ = self else { return }

        // Determine App Group ID similar to plugin logic
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
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // MARK: - Universal Links Handler (Required by Apple's Best Practices)
  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    // Log Universal Link for debugging
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb {
      if let url = userActivity.webpageURL {
        NSLog("[Plendy] Universal Link received: \(url.absoluteString)")
        
        // Validate that this is a link for our domain
        if url.host == "plendy.app" || url.host == "www.plendy.app" {
          NSLog("[Plendy] Valid Universal Link domain")
          
          // Check if this is a shared link
          let path = url.path
          if path.hasPrefix("/shared/") || path.hasPrefix("/shared-category/") {
            NSLog("[Plendy] Shared content Universal Link detected - will handle manually")
            
            // Manually post the URL to Flutter via method channel
            // We do NOT call super.application because that triggers Safari to open
            if let controller = window?.rootViewController as? FlutterViewController {
              let channel = FlutterMethodChannel(name: "deep_link_channel", binaryMessenger: controller.binaryMessenger)
              NSLog("[Plendy] Posting URL to Flutter via channel: \(url.absoluteString)")
              channel.invokeMethod("onDeepLink", arguments: url.absoluteString)
            }
            
            // Return true to tell iOS we handled it (prevents Safari from opening)
            return true
          }
        } else {
          NSLog("[Plendy] Universal Link domain mismatch: \(url.host ?? "nil")")
        }
      }
    }
    
    // For non-shared links, let Flutter handle normally
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }
}
