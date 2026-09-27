import Cocoa
import FlutterMacOS
import Darwin

@main
class AppDelegate: FlutterAppDelegate {
  private var headlessEngine: FlutterEngine?

  private var isHeadless: Bool {
    ProcessInfo.processInfo.arguments.dropFirst().first == "--headless"
  }

  override func applicationWillFinishLaunching(_ notification: Notification) {
    if isHeadless {
      NSApp.setActivationPolicy(.prohibited)
    }
    super.applicationWillFinishLaunching(notification)
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    guard isHeadless else {
      return
    }

    let project = FlutterDartProject()
    project.dartEntrypointArguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
    let engine = FlutterEngine(name: "mcdev-headless", project: project,
                               allowHeadlessExecution: true)
    headlessEngine = engine
    if !engine.run(withEntrypoint: nil) {
      fputs("Unable to start the headless Flutter engine\n", stderr)
      exit(1)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
