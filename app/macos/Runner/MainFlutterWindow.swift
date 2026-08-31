import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // Hide AppKit's auto-inserted "Show Tab Bar" / "Show All Tabs" items
    // (this window opts out of automatic window tabbing).
    NSWindow.allowsAutomaticWindowTabbing = false

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
