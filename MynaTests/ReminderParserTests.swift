import XCTest
@testable import Myna

final class ReminderParserTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testVietnameseShortMinuteCommand() throws {
        let reminder = try XCTUnwrap(ReminderParser.parse(
            "15m nữa nhắc anh làm việc nọ việc kia", now: now
        ))
        XCTAssertEqual(reminder.title, "làm việc nọ việc kia")
        XCTAssertEqual(reminder.dueAt, now.addingTimeInterval(15 * 60))
    }

    func testSpelledOutMinuteAndHour() throws {
        let minutes = try XCTUnwrap(ReminderParser.parse("30 phút nữa nhắc tôi uống nước", now: now))
        XCTAssertEqual(minutes.dueAt, now.addingTimeInterval(30 * 60))
        XCTAssertEqual(minutes.title, "uống nước")

        let hours = try XCTUnwrap(ReminderParser.parse("2h nữa nhắc họp", now: now))
        XCTAssertEqual(hours.dueAt, now.addingTimeInterval(2 * 60 * 60))
        XCTAssertEqual(hours.title, "họp")

        let spelledHours = try XCTUnwrap(ReminderParser.parse("1 giờ nữa nhắc em gọi mẹ", now: now))
        XCTAssertEqual(spelledHours.dueAt, now.addingTimeInterval(60 * 60))
        XCTAssertEqual(spelledHours.title, "gọi mẹ")
    }

    func testOrdinaryAndInvalidMessagesDoNotSchedule() {
        XCTAssertNil(ReminderParser.parse("ghi chú cuộc họp", now: now))
        XCTAssertNil(ReminderParser.parse("0m nữa nhắc anh làm việc", now: now))
        XCTAssertNil(ReminderParser.parse("10081m nữa nhắc anh làm việc", now: now))
        XCTAssertNil(ReminderParser.parse("15m nữa nhắc anh", now: now))
        XCTAssertNil(ReminderParser.parse("15m nữa nhắc", now: now))
    }
}
