import Foundation
import Observation
import UserNotifications

struct ReminderRequest {
    let title: String
    let dueAt: Date
}

/// Deliberately narrow syntax so an ordinary note is not scheduled by accident.
enum ReminderParser {
    private static let pattern = try! NSRegularExpression(
        pattern: #"^\s*(\d{1,5})\s*(m|phút|phut|h|giờ|gio)\s+(?:nữa|nua)\s+nhắc\s+(.+?)\s*$"#,
        options: [.caseInsensitive]
    )

    static func parse(_ text: String, now: Date = Date()) -> ReminderRequest? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = pattern.firstMatch(in: text, range: range),
              let amountRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let titleRange = Range(match.range(at: 3), in: text),
              let amount = Int(text[amountRange]) else { return nil }

        let unit = text[unitRange].lowercased()
        let minutes = (unit == "h" || unit == "giờ" || unit == "gio") ? amount * 60 : amount
        guard (1...10_080).contains(minutes) else { return nil }
        let rawTitle = text[titleRange].trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String
        let words = rawTitle.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        if let first = words.first,
           ["anh", "em", "tôi", "toi", "mình", "minh"].contains(first.lowercased()) {
            title = words.count > 1 ? String(words[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        } else {
            title = rawTitle
        }
        guard !title.isEmpty else { return nil }
        return ReminderRequest(title: title, dueAt: now.addingTimeInterval(TimeInterval(minutes * 60)))
    }
}

enum ReminderError: LocalizedError {
    case permissionDenied
    case expired

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Enable notifications for Myna in Settings to receive reminders."
        case .expired:
            return "The reminder time has passed. Send it again to choose a new time."
        }
    }
}

enum ReminderService {
    static let messageIDKey = "mynaMessageID"

    static func identifier(for messageID: UUID) -> String {
        "myna.reminder.\(messageID.uuidString)"
    }

    static func schedule(_ reminder: ReminderRequest,
                         messageID: UUID) async throws {
        let center = UNUserNotificationCenter.current()
        let allowed = try await center.requestAuthorization(options: [.alert, .sound])
        guard allowed else { throw ReminderError.permissionDenied }

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
