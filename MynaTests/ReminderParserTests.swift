import XCTest
@testable import Myna

final class ReminderParserTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testExplicitMinuteCommand() throws {
        let reminder = try XCTUnwrap(ReminderParser.parseCommand(
            "/remind 15m làm việc nọ việc kia", now: now
        ))
        XCTAssertEqual(reminder.title, "làm việc nọ việc kia")
        XCTAssertEqual(reminder.dueAt, now.addingTimeInterval(15 * 60))
    }

    func testHourAndLocalizedUnits() throws {
        let hours = try XCTUnwrap(ReminderParser.parseCommand("/remind 2h họp", now: now))
        XCTAssertEqual(hours.dueAt, now.addingTimeInterval(2 * 60 * 60))
        XCTAssertEqual(hours.title, "họp")

        let minutes = try XCTUnwrap(ReminderParser.parseCommand("/remind 30 phút uống nước", now: now))
        XCTAssertEqual(minutes.dueAt, now.addingTimeInterval(30 * 60))
        XCTAssertEqual(minutes.title, "uống nước")
    }

    func testOrdinaryTextNeverSchedules() throws {
        XCTAssertNil(try ReminderParser.parseCommand("15m nữa nhắc anh làm việc nọ việc kia", now: now))
        XCTAssertNil(try ReminderParser.parseCommand("ghi chú cuộc họp", now: now))
        XCTAssertNil(try ReminderParser.parseCommand("/feed subscribe https://example.com/rss", now: now))
        XCTAssertNil(try ReminderParser.parseCommand("/reminders 15m task", now: now))
        XCTAssertNil(try ReminderParser.parseCommand("/remindful 15m task", now: now))
        XCTAssertNil(try ReminderParser.parseCommand("/remind15m task", now: now))
    }

    func testMalformedCommandThrowsUsageError() {
        for command in ["/remind", "/remind 15m", "/remind abc task", "/remind 0m task",
                        "/remind 10081m task", "/remind 1d task"] {
            XCTAssertThrowsError(try ReminderParser.parseCommand(command, now: now), command) { error in
                XCTAssertTrue(error is ReminderCommandError)
            }
        }
    }
}
