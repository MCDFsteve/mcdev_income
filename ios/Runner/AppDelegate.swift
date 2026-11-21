import Flutter
import Security
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let secureService = "com.aimessoft.consmelt.session"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registerSecureStorageChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func registerSecureStorageChannel() {
    guard let registrar = self.registrar(forPlugin: "SecureStoragePlugin") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "mcdev_income/secure_storage",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "AppDelegate 已释放", details: nil))
        return
      }
      guard let args = call.arguments as? [String: Any],
            let key = args["key"] as? String, !key.isEmpty else {
        result(FlutterError(code: "invalid_args", message: "缺少安全存储键名", details: nil))
        return
      }
      switch call.method {
      case "read":
        self.readSecret(account: key, result: result)
      case "write":
        guard let value = args["value"] as? String else {
          result(FlutterError(code: "invalid_args", message: "缺少安全存储内容", details: nil))
          return
        }
        self.writeSecret(account: key, value: value, result: result)
      case "delete":
        self.deleteSecret(account: key, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func readSecret(account: String, result: FlutterResult) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: secureService,
      kSecAttrAccount as String: account,
      kSecReturnData as String: kCFBooleanTrue as Any,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound {
      result(nil)
      return
    }
    guard status == errSecSuccess, let data = item as? Data else {
      result(FlutterError(code: "keychain_read_failed", message: "OSStatus=\(status)", details: nil))
      return
    }
    result(String(data: data, encoding: .utf8))
  }

  private func writeSecret(account: String, value: String, result: FlutterResult) {
    guard let data = value.data(using: .utf8) else {
      result(FlutterError(code: "encoding_error", message: "UTF-8 编码失败", details: nil))
      return
    }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: secureService,
      kSecAttrAccount as String: account,
    ]
    let update: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
    if status == errSecItemNotFound {
      var add = query
      add[kSecValueData as String] = data
      add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      status = SecItemAdd(add as CFDictionary, nil)
    }
    if status == errSecSuccess {
      result(nil)
    } else {
      result(FlutterError(code: "keychain_write_failed", message: "OSStatus=\(status)", details: nil))
    }
  }

  private func deleteSecret(account: String, result: FlutterResult) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: secureService,
      kSecAttrAccount as String: account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    if status == errSecSuccess || status == errSecItemNotFound {
      result(nil)
    } else {
      result(FlutterError(code: "keychain_delete_failed", message: "OSStatus=\(status)", details: nil))
    }
  }
}
