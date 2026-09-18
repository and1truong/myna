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
