import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var isHeadless: Bool {
    ProcessInfo.processInfo.arguments.dropFirst().first == "--headless"
  }

  override func awakeFromNib() {
    if isHeadless {
      super.awakeFromNib()
      return
    }

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    if isHeadless && place != .out { return }
    super.order(place, relativeTo: otherWin)
  }
}
