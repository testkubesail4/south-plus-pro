import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var watchNotifications: WatchNotificationBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      watchNotifications = WatchNotificationBridge(messenger: controller.binaryMessenger)
    }
    return result
  }
}

private class WatchNotificationBridge: NSObject, UNUserNotificationCenterDelegate {
  private let channel: FlutterMethodChannel
  private let center = UNUserNotificationCenter.current()
  private var pendingTap: [String: String]?
  private let prefix = "south-plus-watch/"

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "south_plus_rewrite/watch_notifications", binaryMessenger: messenger)
    super.init()
    center.delegate = self
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "permission":
        self.center.getNotificationSettings { settings in
          DispatchQueue.main.async {
            result(settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
          }
        }
      case "requestPermission":
        self.center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
          DispatchQueue.main.async { result(granted) }
        }
      case "show":
        guard let args = call.arguments as? [String: Any],
              let owner = args["owner"] as? String, let event = args["eventId"] as? String,
              self.valid(owner), self.valid(event) else {
          result(FlutterError(code: "invalid_notification", message: "无效的关注动态", details: nil)); return
        }
        let content = UNMutableNotificationContent()
        // No forum title, author, body or account name is exposed on the lock screen.
        content.title = "南+"
        content.body = "你关注的内容有新动态，打开 App 查看"
        content.sound = .default
        content.userInfo = ["owner": owner, "eventId": event]
        let identity = Data(owner.utf8).base64EncodedString() + ":" + Data(event.utf8).base64EncodedString()
        let request = UNNotificationRequest(identifier: self.prefix + identity, content: content, trigger: nil)
        self.center.add(request) { error in
          DispatchQueue.main.async {
            if error != nil {
              result(FlutterError(code: "notification_failed", message: "系统通知不可用", details: nil))
            } else { result(nil) }
          }
        }
      case "cancelAll":
        self.pendingTap = nil
        let cancellation = DispatchGroup()
        cancellation.enter()
        self.center.getDeliveredNotifications { delivered in
          self.center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter { $0.hasPrefix(self.prefix) })
          cancellation.leave()
        }
        cancellation.enter()
        self.center.getPendingNotificationRequests { pending in
          self.center.removePendingNotificationRequests(withIdentifiers: pending.map { $0.identifier }.filter { $0.hasPrefix(self.prefix) })
          cancellation.leave()
        }
        cancellation.notify(queue: .main) { result(nil) }
      case "takeTap":
        result(self.pendingTap)
        self.pendingTap = nil
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func valid(_ value: String) -> Bool {
    return !value.isEmpty && value.count <= 1024 && value.unicodeScalars.allSatisfy {
      !CharacterSet.controlCharacters.contains($0) && $0.properties.generalCategory != .format
    }
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void) {
    let info = response.notification.request.content.userInfo
    guard response.notification.request.identifier.hasPrefix(prefix),
          let owner = info["owner"] as? String, let event = info["eventId"] as? String,
          valid(owner), valid(event) else { completionHandler(); return }
    DispatchQueue.main.async {
      self.pendingTap = ["owner": owner, "eventId": event]
      self.channel.invokeMethod("tap", arguments: nil)
      completionHandler()
    }
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.alert, .sound])
  }
}
