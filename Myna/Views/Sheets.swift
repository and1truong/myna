import SwiftData
import SwiftUI

/// "Move to channel…" — the core re-organization flow. Picking a channel moves
/// the root note and its whole thread transactionally; the stream updates
/// immediately.
struct MoveToChannelSheet: View {
    let message: Message

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Channel.position) private var channels: [Channel]

    var body: some View {
        NavigationStack {
            List {
                ForEach(channels) { channel in
                    Button {
                        NoteStore(context: modelContext).move(message, to: channel)
                        dismiss()
                    } label: {
                        HStack {
                            Label(channel.name, systemImage: "number")
                            Spacer()
                            if channel.id == message.effectiveChannel?.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(channel.id == message.effectiveChannel?.id)
                }
            }
            .navigationTitle("Move to channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct EditMessageSheet: View {
    let message: Message

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var draft: String

    init(message: Message) {
        self.message = message
        _draft = State(initialValue: message.content)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $draft)
                .padding(8)
                .navigationTitle("Edit note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            NoteStore(context: modelContext)
                                .edit(message, content: draft)
                            dismiss()
                        }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
        .presentationDetents([.medium])
    }
}

struct NewChannelSheet: View {
    var onCreate: (Channel) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""

    private var normalized: String { NoteStore.normalizeChannelName(name) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("channel-name", text: $name)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                if !normalized.isEmpty {
                    Text("Will be created as #\(normalized)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let channel = NoteStore(context: modelContext).createChannel(name: name)
                        dismiss()
                        onCreate(channel)
                    }
                    .disabled(normalized.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
