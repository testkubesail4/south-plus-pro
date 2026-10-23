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
  private var notificationGeneration = 0
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
        content.body = "关注有新动态"
        content.sound = .default
        content.userInfo = ["owner": owner, "eventId": event]
        let ownerPrefix = self.prefix + Data(owner.utf8).base64EncodedString() + ":"
        let request = UNNotificationRequest(identifier: ownerPrefix + "summary", content: content, trigger: nil)
        let generation = self.notificationGeneration
        self.clearNotifications(prefix: ownerPrefix) {
          guard generation == self.notificationGeneration else { result(nil); return }
          self.center.add(request) { error in
            DispatchQueue.main.async {
              if error != nil {
                result(FlutterError(code: "notification_failed", message: "系统通知不可用", details: nil))
              } else { result(nil) }
            }
          }
        }
      case "openSettings":
        self.openSettings(result)
      case "cancelAll":
        self.notificationGeneration += 1
        self.pendingTap = nil
        self.clearNotifications(prefix: self.prefix) { result(nil) }
      case "takeTap":
        result(self.pendingTap)
        self.pendingTap = nil
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func openSettings(_ result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      guard let fallback = URL(string: UIApplication.openSettingsURLString) else {
        result(false); return
      }
      if #available(iOS 16.0, *),
         let notifications = URL(string: UIApplication.openNotificationSettingsURLString) {
        UIApplication.shared.open(notifications, options: [:]) { opened in
          if opened { result(true) }
          else { UIApplication.shared.open(fallback, options: [:]) { result($0) } }
        }
      } else {
        UIApplication.shared.open(fallback, options: [:]) { result($0) }
      }
    }
  }

  private func clearNotifications(prefix: String, completion: @escaping () -> Void) {
    let cancellation = DispatchGroup()
    cancellation.enter()
    center.getDeliveredNotifications { delivered in
      self.center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter { $0.hasPrefix(prefix) })
      cancellation.leave()
    }
    cancellation.enter()
    center.getPendingNotificationRequests { pending in
      self.center.removePendingNotificationRequests(withIdentifiers: pending.map { $0.identifier }.filter { $0.hasPrefix(prefix) })
      cancellation.leave()
    }
    cancellation.notify(queue: .main, execute: completion)
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
