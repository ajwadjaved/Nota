# Kuroko

A macOS agent that watches your screen, notices when you are stuck, and guides
you through it — in a floating overlay in the top-right corner and, when you
ask, out loud.

Named after the 黒子 of kabuki: the black-clad stage assistant who helps the
performer while the audience agrees not to see them.

Everything runs on-device. No API keys, no per-token cost, nothing leaves the
machine.

## Why it is built in tiers

Sending screenshots to a model on a timer is the obvious design and the wrong
one. At Claude's high-resolution tier a 3024x1964 screen costs 4,784 visual
tokens per frame, which is roughly $56/day on Haiku at one frame per second.
Running locally removes the dollars but not the latency or the battery drain, so
the same ladder applies: extract structured text where possible, and only wake a
model on a real event.

| Tier | What it does | Cost |
| ---- | ------------ | ---- |
| 0 | Accessibility observers and frontmost-app changes decide something happened at all | ~1 ms |
| 1 | Pull structured context: AX tree, AppleScript for Excel/Word/Numbers, Vision OCR as fallback | ~10-50 ms |
| 2 | Apple Foundation Models triages "does this need help?" from text alone | ~100 ms |
| 3 | Local Qwen3.5-VL via MLX writes the actual guidance | ~1-3 s |
| 4 | SpeechTranscriber in, Kokoro-82M out | ~180-500 ms to first audio |

Tier 2 is the load-bearing one. It is free and on-device, so it can run on every
screen event and keep the expensive vision model idle most of the time.

## Layout

```
app/Sources/        Swift menu-bar app: capture, Accessibility, speech, overlay
sidecar/            Python MLX sidecar: vision-language model + TTS
project.yml         XcodeGen spec; Kuroko.xcodeproj is generated, not committed
```

Swift owns OS integration because it is the only reasonable way to handle TCC
permissions, ScreenCaptureKit, the Accessibility API and `SpeechAnalyzer`.
Python owns inference because `mlx-vlm` and `mlx-audio` are far ahead of
`mlx-swift` for vision-language and TTS work.

## Requirements

- macOS 26 or later (Apple Foundation Models, `SpeechAnalyzer`)
- Apple Silicon; 48 GB unified memory comfortably runs Qwen3.6-27B-4bit
- Xcode 26, XcodeGen (`brew install xcodegen`)

## Build

```sh
xcodegen generate
xcodebuild -project Kuroko.xcodeproj -scheme Kuroko -configuration Debug \
  -derivedDataPath build build
open build/Build/Products/Debug/Kuroko.app
```

## Signing, and why it matters here

macOS keys Screen Recording and Accessibility grants to an app's code
signature. Under the ad-hoc signing that `project.yml` currently uses, every
rebuild changes that signature and macOS silently revokes both grants — you
re-approve after every build.

To fix it, add an Apple ID in Xcode > Settings > Accounts (a free one is
enough for local development), then replace the signing block in `project.yml`
with:

```yaml
CODE_SIGN_STYLE: Automatic
DEVELOPMENT_TEAM: <YOUR_TEAM_ID>
```

Find the team ID with `security find-identity -v -p codesigning`.

## Two constraints worth knowing early

**The overlay must be excluded from capture.** Screen capture uses
`SCContentFilter(display:excludingWindows:)` with the overlay's window ID.
Without it the model reads its own last suggestion off the screen and feeds it
back to itself.

**The App Sandbox has to stay off.** Accessibility access and sending Apple
events to arbitrary applications are both incompatible with it, which also
rules out Mac App Store distribution.

## Non-goals for v1

Kuroko does not click, type, or control anything. Guidance only. That keeps it
out of computer-use territory, where a wrong action has real consequences.

A cloud escape hatch for hard questions sits behind a `GuidanceProvider`
protocol so a hosted model can be added later without rearchitecting, but it is
deliberately unimplemented.
