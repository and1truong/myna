import XCTest
@testable import Myna

final class NavigationModelTests: XCTestCase {
    private var navigation: NavigationModel!

    override func setUp() {
        navigation = NavigationModel()
    }

    func testSelectChannelSetsChannel() {
        let id = UUID()
        navigation.selectChannel(id)
        XCTAssertEqual(navigation.selectedChannelID, id)
    }

    func testSwitchingChannelClosesThread() {
        let channelA = UUID()
        let channelB = UUID()
        navigation.selectChannel(channelA)
        navigation.openThread(UUID())

        navigation.selectChannel(channelB)

        XCTAssertEqual(navigation.selectedChannelID, channelB)
        XCTAssertNil(navigation.selectedThreadID)
    }

    func testReselectingSameChannelKeepsThread() {
        let channel = UUID()
        let thread = UUID()
        navigation.selectChannel(channel)
        navigation.openThread(thread)

        navigation.selectChannel(channel)

        XCTAssertEqual(navigation.selectedThreadID, thread)
    }

    func testOpenThreadIsIndependentOfChannel() {
        let thread = UUID()
        navigation.openThread(thread)
        XCTAssertEqual(navigation.selectedThreadID, thread)
        XCTAssertNil(navigation.selectedChannelID)
    }

    func testCloseThreadKeepsChannel() {
        let channel = UUID()
        navigation.selectChannel(channel)
        navigation.openThread(UUID())

        navigation.closeThread()

        XCTAssertEqual(navigation.selectedChannelID, channel)
        XCTAssertNil(navigation.selectedThreadID)
    }

    func testReminderNavigationFocusesMessageInThread() {
        let channel = UUID()
        let root = UUID()
        let reply = UUID()

        navigation.selectChannel(channel)
        navigation.openThread(root, focusMessageID: reply)

        XCTAssertEqual(navigation.selectedChannelID, channel)
        XCTAssertEqual(navigation.selectedThreadID, root)
        XCTAssertEqual(navigation.focusedMessageID, reply)

        navigation.closeThread()
        XCTAssertNil(navigation.focusedMessageID)
    }
}
