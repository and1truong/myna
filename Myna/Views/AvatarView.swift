import SwiftUI

/// Slack-dense monogram: blue for humans, purple for agents, green for feeds.
struct AvatarView: View {
    let authorType: AuthorType
    let displayName: String
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(avatarColor)
            if authorType == .agent {
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            } else if authorType == .feed {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Text(String(displayName.prefix(1)).uppercased())
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }

    private var avatarColor: Color {
        switch authorType {
        case .human: Color.blue.opacity(0.85)
        case .agent: Color.purple.opacity(0.85)
        case .feed: Color.green.opacity(0.85)
        }
    }
}
