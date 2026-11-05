import Flutter
import Cocoa

@main
class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: NSApplication,
    didFinishLaunching withLaunchOptions: [NSApplication.AttributeKey: Any]?
  ) -> Bool {
    let window = NSApplication.shared.windows.first
    window?.center()
    return super.application(application, didFinishLaunchingWithOptions: withLaunchOptions)
  }
}
