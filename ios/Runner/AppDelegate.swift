import Flutter
import UIKit
import GoogleMaps

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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
