import SwiftUI
import UIKit

/// Multiline composer. Hardware keyboard: Return sends, Shift+Return inserts a
/// newline (per spec). Touch keyboard: Return inserts a newline, the send button
/// posts. `@` opens agent autocomplete above the field.
struct ComposerView: View {
    let channel: Channel
    /// When set, posts land as thread replies under this root instead of in the channel.
    var root: Message? = nil
    var autofocus: Bool = false

    @Environment(\.modelContext) private var modelContext
    @State private var text = ""
    @State private var reminderError: String?
    @State private var isSchedulingReminder = false

    private let registry = AgentRegistry.default

    private var suggestions: [any MynaAgent] {
        guard let prefix = MentionParser.activeMentionPrefix(in: text) else { return [] }
        return registry.suggestions(forPrefix: prefix)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if !suggestions.isEmpty {
                suggestionList
            }
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                ComposerTextView(
                    text: $text,
                    placeholder: root == nil ? "Note in #\(channel.name)" : "Reply in thread",
                    autofocus: autofocus,
                    onSend: send
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 17))

                if isSchedulingReminder {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(canSend && !isSchedulingReminder ? Color.accentColor : Color(.tertiaryLabel))
                }
                .disabled(!canSend || isSchedulingReminder)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
        .alert("Reminder not set", isPresented: Binding(
            get: { reminderError != nil },
            set: { if !$0 { reminderError = nil } }
        )) {
            Button("OK") { reminderError = nil }
        } message: {
            Text(reminderError ?? "")
        }
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            Divider()
            ForEach(suggestions, id: \.id) { agent in
                Button {
                    text = MentionParser.completingMention(in: text, with: agent.name)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.purple)
                        Text("@\(agent.name)")
                            .font(.body.weight(.medium))
                        Text(agent.tagline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(.bar)
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSchedulingReminder else { return }
        do {
            if let reminder = try ReminderParser.parseCommand(trimmed) {
                sendReminder(reminder, commandText: trimmed)
                return
            }
        } catch {
            reminderError = error.localizedDescription
            return
        }
        let store = NoteStore(context: modelContext)
        let message: Message
        if let root {
            message = store.postReply(trimmed, to: root)
        } else {
            message = store.postMessage(trimmed, in: channel)
        }
        text = ""
        let service = AgentService(store: store, registry: registry)
        Task { await service.processMentions(in: message) }
    }

    private func sendReminder(_ reminder: ReminderRequest, commandText: String) {
        isSchedulingReminder = true
        let channelID = channel.id
        let rootID = root?.id
        let store = NoteStore(context: modelContext)
        Task { @MainActor in
            defer { isSchedulingReminder = false }
            do {
                try await ReminderService.ensureAuthorization()
                let currentRoot: Message?
                let currentChannel: Channel?
                if let rootID {
                    guard let savedRoot = store.message(withID: rootID) else {
                        throw ReminderError.destinationUnavailable
                    }
                    currentRoot = savedRoot
                    currentChannel = nil
                } else {
                    guard let savedChannel = store.channel(withID: channelID) else {
                        throw ReminderError.destinationUnavailable
                    }
                    currentRoot = nil
                    currentChannel = savedChannel
                }

                let anchor = try store.postReminderAnchor(reminder,
                                                          in: currentChannel,
                                                          replyingTo: currentRoot)
                let anchorID = anchor.id
                do {
                    try await ReminderService.schedule(reminder, messageID: anchorID)
                    guard let savedAnchor = store.message(withID: anchorID) else {
                        ReminderService.cancel(for: anchorID)
                        return
                    }
                    try store.setReminder(reminder, for: savedAnchor)
                    if text.trimmingCharacters(in: .whitespacesAndNewlines) == commandText {
                        text = ""
                    }
                } catch {
                    ReminderService.cancel(for: anchorID)
                    if let savedAnchor = store.message(withID: anchorID) {
                        store.delete(savedAnchor)
                    }
                    throw error
                }
            } catch {
                reminderError = error.localizedDescription
            }
        }
    }
}

/// UITextView wrapper: intercepts hardware Return so Enter sends and
/// Shift+Enter inserts a newline — impossible with SwiftUI's TextField.
private struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var autofocus: Bool
    var onSend: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> ComposerUITextView {
        let view = ComposerUITextView()
        view.delegate = context.coordinator
        view.onSend = onSend
        view.font = .preferredFont(forTextStyle: .body)
        view.textContainerInset = UIEdgeInsets(top: 7, left: 4, bottom: 7, right: 4)
        view.placeholderLabel.text = placeholder
        view.placeholderLabel.isHidden = !text.isEmpty
        if autofocus {
            DispatchQueue.main.async { view.becomeFirstResponder() }
        }
        return view
    }

    func updateUIView(_ view: ComposerUITextView, context: Context) {
        if view.text != text {
            view.text = text
            view.placeholderLabel.isHidden = !text.isEmpty
        }
        view.placeholderLabel.text = placeholder
        view.onSend = onSend
    }

    /// Grow with content up to a cap, then scroll — the Slack composer feel.
    func sizeThatFits(_ proposal: ProposedViewSize,
                      uiView: ComposerUITextView,
                      context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: min(max(fitting.height, 34), 110))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
            (textView as? ComposerUITextView)?.placeholderLabel.isHidden = !textView.text.isEmpty
        }
    }
}

private final class ComposerUITextView: UITextView {
    var onSend: () -> Void = {}

    let placeholderLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .placeholderText
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
        ])
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// UIPress events fire only for hardware keyboards. Return without Shift
    /// posts the message; Shift+Return falls through and inserts a newline.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if let key = presses.first?.key,
           key.keyCode == .keyboardReturnOrEnter,
           !key.modifierFlags.contains(.shift) {
            onSend()
            return
        }
        super.pressesBegan(presses, with: event)
    }
}
