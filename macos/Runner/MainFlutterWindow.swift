import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

private class WindowDragView: NSView {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 { window?.performZoom(nil) }
    else { window?.performDrag(with: event) }
  }
}

class MainFlutterWindow: NSWindow {
  private var logSaveChannel: FlutterMethodChannel?
  private var logSavePanel: NSSavePanel?
  private var chromeChannel: FlutterMethodChannel?
  private let chromeDragView = WindowDragView()
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
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    styleMask.insert(.fullSizeContentView)
    isMovableByWindowBackground = false
    if #available(macOS 11.0, *) { titlebarSeparatorStyle = .none }

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerLogSavePanel(flutterViewController)
    registerWindowChrome(flutterViewController)

    super.awakeFromNib()
  }

  private func registerWindowChrome(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(name: "mcdev_income/window_chrome",
                                       binaryMessenger: controller.engine.binaryMessenger)
    chromeChannel = channel
    controller.view.addSubview(chromeDragView)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let window = self else { result(nil); return }
      switch call.method {
      case "setDragRegion":
        if let rect = call.arguments as? [String: Double],
           let x = rect["x"], let y = rect["y"],
           let width = rect["width"], let height = rect["height"] {
          let view = controller.view
          window.chromeDragView.frame = NSRect(x: x, y: view.isFlipped ? y : view.bounds.height - y - height,
                                               width: width, height: height)
        }
      case "minimize": window.performMiniaturize(nil)
      case "zoom": window.performZoom(nil)
      case "fullscreen": window.toggleFullScreen(nil)
      case "close": window.performClose(nil)
      default: result(FlutterMethodNotImplemented); return
      }
      result(nil)
    }
  }

  private func registerLogSavePanel(_ controller: FlutterViewController) {
    let registrar = controller.registrar(forPlugin: "DevelopmentLogSavePanel")
    let channel = FlutterMethodChannel(name: "mcdev_income/development_logs",
                                       binaryMessenger: registrar.messenger)
    logSaveChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "chooseLogExport" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let window = self else {
        result(FlutterError(code: "no_window", message: "日志窗口已关闭。", details: nil))
        return
      }
      guard window.logSavePanel == nil else {
        result(FlutterError(code: "save_in_progress", message: "请先完成当前导出。", details: nil))
        return
      }
      guard let args = call.arguments as? [String: Any],
            let fileName = args["fileName"] as? String, !fileName.isEmpty else {
        result(FlutterError(code: "invalid_filename", message: "日志文件名无效。", details: nil))
        return
      }
      let panel = NSSavePanel()
      window.logSavePanel = panel
      panel.title = (args["filtered"] as? Bool == true) ? "导出筛选结果" : "导出原始日志"
      panel.nameFieldStringValue = (fileName as NSString).lastPathComponent
      panel.canCreateDirectories = true
      panel.allowsOtherFileTypes = false
      if #available(macOS 11.0, *) {
        panel.allowedContentTypes = [UTType(filenameExtension: "log", conformingTo: .plainText)
                                    ?? .plainText, .plainText]
      } else {
        panel.allowedFileTypes = ["log", "txt"]
      }
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      panel.beginSheetModal(for: window) { [weak window] response in
        window?.logSavePanel = nil
        result(response == .OK ? panel.url?.path : nil)
      }
    }
  }

  override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    if isHeadless && place != .out { return }
    super.order(place, relativeTo: otherWin)
  }
}
