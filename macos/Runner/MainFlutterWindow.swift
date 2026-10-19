import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // The macOS look draws its own unified toolbar and sidebar up to the top
    // edge; the system keeps only its traffic lights, over the sidebar header
    // (lib/features/shell/mac/mac_window_frame.dart leaves room for them).
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.minSize = NSSize(width: 800, height: 600)

    super.awakeFromNib()
  }
}
