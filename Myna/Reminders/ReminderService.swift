import Foundation
import Observation
import UserNotifications

struct ReminderRequest {
    let title: String
    let dueAt: Date
}

enum ReminderCommandError: LocalizedError {
    case invalidUsage

    var errorDescription: String? {
        "Use /remind 15m task or /remind 2h task (up to 7 days)."
    }
}

/// Only an explicit slash command can create a reminder.
enum ReminderParser {
    private static let pattern = try! NSRegularExpression(
        pattern: #"^/remind\s+(\d{1,5})\s*(m|phút|phut|h|giờ|gio)\s+(.+?)\s*$"#,
        options: [.caseInsensitive]
    )

    static func parseCommand(_ text: String, now: Date = Date()) throws -> ReminderRequest? {
        let command = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let commandName = command.prefix { !$0.isWhitespace }
        guard commandName.lowercased() == "/remind" else { return nil }
        let range = NSRange(command.startIndex..<command.endIndex, in: command)
        guard let match = pattern.firstMatch(in: command, range: range),
              let amountRange = Range(match.range(at: 1), in: command),
              let unitRange = Range(match.range(at: 2), in: command),
              let titleRange = Range(match.range(at: 3), in: command),
              let amount = Int(command[amountRange]) else { throw ReminderCommandError.invalidUsage }

        let unit = command[unitRange].lowercased()
        let minutes = (unit == "h" || unit == "giờ" || unit == "gio") ? amount * 60 : amount
        guard (1...10_080).contains(minutes) else { throw ReminderCommandError.invalidUsage }
        let title = command[titleRange].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ReminderCommandError.invalidUsage }
        return ReminderRequest(title: title, dueAt: now.addingTimeInterval(TimeInterval(minutes * 60)))
    }
}

enum ReminderError: LocalizedError {
    case permissionDenied
    case expired
    case destinationUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Enable notifications for Myna in Settings to receive reminders."
        case .expired:
            return "The reminder time has passed. Send it again to choose a new time."
        case .destinationUnavailable:
            return "This channel or thread is no longer available."
        }
    }
}

enum ReminderService {
    static let messageIDKey = "mynaMessageID"

    static func identifier(for messageID: UUID) -> String {
        "myna.reminder.\(messageID.uuidString)"
    }

    static func ensureAuthorization() async throws {
        let center = UNUserNotificationCenter.current()
        let allowed = try await center.requestAuthorization(options: [.alert, .sound])
        guard allowed else { throw ReminderError.permissionDenied }
    }

    static func schedule(_ reminder: ReminderRequest,
                         messageID: UUID) async throws {
        let center = UNUserNotificationCenter.current()
        let interval = reminder.dueAt.timeIntervalSinceNow
        guard interval > 0 else { throw ReminderError.expired }
        let content = UNMutableNotificationContent()
        content.title = "Myna reminder"
        content.body = reminder.title
        content.sound = .default
        content.userInfo = [messageIDKey: messageID.uuidString]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier(for: messageID),
                                            content: content, trigger: trigger)
        try await center.add(request)
    }

    static func cancel(for messageID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier(for: messageID)]
        )
    }
}

@MainActor
@Observable
final class ReminderNavigation {
    static let shared = ReminderNavigation()
    var pendingMessageID: UUID?

    private init() {}
}

final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let rawID = response.notification.request.content.userInfo[ReminderService.messageIDKey] as? String,
           let messageID = UUID(uuidString: rawID) {
            Task { @MainActor in
                ReminderNavigation.shared.pendingMessageID = messageID
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
