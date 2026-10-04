import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

class MainFlutterWindow: NSWindow {
  private var logSaveChannel: FlutterMethodChannel?
  private var logSavePanel: NSSavePanel?
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
    registerLogSavePanel(flutterViewController)

    super.awakeFromNib()
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
