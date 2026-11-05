import Cocoa

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = flutterViewController.view.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.title = "Anime TUI"
    self.isRestorable = false
    super.awakeFromNib()
  }
}
