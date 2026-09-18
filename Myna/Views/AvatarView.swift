import SwiftUI

/// Slack-dense monogram: blue for humans, purple sparkle for agents.
struct AvatarView: View {
    let authorType: AuthorType
    let displayName: String
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(authorType == .agent ? Color.purple.opacity(0.85) : Color.blue.opacity(0.85))
            if authorType == .agent {
                Image(systemName: "sparkles")
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
}
