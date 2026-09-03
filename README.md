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
signature. Under an ad-hoc signature every rebuild changes that signature and
macOS silently revokes both grants, so you re-approve after every single build.

An Apple Development certificate fixes this. The designated requirement then
binds to the bundle ID and the certificate rather than a binary hash:

```
identifier "dev.kuroko.Kuroko" and anchor apple generic and
certificate leaf[subject.CN] = "Apple Development: ..."
```

Rebuilds keep satisfying that, so the grants persist. A free Apple ID is
enough; the paid Developer Program is not needed. Add it in Xcode > Settings >
Accounts, then Manage Certificates > + > Apple Development. Set
`DEVELOPMENT_TEAM` in `project.yml` to the `OU` field of the certificate
subject.

Signing is Manual rather than Automatic on purpose. A macOS app signed for
local development needs no provisioning profile as long as its entitlements
don't require one, and ours don't, which avoids the profile dance entirely.

### If `find-identity` reports zero valid identities

A certificate can exist and still be invalid because its **intermediate** is
missing or expired. Check what is actually wrong:

```sh
security find-identity -p codesigning     # lists it even when invalid
security find-certificate -c "Apple Worldwide Developer Relations Certification Authority" \
  -p | openssl x509 -noout -subject -dates
```

Current certificates are issued by WWDR **G3**. The original WWDR intermediate
expired in February 2023, and if that is the only one in the keychain the chain
cannot be built. Install the current one:

```sh
curl -fsSLO https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
security add-certificates -k ~/Library/Keychains/login.keychain-db AppleWWDRCAG3.cer
```

After changing how the app is signed, clear the grants tied to the old
signature so the prompts come back cleanly:

```sh
for s in Accessibility ScreenCapture Microphone AppleEvents; do
  tccutil reset $s dev.kuroko.Kuroko
done
```

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
