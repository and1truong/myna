# Myna

A Slack-style personal note-taking app for iOS. Channels organize context, messages capture small atomic notes, threads let ideas grow, and AI agents participate via `@mention`.

## Requirements

- Xcode 26+ (Swift 5, iOS 17+ deployment target)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the project: `brew install xcodegen`

## Generate and build

```sh
xcodegen
xcodebuild -scheme Myna -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## Test

```sh
xcodebuild -scheme Myna -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## Slack channel feed

In a Myna channel, open the **Slack** tab and its settings. Create a Slack app in
your workspace, grant its bot `channels:read` and `channels:history` (plus
`groups:read` and `groups:history` if private channels are needed), install the
app, and invite the bot to each channel you want to import. Paste the `xoxb-`
bot token into Myna, load the channels the bot has joined, and select the ones
to show in that Myna channel. The token is kept in the device Keychain.

Myna imports the latest 50 posts on first sync and newer posts on later syncs.
Open the Slack tab or tap Refresh to sync. Each imported post links back to its
original Slack message. This is channel history polling, not a mirror of your
personal Slack notifications or an always-on push service. Slack API access and
rate limits depend on your workspace and app distribution; errors are shown in
the feed. Removing the token stops further sync; already imported posts stay on
the device as an archive.
