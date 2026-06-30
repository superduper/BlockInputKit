import Foundation

/// Lightweight selection diagnostics that stay silent unless explicitly enabled by a host or test process.
enum BlockInputSelectionDebug {
    static let isEnabledKey = "BlockInputKitSelectionDebugEnabled"
    static let notificationName = Notification.Name("BlockInputKitSelectionDebugEvent")

    static func emit(_ message: @autoclosure () -> String) {
        guard UserDefaults.standard.bool(forKey: isEnabledKey) else {
            return
        }
        NotificationCenter.default.post(
            name: notificationName,
            object: nil,
            userInfo: ["message": message()]
        )
    }
}
