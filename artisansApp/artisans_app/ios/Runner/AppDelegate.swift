import Flutter
import UIKit
import GoogleMaps


@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // SECURITY: Load Google Maps API key from Info.plist (which reads from .env at build time)
    // Never hardcode API keys in source code.
    if let mapsKey = Bundle.main.object(forKey: "GOOGLE_MAPS_API_KEY") as? String, !mapsKey.isEmpty {
      GMSServices.provideAPIKey(mapsKey)
    } else {
      NSLog("FixIt App: GOOGLE_MAPS_API_KEY not found in Info.plist — map features will not work")
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
