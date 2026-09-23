import SwiftUI

/// Owns top-level navigation selection so views stay declarative: which
/// channel is showing, which thread is open, and how the split view's columns
/// are arranged. Selection is by model id, so a thread can be targeted
/// independently of a channel — the shape a future deep link (e.g. from
/// search) can drive directly.
@Observable
final class NavigationModel {
    var columnVisibility: NavigationSplitViewVisibility = .automatic
    var selectedChannelID: UUID?
    var selectedThreadID: UUID?
    var focusedMessageID: UUID?

    func selectChannel(_ id: UUID) {
        if selectedChannelID != id {
            selectedThreadID = nil
            focusedMessageID = nil
        }
        selectedChannelID = id
    }

    func openThread(_ rootID: UUID, focusMessageID: UUID? = nil) {
        selectedThreadID = rootID
        focusedMessageID = focusMessageID
    }

    func closeThread() {
        selectedThreadID = nil
        focusedMessageID = nil
    }
}
