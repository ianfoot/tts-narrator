import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Spec min window size (see AppMetrics) enforced in AppKit units.
  static let minContentSize = NSSize(width: 900, height: 600)

  /// Spec default window size (see AppMetrics).
  static let defaultContentSize = NSSize(width: 1100, height: 750)

  override func awakeFromNib() {
    // Hide AppKit's auto-inserted "Show Tab Bar" / "Show All Tabs" items
    // (this window opts out of automatic window tabbing).
    NSWindow.allowsAutomaticWindowTabbing = false

    // Enforce the spec's minimum window size so the fixed 44px toolbar,
    // the settings rail, and the status bar never get clipped off.
    contentMinSize = Self.minContentSize

    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Open at the spec default size, centered on the main screen.
    let frame = NSRect(
      origin: NSZeroPoint,
      size: Self.defaultContentSize
    )
    let screen = NSScreen.main?.visibleFrame
    let origin = CGPoint(
      x: screen.map { $0.midX - frame.width / 2 } ?? 0,
      y: screen.map { $0.midY - frame.height / 2 } ?? 0
    )
    self.setFrame(NSRect(origin: origin, size: frame.size), display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}